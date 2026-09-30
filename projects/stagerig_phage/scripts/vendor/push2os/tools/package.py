"""Deterministic Push 2 package export, verification and leased installation/recovery."""
import argparse
import hashlib
import io
import json
import re
import stat
import sys
import subprocess
import tempfile
import unicodedata
import zipfile
from pathlib import Path, PurePosixPath

MAX_BYTES = 128 * 1024 * 1024
MANIFEST = 'push2os.manifest.json'


class PackageError(Exception):
    def __init__(self, code, message, path=None):
        super().__init__(message)
        self.code, self.path = code, path


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    """UTF-8 JSON, sorted object keys, compact separators, no terminal newline."""
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode('utf-8')


def validate_paths(names):
    seen = set()
    for name in names:
        if not isinstance(name, str) or not name or '\\' in name or ':' in name or '\x00' in name:
            raise PackageError('INVALID_PATH', 'Expected a portable relative POSIX file path', str(name))
        p = PurePosixPath(name)
        parts = name.split('/')
        if p.is_absolute() or any(x in ('', '.', '..') or x[-1:] in (' ', '.') for x in parts):
            raise PackageError('INVALID_PATH', 'Noncanonical or escaping path', name)
        for part in parts:
            if re.search(r'[<>"|?*\x00-\x1f]', part) or re.fullmatch(r'(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?', part):
                raise PackageError('INVALID_PATH', 'Unsupported Windows filename', name)
        key = unicodedata.normalize('NFC', name).casefold()
        if key in seen:
            raise PackageError('PATH_COLLISION', 'Duplicate or case-colliding path', name)
        seen.add(key)
    # Files cannot simultaneously act as parent directories.
    for name in seen:
        parts = name.split('/')
        if any('/'.join(parts[:i]) in seen for i in range(1, len(parts))):
            raise PackageError('PATH_COLLISION', 'File/directory prefix collision', name)


def git(source, *args):
    try:
        return subprocess.check_output(['git', '-C', str(source), *args], stderr=subprocess.PIPE).decode().strip()
    except subprocess.CalledProcessError as error:
        raise PackageError('GIT_PROVENANCE', error.stderr.decode(errors='replace')) from error


def export(source, output, version, development=False):
    source, output = Path(source).resolve(strict=True), Path(output).absolute()
    if output.resolve().is_relative_to(source):
        raise PackageError('OUTPUT_INSIDE_SOURCE', 'Artifact must be outside its source tree')
    if output.exists():
        raise PackageError('OUTPUT_EXISTS', 'Export never overwrites an existing artifact', str(output))
    metadata = json.loads((source / 'package.json').read_text(encoding='utf-8'))
    revision = git(source, 'rev-parse', 'HEAD')
    dirty = git(source, 'status', '--porcelain', '--', '.')
    if not development and dirty:
        raise PackageError('DIRTY_RELEASE', 'Release exports require a clean tracked source tree')
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', version):
        raise PackageError('INVALID_VERSION', 'Expected semantic version')
    if not development and not metadata.get('tested_host_revision'):
        raise PackageError('UNTESTED_HOST', 'Release requires a tested host revision')
    files = {}
    for path in sorted(source.rglob('*')):
        relative = path.relative_to(source).as_posix()
        if any(part in ('.git', '__pycache__') for part in path.relative_to(source).parts):
            continue
        if path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction()):
            raise PackageError('LINK_REFUSED', 'Source must contain local regular files', relative)
        if path.is_file():
            if not path.resolve().is_relative_to(source):
                raise PackageError('INVALID_PATH', 'Resolved source escapes package', relative)
            files[relative] = path.read_bytes()
    validate_paths([MANIFEST, *files])
    if not development:
        tracked = set(git(source, 'ls-files', '--', '.').splitlines())
        if set(files) != tracked:
            raise PackageError('UNTRACKED_RELEASE_BYTES', 'Release source must contain exactly tracked package files')
    if sum(map(len, files.values())) > MAX_BYTES:
        raise PackageError('SIZE_LIMIT', 'Package exceeds bounded source-package size')
    entries = [{'path': name, 'sha256': digest(data)} for name, data in sorted(files.items())]
    lock = {'format_version': 1, 'package': metadata['package'], 'package_version': version,
            'api_version': metadata['api_version'], 'data_schema_version': metadata['data_schema_version'],
            'source_revision': revision, 'development': development,
            'content_sha256': digest(canonical(entries)), 'files': entries,
            'host_requirements': metadata['host_requirements'],
            'tested_host_revision': metadata['tested_host_revision']}
    output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive final creation: even another exporter cannot replace a prior artifact.
    with tempfile.TemporaryDirectory(dir=output.parent, prefix='.push2os-export-') as temp:
        staged = Path(temp) / 'artifact.zip'
        with zipfile.ZipFile(staged, 'w', compression=zipfile.ZIP_STORED) as archive:
            for name, data in sorted({**files, MANIFEST: canonical(lock)}.items()):
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                archive.writestr(info, data)
        verify_artifact(staged)
        for name, data in files.items():
            if (source / name).read_bytes() != data:
                raise PackageError('SOURCE_CHANGED', 'Source changed during export', name)
        if git(source, 'rev-parse', 'HEAD') != revision or (not development and git(source, 'status', '--porcelain', '--', '.')):
            raise PackageError('SOURCE_CHANGED', 'Git source changed during export')
        with output.open('xb') as final:
            final.write(staged.read_bytes())
    return {'ok': True, 'action': 'export', 'code': 'EXPORTED', 'changes': [{'path': str(output), 'operation': 'create', 'after_sha256': digest(output.read_bytes())}], 'errors': [], 'lock': lock}


def verify_artifact(artifact):
    try:
        with zipfile.ZipFile(artifact) as archive:
            infos = archive.infolist()
            validate_paths([info.filename for info in infos])
            if sum(info.file_size for info in infos) > MAX_BYTES:
                raise PackageError('SIZE_LIMIT', 'Expanded package exceeds size limit')
            for info in infos:
                mode = info.external_attr >> 16
                if info.is_dir() or stat.S_ISLNK(mode) or (stat.S_IFMT(mode) not in (0, stat.S_IFREG)):
                    raise PackageError('LINK_REFUSED', 'Archive entries must be regular files', info.filename)
            raw = archive.read(MANIFEST)
            lock = json.loads(raw)
            if raw != canonical(lock):
                raise PackageError('MANIFEST_ENCODING', 'Manifest must use canonical encoding')
            if type(lock['format_version']) is not int or lock['format_version'] != 1 or lock['package'] != 'push2os':
                raise PackageError('UNSUPPORTED_MANIFEST', 'Unknown manifest format/package')
            for field in ('api_version', 'data_schema_version'):
                if type(lock[field]) is not int or lock[field] < 1:
                    raise PackageError('MANIFEST_SCHEMA', 'Positive integer required', field)
            if not isinstance(lock['package_version'], str) or not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', lock['package_version']):
                raise PackageError('MANIFEST_SCHEMA', 'Invalid package version')
            requirements = lock['host_requirements']
            if not isinstance(requirements, list) or not requirements or any(not isinstance(x, str) or not x for x in requirements) or len(set(requirements)) != len(requirements):
                raise PackageError('MANIFEST_SCHEMA', 'Unique host capability requirements required')
            tested = lock['tested_host_revision']
            if tested is not None and (not isinstance(tested, str) or not re.fullmatch('[a-f0-9]{40,64}', tested)):
                raise PackageError('MANIFEST_SCHEMA', 'Invalid tested host revision')
            entries = lock['files']
            if not isinstance(entries, list) or not entries:
                raise PackageError('MANIFEST_SCHEMA', 'Nonempty file manifest required')
            for entry in entries:
                if not isinstance(entry, dict) or set(entry) != {'path', 'sha256'} or not isinstance(entry['sha256'], str) or not re.fullmatch('[a-f0-9]{64}', entry['sha256']):
                    raise PackageError('MANIFEST_SCHEMA', 'Invalid file entry')
            validate_paths([entry['path'] for entry in entries])
            if entries != sorted(entries, key=lambda entry: entry['path']):
                raise PackageError('MANIFEST_ORDER', 'Manifest files must be sorted by path')
            if digest(canonical(entries)) != lock['content_sha256']:
                raise PackageError('CONTENT_HASH', 'Manifest content hash mismatch')
            if set(archive.namelist()) != {MANIFEST, *(entry['path'] for entry in entries)}:
                raise PackageError('FILE_SET', 'Archive and manifest owned files differ')
            for entry in entries:
                if digest(archive.read(entry['path'])) != entry['sha256']:
                    raise PackageError('FILE_HASH', 'File bytes do not match manifest', entry['path'])
            if not isinstance(lock['development'], bool) or not re.fullmatch('[a-f0-9]{40,64}', lock['source_revision']):
                raise PackageError('PROVENANCE', 'Invalid source provenance')
            if not lock['development'] and not lock.get('tested_host_revision'):
                raise PackageError('UNTESTED_HOST', 'Release lacks tested host revision')
            return {'ok': True, 'action': 'verify_artifact', 'code': 'VERIFIED', 'changes': [], 'errors': [], 'lock': lock}
    except (zipfile.BadZipFile, KeyError, TypeError, ValueError, UnicodeError, RuntimeError) as error:
        raise PackageError('CORRUPT_ARTIFACT', str(error)) from error


def verify(project, lock_path=None):
    """Read-only verification of owned vendor bytes; unknown files remain unowned."""
    project = Path(project).resolve(strict=True)
    lock_path = Path(lock_path) if lock_path else project / 'push2os.lock.json'
    if lock_path.is_symlink() or not lock_path.resolve().is_relative_to(project):
        raise PackageError('INVALID_LOCK_PATH', 'Lock must be a regular project-local file')
    lock = json.loads(lock_path.read_text(encoding='utf-8'))
    entries = lock['files']
    validate_paths([MANIFEST, *(entry['path'] for entry in entries)])
    vendor = project / 'scripts/vendor/push2os'
    buffer = io.BytesIO()
    total = 0
    with zipfile.ZipFile(buffer, 'w') as archive:
        archive.writestr(MANIFEST, canonical(lock))
        for entry in entries:
            path = vendor / entry['path']
            for parent in [path, *path.parents]:
                if parent == project:
                    break
                if parent.is_symlink() or (hasattr(parent, 'is_junction') and parent.is_junction()):
                    raise PackageError('LINK_REFUSED', 'Installed owned paths cannot traverse links', str(parent))
            if not path.resolve().is_relative_to(vendor.resolve()) or not vendor.resolve().is_relative_to(project):
                raise PackageError('INVALID_PATH', 'Installed path escapes vendor root', str(path))
            total += path.stat().st_size
            if total > MAX_BYTES:
                raise PackageError('SIZE_LIMIT', 'Installed package exceeds size limit')
            archive.writestr(entry['path'], path.read_bytes())
    buffer.seek(0)
    result = verify_artifact(buffer)
    result['action'] = 'verify'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    command = commands.add_parser('export')
    command.add_argument('--source', type=Path, required=True)
    command.add_argument('--output', type=Path, required=True)
    command.add_argument('--version', required=True)
    command.add_argument('--development', action='store_true')
    command = commands.add_parser('verify-artifact')
    command.add_argument('artifact', type=Path)
    command = commands.add_parser('verify')
    command.add_argument('--project', type=Path, required=True)
    command.add_argument('--lock', type=Path)
    command = commands.add_parser('install')
    command.add_argument('artifact',type=Path)
    command.add_argument('--project',type=Path,required=True)
    command.add_argument('--project-file',type=Path)
    command.add_argument('--apply',action='store_true')
    for action in ('rollback','recover'):
        command=commands.add_parser(action)
        command.add_argument('--project',type=Path,required=True)
        command.add_argument('--checkpoint',type=Path,required=True)
        command.add_argument('--apply',action='store_true')
    args = parser.parse_args()
    try:
        if args.action == 'export':
            result = export(args.source, args.output, args.version, args.development)
        elif args.action == 'verify':
            result = verify(args.project, args.lock)
        elif args.action in ('install','rollback','recover'):
            import activation
            if args.action=='install':
                result=activation.install(args.artifact,args.project,manifest=args.project_file,apply=args.apply)
            else:
                result=getattr(activation,args.action)(args.project,args.checkpoint,apply=args.apply)
        else:
            result = verify_artifact(args.artifact)
    except (PackageError, OSError, ValueError, KeyError, TypeError) as error:
        code = error.code if isinstance(error, PackageError) else 'IO_ERROR'
        result = {'ok': False, 'action': args.action, 'code': code, 'changes': [], 'errors': [{'code': code, 'path': getattr(error, 'path', None), 'message': str(error)}]}
    print(json.dumps(result, indent=2))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    # Keep one PackageError class when the CLI lazily imports activation.
    sys.modules['package']=sys.modules[__name__]
    raise SystemExit(main())
