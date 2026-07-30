[CmdletBinding()]
param(
    [string]$Root,
    [string]$ConfigPath,
    [string]$SourceCommit
)

$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot 'official-examples.config.psd1'
}

$rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
$manifestPath = Join-Path $rootFull '.sentinel-workspace-manifest.json'
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Release config is missing: $ConfigPath"
}
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
if (-not $config.ContainsKey('WorkspaceManifest')) {
    throw 'Release config has no WorkspaceManifest policy.'
}

function Assert-SafeRelativePath([string]$Path, [string]$Context) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Context path is empty."
    }
    if ($Path.Contains('\')) {
        throw "$Context path must use forward slashes: $Path"
    }
    if ([IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('/') -or
        $Path.EndsWith('/') -or $Path.Contains('//') -or $Path.Contains(':')) {
        throw "$Context path is not a canonical relative file path: $Path"
    }
    $segments = @($Path -split '/')
    if (($segments | Where-Object { $_ -in @('', '.', '..') } | Measure-Object).Count -gt 0) {
        throw "$Context path contains an unsafe segment: $Path"
    }
    if ($segments[0].ToLowerInvariant() -in @('.git', '.release')) {
        throw "$Context path targets protected repository metadata: $Path"
    }
    return $Path
}

function Assert-Sha256([string]$Hash, [string]$Context) {
    if ($Hash -notmatch '^[0-9a-f]{64}$') {
        throw "$Context has an invalid SHA-256 value."
    }
    return $Hash
}

function Get-ManagedSha256([string]$Path, [string[]]$TextExtensions) {
    $name = [IO.Path]::GetFileName($Path)
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $isText = $extension -in $TextExtensions -or
        $name -in @('.gitignore', '.sentinel-workspace-version', 'LICENSE')
    if (-not $isText) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    # Hash canonical LF bytes so the install manifest is invariant to Git's
    # checkout-time CRLF conversion on Windows.
    $bytes = [IO.File]::ReadAllBytes($Path)
    $canonical = [Collections.Generic.List[byte]]::new($bytes.Length)
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        if ($bytes[$index] -eq 13) {
            if ($index + 1 -lt $bytes.Length -and $bytes[$index + 1] -eq 10) {
                $index++
            }
            $canonical.Add(10)
        } else {
            $canonical.Add($bytes[$index])
        }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($canonical.ToArray())) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

if (-not $SourceCommit) {
    $SourceCommit = (git -C $rootFull rev-parse HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'git rev-parse HEAD failed.' }
}
$SourceCommit = ([string]$SourceCommit).Trim()
if ($SourceCommit -notmatch '^[0-9a-fA-F]{40}$') {
    throw "SourceCommit must be a full 40-character Git commit id: $SourceCommit"
}

$candidateFiles = @(
    git -C $rootFull ls-files --cached --others --exclude-standard |
        ForEach-Object { $_.Replace('\', '/') } |
        Sort-Object -Unique
)
if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }

$projectPrefixes = @(
    $config.Projects.Keys |
        ForEach-Object { "projects/$($_)/" } |
        Sort-Object
)
$managedPrefixes = @(
    $config.WorkspaceManifest.Prefixes |
        ForEach-Object { ([string]$_).Replace('\', '/').Trim('/') + '/' } |
        Where-Object { $_ -notmatch '^projects/$' } |
        Sort-Object -Unique
)
$managedFiles = @(
    $config.WorkspaceManifest.Files |
        ForEach-Object { ([string]$_).Replace('\', '/').TrimStart('/') } |
        Sort-Object -Unique
)

$managedPaths = @(
    $candidateFiles |
        Where-Object {
            $path = $_
            if ($path -in $managedFiles) { return $true }
            if (@($managedPrefixes | Where-Object {
                $path.StartsWith($_, [StringComparison]::Ordinal)
            }).Count -gt 0) { return $true }
            return @($projectPrefixes | Where-Object {
                $path.StartsWith($_, [StringComparison]::Ordinal)
            }).Count -gt 0
        } |
        Sort-Object -Unique
)

$managedDuplicates = @(
    $managedPaths |
        Group-Object { $_.ToLowerInvariant() } |
        Where-Object { $_.Count -gt 1 }
)
if ($managedDuplicates.Count -gt 0) {
    throw "Managed paths collide by case: $(@($managedDuplicates.Name) -join ', ')"
}

$files = [Collections.Generic.List[object]]::new()
foreach ($relative in $managedPaths) {
    [void](Assert-SafeRelativePath $relative 'managed')
    $full = Join-Path $rootFull $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Managed file is absent from the working tree: $relative"
    }
    $files.Add([ordered]@{
        path = $relative
        sha256 = Get-ManagedSha256 $full @($config.TextExtensions)
    })
}

$priorFiles = @()
$priorOrphans = @()
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $prior = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    $priorFiles = @($prior.files)
    $priorOrphans = @($prior.orphan_candidates)
}

$priorEntries = @($priorOrphans) + @($priorFiles)
$priorDuplicatePaths = @(
    $priorEntries |
        Group-Object { ([string]$_.path).Replace('\', '/').ToLowerInvariant() } |
        Where-Object { $_.Count -gt 1 }
)
if ($priorDuplicatePaths.Count -gt 0) {
    throw "Prior workspace manifest has duplicate paths: $(@($priorDuplicatePaths.Name) -join ', ')"
}
foreach ($entry in $priorEntries) {
    $priorPath = [string]$entry.path
    [void](Assert-SafeRelativePath $priorPath 'prior manifest')
    [void](Assert-Sha256 ([string]$entry.sha256) "prior manifest entry '$priorPath'")
}

$managedLookup = @{}
foreach ($entry in $files) { $managedLookup[$entry.path.ToLowerInvariant()] = $true }
$orphanByPath = @{}
foreach ($entry in $priorEntries) {
    $path = [string]$entry.path
    if (-not $path) { continue }
    $key = $path.ToLowerInvariant()
    if ($managedLookup.ContainsKey($key)) { continue }
    $orphanByPath[$key] = [ordered]@{
        path = $path
        sha256 = ([string]$entry.sha256).ToLowerInvariant()
    }
}
$orphans = @(
    $orphanByPath.Values |
        Sort-Object { $_.path }
)

$manifest = [ordered]@{
    files = @($files)
    orphan_candidates = $orphans
    schema_version = 1
    source_commit = $SourceCommit.ToLowerInvariant()
}
$json = $manifest | ConvertTo-Json -Depth 6
$temporary = "$manifestPath.tmp"
[IO.File]::WriteAllText($temporary, $json + "`n", [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporary -Destination $manifestPath -Force

Write-Host (
    "Workspace manifest: {0} managed file(s), {1} orphan candidate(s), source {2}" -f
    $files.Count,
    $orphans.Count,
    $SourceCommit
)
