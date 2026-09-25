"""Owned-file activation with a durable checkpoint and native exclusive lease."""
import io
import json
import os
import uuid
import zipfile
from pathlib import Path
from package import PackageError, MAX_BYTES, MANIFEST, canonical, digest, validate_paths, verify, verify_artifact


def safe(root, path):
    path=Path(path)
    if not path.resolve().is_relative_to(root):
        raise PackageError('PATH_ESCAPE','Transaction path escapes project',str(path))
    for part in (path,*path.parents):
        if part==root: break
        if part.is_symlink() or (hasattr(part,'is_junction') and part.is_junction()):
            raise PackageError('LINK_REFUSED','Transaction paths must not traverse links',str(part))
    return path


def tree(root, path):
    safe(root,path)
    result={}
    if not path.exists(): return result
    if not path.is_dir(): raise PackageError('INVALID_VENDOR','Expected a directory',str(path))
    total=0
    for item in path.rglob('*'):
        safe(root,item)
        if item.is_file():
            total+=item.stat().st_size
            if total>MAX_BYTES: raise PackageError('SIZE_LIMIT','Vendor tree exceeds bounded package size')
            result[item.relative_to(path).as_posix()]=item.read_bytes()
    validate_paths(list(result))
    return result


def hashes(files): return {name:digest(data) for name,data in sorted(files.items())}


def write_atomic(root,path,data):
    safe(root,path)
    temporary=safe(root,path.with_name(path.name+'.tmp-'+uuid.uuid4().hex))
    with temporary.open('xb') as stream:
        stream.write(data);stream.flush();os.fsync(stream.fileno())
    os.replace(temporary,path)


def move(root,source,destination):
    safe(root,source);safe(root,destination)
    if destination.exists(): raise PackageError('DESTINATION_EXISTS','Refusing replacement of transaction backup',str(destination))
    os.replace(source,destination)


def project_file(project, supplied=None):
    root=Path(project).resolve(strict=True)
    if supplied is None:
        matches=list(root.glob('*.ctrl'))
        if len(matches)!=1: raise PackageError('AMBIGUOUS_PROJECT','Supply --project-file for the target .ctrl')
        supplied=matches[0]
    manifest=Path(supplied).resolve(strict=True)
    if manifest.parent!=root or not manifest.is_file():
        raise PackageError('PROJECT_MISMATCH','Target .ctrl must be directly inside the project')
    return root,manifest


class NativeLease:
    def __init__(self,manifest):
        self.manifest=manifest
        self.identity=None

    def request(self,command,**args):
        try:
            import zmq
            with zmq.Context.instance().socket(zmq.REQ) as socket:
                socket.setsockopt(zmq.LINGER,0)
                socket.setsockopt(zmq.RCVTIMEO,30000)
                socket.setsockopt(zmq.SNDTIMEO,30000)
                socket.connect('tcp://127.0.0.1:5556')
                socket.send_json({'cmd':command,**args})
                response=socket.recv_json()
            if response.get('status')!='ok': raise RuntimeError(response)
            return response['data']
        except Exception as error:
            raise PackageError('HOST_UNAVAILABLE','Native maintenance response unavailable: '+str(error)) from error

    def acquire(self,recovery_token=None):
        result=self.request('MAINTENANCE_ACQUIRE',path=str(self.manifest),token=recovery_token or '')
        if not result.get('ok') or not result.get('ready'):
            raise PackageError('LEASE_REFUSED',str(result))
        self.identity=result
        self.check()
        return result

    def check(self):
        status=self.status()
        if (not self.identity or not status.get('ok') or not status.get('ready') or
            status.get('token')!=self.identity['token'] or status.get('generation')!=self.identity['generation'] or
            status.get('current_generation')!=self.identity['generation'] or
            Path(status.get('project','')).resolve()!=self.manifest or status.get('module_count')!=0 or
            set(status.get('watchers',{}))!={'scripts','controllers','presets','sequences'} or
            any(w['running'] or w['pending'] for w in status['watchers'].values())):
            raise PackageError('LEASE_LOST','Maintenance identity or drained watcher state changed')
        return status

    def status(self): return self.request('MAINTENANCE_STATUS')

    def release(self):
        self.check()
        result=self.request('MAINTENANCE_RELEASE',token=self.identity['token'],generation=self.identity['generation'])
        if not result.get('ok'): raise PackageError('LEASE_RELEASE_FAILED',str(result))


def read_artifact(artifact):
    raw=Path(artifact).read_bytes() if isinstance(artifact,(str,Path)) else artifact
    lock=verify_artifact(io.BytesIO(raw))['lock']
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        files={entry['path']:archive.read(entry['path']) for entry in lock['files']}
    return lock,files


def current(root):
    lock_path=safe(root,root/'push2os.lock.json')
    raw=lock_path.read_bytes() if lock_path.exists() else None
    lock=verify(root)['lock'] if raw is not None else None
    files=tree(root,root/'scripts/vendor/push2os')
    return lock,raw,files


def plan(root,incoming,files):
    previous,old_raw,old=current(root)
    owned={e['path'] for e in previous['files']} if previous else set()
    unknown={n:b for n,b in old.items() if n not in owned}
    if {n.casefold() for n in unknown}&{n.casefold() for n in files}:
        raise PackageError('UNKNOWN_COLLISION','Incoming package would claim or overwrite unknown files')
    combined={**unknown,**files}
    validate_paths(list(combined))
    if sum(map(len,combined.values()))>MAX_BYTES:
        raise PackageError('SIZE_LIMIT','Combined package and unknown files exceed size limit')
    changes=[]
    for name in sorted(set(old)|set(combined)):
        before,after=old.get(name),combined.get(name)
        if before==after: continue
        changes.append({'path':'scripts/vendor/push2os/'+name,
            'operation':'create' if before is None else 'remove' if after is None else 'replace',
            'before_sha256':digest(before) if before is not None else None,
            'after_sha256':digest(after) if after is not None else None})
    new_raw=canonical(incoming) if incoming else None
    if old_raw!=new_raw:
        changes.append({'path':'push2os.lock.json','operation':'remove' if new_raw is None else 'replace' if old_raw else 'create',
            'before_sha256':digest(old_raw) if old_raw else None,'after_sha256':digest(new_raw) if new_raw else None})
    return previous,old_raw,old,combined,new_raw,changes


def save_journal(root,checkpoint,journal):
    write_atomic(root,checkpoint/'journal.json',canonical(journal))


def inspect_recovery(root,checkpoint,journal):
    """Read-only integrity validation before either preview or recovery."""
    vendor=root/'scripts/vendor/push2os'
    backup=checkpoint/'before-vendor'
    now=hashes(tree(root,vendor))
    before,after=journal['before_files'],journal['after_files']
    if now not in (before,after,{}) or (vendor.exists() and now=={} and before and after):
        raise PackageError('RECOVERY_CHANGED','Current vendor contains unrecognized bytes')
    oldlock=safe(root,checkpoint/'before-lock')
    previous=oldlock.read_bytes() if journal['before_lock'] is not None else None
    if previous is not None and digest(previous)!=journal['before_lock']:
        raise PackageError('CHECKPOINT_HASH','Original lock backup changed')
    lock=root/'push2os.lock.json'
    safe(root,lock);safe(root,oldlock)
    present=lock.read_bytes() if lock.exists() else None
    if (digest(present) if present is not None else None) not in (journal['before_lock'],journal['after_lock'],None):
        raise PackageError('RECOVERY_CHANGED','Current lock contains unrecognized bytes')
    if backup.exists():
        if hashes(tree(root,backup))!=before: raise PackageError('CHECKPOINT_HASH','Original vendor backup changed')
    elif journal['before_vendor_exists'] and (not vendor.exists() or now!=before):
        raise PackageError('CHECKPOINT_MISSING','Original vendor backup is unavailable')
    return vendor,backup,before,previous,lock


def restore(root,checkpoint,journal,lease):
    """Recover an interrupted activation. Never discard unrecognized current bytes."""
    lease.check()
    vendor,backup,before,previous,lock=inspect_recovery(root,checkpoint,journal)
    if backup.exists():
        if vendor.exists(): move(root,vendor,checkpoint/('discard-'+uuid.uuid4().hex))
        lease.check()
        move(root,backup,vendor)
    elif not journal['before_vendor_exists'] and vendor.exists():
        move(root,vendor,checkpoint/('discard-'+uuid.uuid4().hex))
    lease.check()
    if previous is None:
        if lock.exists(): move(root,lock,checkpoint/('discard-lock-'+uuid.uuid4().hex))
    else: write_atomic(root,lock,previous)
    if hashes(tree(root,vendor))!=before or (lock.read_bytes() if lock.exists() else None)!=previous:
        raise PackageError('RECOVERY_VERIFY','Original package and lock did not restore')
    journal['state']='restored';save_journal(root,checkpoint,journal)


def activate(incoming,files,project,manifest=None,apply=False,lease_factory=NativeLease,fault=None):
    root,manifest=project_file(project,manifest)
    baseline=plan(root,incoming,files)
    previous,old_raw,old,combined,new_raw,changes=baseline
    result={'ok':True,'action':'install','code':'DRY_RUN','changes':changes,'errors':[],'lock':incoming}
    if not apply: return result
    lease=lease_factory(manifest)
    identity=lease.acquire()
    checkpoint=None
    journal=None
    try:
        if plan(root,incoming,files)!=baseline: raise PackageError('TARGET_CHANGED','Target changed before lease acquisition')
        checkpoint=safe(root,root/'.push2os-transactions'/uuid.uuid4().hex)
        checkpoint.mkdir(parents=True,exist_ok=False)
        stage=checkpoint/'staged-vendor';stage.mkdir()
        for name,data in combined.items():
            target=safe(root,stage/name);target.parent.mkdir(parents=True,exist_ok=True)
            with target.open('xb') as stream:
                stream.write(data);stream.flush();os.fsync(stream.fileno())
        if old_raw is not None: write_atomic(root,checkpoint/'before-lock',old_raw)
        if new_raw is not None: write_atomic(root,checkpoint/'staged-lock',new_raw)
        vendor=safe(root,root/'scripts/vendor/push2os')
        vendor.parent.mkdir(parents=True,exist_ok=True)
        journal={'format_version':1,'project':str(root),'project_file':str(manifest),'state':'prepared',
            'lease':identity,'before_vendor_exists':vendor.exists(),'before_files':hashes(old),
            'after_files':hashes(combined),'before_lock':digest(old_raw) if old_raw is not None else None,
            'after_lock':digest(new_raw) if new_raw is not None else None}
        save_journal(root,checkpoint,journal)
        def boundary(name):
            lease.check();journal['state']=name;save_journal(root,checkpoint,journal)
            if fault: fault(name)
        boundary('before_replace')
        before_lock=safe(root,root/'push2os.lock.json')
        if (hashes(tree(root,vendor))!=journal['before_files'] or
            (before_lock.read_bytes() if before_lock.exists() else None)!=old_raw):
            raise PackageError('TARGET_CHANGED','Target changed during candidate preparation')
        if vendor.exists(): move(root,vendor,checkpoint/'before-vendor')
        boundary('old_vendor_moved')
        move(root,stage,vendor)
        boundary('new_vendor_moved')
        lock=safe(root,root/'push2os.lock.json')
        if new_raw is not None: os.replace(safe(root,checkpoint/'staged-lock'),lock)
        elif lock.exists(): move(root,lock,checkpoint/'removed-lock')
        boundary('lock_replaced')
        if incoming: verify(root)
        if hashes(tree(root,vendor))!=journal['after_files']:
            raise PackageError('ACTIVATION_VERIFY','Staged package or unknown files changed')
        boundary('verified')
        lease.release()
        journal['state']='complete';save_journal(root,checkpoint,journal)
        result.update(code='INSTALLED',checkpoint=str(checkpoint))
        return result
    except Exception as error:
        if journal is not None:
            try:
                restore(root,checkpoint,journal,lease)
                lease.release()
            except Exception as recovery:
                raise PackageError('RECOVERY_REQUIRED',f'{error}; recovery held: {recovery}',str(checkpoint)) from recovery
        else:
            lease.release()
        raise PackageError('ACTIVATION_ROLLED_BACK',str(error),str(checkpoint)) from error


def install(artifact,project,**kwargs):
    lock,files=read_artifact(artifact)
    return activate(lock,files,project,**kwargs)


def checkpoint_data(project,checkpoint):
    root=Path(project).resolve(strict=True)
    checkpoint=Path(checkpoint).absolute()
    safe(root,checkpoint)
    if checkpoint.parent!=root/'.push2os-transactions' or len(checkpoint.name)!=32 or any(c not in '0123456789abcdef' for c in checkpoint.name):
        raise PackageError('INVALID_CHECKPOINT','Expected a direct project-local transaction checkpoint')
    journal=json.loads(safe(root,checkpoint/'journal.json').read_text())
    if journal['format_version']!=1 or Path(journal['project']).resolve()!=root:
        raise PackageError('INVALID_CHECKPOINT','Checkpoint project/schema mismatch')
    project_file(root,journal['project_file'])
    for field in ('before_files','after_files'):
        validate_paths(list(journal[field]))
    return root,checkpoint,journal


def recover(project,checkpoint,apply=False,lease_factory=NativeLease):
    root,checkpoint,journal=checkpoint_data(project,checkpoint)
    if journal['state']=='complete':
        raise PackageError('NOT_INTERRUPTED','Use rollback for a completed installation')
    result={'ok':True,'action':'recover','code':'DRY_RUN','changes':[],'errors':[],'checkpoint':str(checkpoint)}
    inspect_recovery(root,checkpoint,journal)
    now=hashes(tree(root,root/'scripts/vendor/push2os'))
    for name in sorted(set(now)|set(journal['before_files'])):
        before,after=now.get(name),journal['before_files'].get(name)
        if before!=after:
            result['changes'].append({'path':'scripts/vendor/push2os/'+name,
                'operation':'remove' if after is None else 'create' if before is None else 'replace',
                'before_sha256':before,'after_sha256':after})
    live_lock=safe(root,root/'push2os.lock.json')
    live_lock_hash=digest(live_lock.read_bytes()) if live_lock.exists() else None
    if live_lock_hash!=journal['before_lock']:
        result['changes'].append({'path':'push2os.lock.json',
            'operation':'remove' if journal['before_lock'] is None else 'replace' if live_lock_hash else 'create',
            'before_sha256':live_lock_hash,'after_sha256':journal['before_lock']})
    if not apply: return result
    lease=lease_factory(Path(journal['project_file']))
    # The host may have acknowledged release just before the installer died.
    # No package writes are needed if the last verified state is already present.
    status=lease.status()
    if status.get('ok') and not status.get('held') and journal['state'] in ('verified','restored'):
        expected='after' if journal['state']=='verified' else 'before'
        lock=root/'push2os.lock.json'
        raw=lock.read_bytes() if lock.exists() else None
        if now!=journal[expected+'_files'] or (digest(raw) if raw is not None else None)!=journal[expected+'_lock']:
            raise PackageError('RECOVERY_CHANGED','Released transaction no longer matches verified state')
        if raw is not None: verify(root)
        journal['state']='complete' if expected=='after' else 'restored'
        save_journal(root,checkpoint,journal)
        result['code']='COMPLETED_AFTER_RELEASE' if expected=='after' else 'RECOVERED'
        return result
    # A surviving host may still hold the original ready lease. A restarted host
    # requires explicit re-acquisition with token rotation before any recovery write.
    lease.identity=journal['lease']
    try: lease.check()
    except PackageError:
        journal['lease']=lease.acquire(journal['lease']['token'])
        save_journal(root,checkpoint,journal)
    restore(root,checkpoint,journal,lease)
    lease.release()
    result['code']='RECOVERED'
    return result


def rollback(project,checkpoint,apply=False,lease_factory=NativeLease,fault=None):
    root,checkpoint,journal=checkpoint_data(project,checkpoint)
    if journal['state'] not in ('complete','verified'):
        raise PackageError('NOT_COMPLETE','Recover interrupted activation before rollback')
    backup=tree(root,checkpoint/'before-vendor')
    if hashes(backup)!=journal['before_files']:
        raise PackageError('CHECKPOINT_HASH','Original vendor backup changed')
    if journal['before_lock'] is None:
        lock,files=None,{}
    else:
        raw=safe(root,checkpoint/'before-lock').read_bytes()
        if digest(raw)!=journal['before_lock']: raise PackageError('CHECKPOINT_HASH','Original lock changed')
        lock=json.loads(raw)
        data=io.BytesIO()
        with zipfile.ZipFile(data,'w') as archive:
            archive.writestr(MANIFEST,canonical(lock))
            for entry in lock['files']: archive.writestr(entry['path'],backup[entry['path']])
        lock,files=read_artifact(data.getvalue())
    result=activate(lock,files,root,manifest=journal['project_file'],apply=apply,lease_factory=lease_factory,fault=fault)
    result['action']='rollback'
    if apply: result['code']='ROLLED_BACK'
    return result
