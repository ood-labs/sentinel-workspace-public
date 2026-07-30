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

$files = [Collections.Generic.List[object]]::new()
foreach ($relative in $managedPaths) {
    $full = Join-Path $rootFull $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Managed file is absent from the working tree: $relative"
    }
    $files.Add([ordered]@{
        path = $relative
        sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
    })
}

$priorFiles = @()
$priorOrphans = @()
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $prior = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    $priorFiles = @($prior.files)
    $priorOrphans = @($prior.orphan_candidates)
}

$managedLookup = @{}
foreach ($entry in $files) { $managedLookup[$entry.path.ToLowerInvariant()] = $true }
$orphanByPath = @{}
foreach ($entry in @($priorOrphans) + @($priorFiles)) {
    $path = ([string]$entry.path).Replace('\', '/')
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
