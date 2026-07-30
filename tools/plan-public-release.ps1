[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$DestinationRoot,
    [string]$ConfigPath,
    [string]$ReportPath,
    [switch]$Apply,
    [string]$Approval,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

if (-not $SourceRoot) { $SourceRoot = Split-Path -Parent $PSScriptRoot }
if (-not $DestinationRoot) { $DestinationRoot = Join-Path (Split-Path -Parent $SourceRoot) 'sentinel-workspace-public' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'official-examples.config.psd1' }

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-IsUnder([string]$ParentPath, [string]$CandidatePath) {
    $parent = (Get-FullPath $ParentPath) + [IO.Path]::DirectorySeparatorChar
    $candidate = (Get-FullPath $CandidatePath) + [IO.Path]::DirectorySeparatorChar
    return $candidate.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)
}

function Get-TrackedFiles([string]$GitRoot, [string]$RelativePath) {
    $prefix = $RelativePath.Replace('\', '/').TrimEnd('/') + '/'
    return @(
        git -C $GitRoot ls-files -- $RelativePath |
            Where-Object { $_.Replace('\', '/').StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }
    )
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Release config is missing: $ConfigPath" }
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$sourceFull = Get-FullPath $SourceRoot
$destinationFull = Get-FullPath $DestinationRoot
if (-not (Test-Path -LiteralPath $sourceFull -PathType Container)) { throw "Source root does not exist: $sourceFull" }
if (-not (Test-Path -LiteralPath $destinationFull -PathType Container)) { throw "Destination root does not exist: $destinationFull" }
if ($sourceFull -eq $destinationFull) { throw 'Source and destination roots must differ.' }

if ($Apply -and $Approval -ne 'G1-approved') {
    throw 'Deletion apply refused: pass -Approval G1-approved only after the user explicitly approves Human Gate G1.'
}

$expectedProjects = @(
    $config.Projects.GetEnumerator() |
        Where-Object { $_.Value.Promote -ne $false } |
        ForEach-Object { [string]$_.Key } |
        Sort-Object
)
$reviewOnlyProjects = @(
    $config.Projects.GetEnumerator() |
        Where-Object { $_.Value.Promote -eq $false } |
        ForEach-Object { [string]$_.Key } |
        Sort-Object
)
$excludedProjects = @($config.ExcludedProjects | ForEach-Object { [string]$_ } | Sort-Object)
$exclusiveSharedPaths = @($config.ExclusiveSharedPaths | ForEach-Object { [string]$_ } | Sort-Object)

$trackedProjectFiles = @(git -C $destinationFull ls-files -- projects)
$actualProjects = @(
    $trackedProjectFiles |
        ForEach-Object {
            $normalized = $_.Replace('\', '/')
            if ($normalized -match '^projects/([^/]+)/') { $Matches[1] }
        } |
        Where-Object { $_ } |
        Sort-Object -Unique
)

$sourceText = [Collections.Generic.List[string]]::new()
foreach ($projectName in $expectedProjects) {
    $projectRoot = Join-Path $sourceFull "projects/$projectName"
    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $projectRoot -File -Recurse) {
        if ($file.Extension.ToLowerInvariant() -notin @('.sentinel', '.json', '.md', '.yaml', '.yml', '.hlsl', '.hlsli')) { continue }
        $sourceText.Add([IO.File]::ReadAllText($file.FullName).Replace('\', '/'))
    }
}
$includedCorpus = $sourceText -join "`n"

$operations = [Collections.Generic.List[object]]::new()
foreach ($projectName in $excludedProjects) {
    $relative = "projects/$projectName"
    $absolute = Get-FullPath (Join-Path $destinationFull $relative)
    $tracked = @(Get-TrackedFiles $destinationFull $relative)
    $operations.Add([pscustomobject]@{
        action = 'delete_directory'
        kind = 'excluded_project'
        path = $relative
        absolute_path = $absolute
        contained = Test-IsUnder $destinationFull $absolute
        tracked_file_count = $tracked.Count
        recoverable_from_commit = ($tracked.Count -gt 0)
        exists = Test-Path -LiteralPath $absolute -PathType Container
        referenced_by_included_project = $false
    })
}

foreach ($relative in $exclusiveSharedPaths) {
    $absolute = Get-FullPath (Join-Path $destinationFull $relative)
    $tracked = @(Get-TrackedFiles $destinationFull $relative)
    $normalized = $relative.Replace('\', '/')
    $referenced = $includedCorpus.IndexOf($normalized, [StringComparison]::OrdinalIgnoreCase) -ge 0
    $operations.Add([pscustomobject]@{
        action = 'delete_directory'
        kind = 'exclusive_shared_dependency'
        path = $normalized
        absolute_path = $absolute
        contained = Test-IsUnder $destinationFull $absolute
        tracked_file_count = $tracked.Count
        recoverable_from_commit = ($tracked.Count -gt 0)
        exists = Test-Path -LiteralPath $absolute -PathType Container
        referenced_by_included_project = $referenced
    })
}

$unsafe = @(
    $operations |
        Where-Object {
            -not $_.contained -or
            -not $_.recoverable_from_commit -or
            ($_.kind -eq 'exclusive_shared_dependency' -and $_.referenced_by_included_project)
        }
)

$sourceReadme = Join-Path $sourceFull 'README.md'
$staleLinks = [Collections.Generic.List[string]]::new()
if (Test-Path -LiteralPath $sourceReadme -PathType Leaf) {
    $readmeText = [IO.File]::ReadAllText($sourceReadme).Replace('\', '/')
    foreach ($projectName in $excludedProjects) {
        if ($readmeText.IndexOf("projects/$projectName", [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $staleLinks.Add("README.md -> projects/$projectName")
        }
    }
}

$projectedProjects = @(
    @($actualProjects | Where-Object { $_ -notin $excludedProjects -and $_ -notin $reviewOnlyProjects }) +
    $expectedProjects |
        Sort-Object -Unique
)
$missingAfterPlan = @($expectedProjects | Where-Object { $_ -notin $projectedProjects })
$unexpectedAfterPlan = @($projectedProjects | Where-Object { $_ -notin $expectedProjects })

if ($Apply) {
    if ($unsafe.Count -gt 0) {
        throw "Deletion apply refused: $($unsafe.Count) operation(s) are untracked, unsafe, or still referenced."
    }
    foreach ($operation in $operations) {
        $target = Get-FullPath $operation.absolute_path
        if (-not (Test-IsUnder $destinationFull $target)) { throw "Unsafe deletion target: $target" }
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Force -Recurse
        }
    }
}

$report = [pscustomobject]@{
    schema_version = 1
    mode = if ($Apply) { 'apply' } else { 'report-only' }
    source_root = $sourceFull
    destination_root = $destinationFull
    source_commit = (git -C $sourceFull rev-parse HEAD)
    public_commit = (git -C $destinationFull rev-parse HEAD)
    expected_projects = $expectedProjects
    actual_projects = $actualProjects
    projected_projects = $projectedProjects
    review_only_projects = $reviewOnlyProjects
    excluded = $excludedProjects
    missing_after_plan = $missingAfterPlan
    unexpected_after_plan = $unexpectedAfterPlan
    stale_links = @($staleLinks)
    destructive_operations = @($operations)
    unsafe_operations = @($unsafe)
    minimum_version = [string]$config.MinimumSentinelVersion
    live_proof_host_version = [string]$config.LiveProofHostVersion
    capability_command_count = [int]$config.CapabilityCommandCount
    capability_schema_hash = [string]$config.CapabilitySchemaHash
    exact_set_ready = ($missingAfterPlan.Count -eq 0 -and $unexpectedAfterPlan.Count -eq 0)
    apply_authorized = ($Apply -and $Approval -eq 'G1-approved')
    pushed = $false
}

$jsonText = $report | ConvertTo-Json -Depth 10
if ($ReportPath) {
    $reportFull = if ([IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $sourceFull $ReportPath }
    $parent = Split-Path -Parent $reportFull
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($reportFull, $jsonText + "`n", [Text.UTF8Encoding]::new($false))
}

if ($Json) {
    Write-Output $jsonText
} else {
    Write-Host ("Release plan {0}: {1} expected project(s), {2} deletion(s), exact-set ready={3}" -f $report.mode, $expectedProjects.Count, $operations.Count, $report.exact_set_ready)
    foreach ($operation in $operations) {
        Write-Host ("  DELETE {0} ({1} tracked files)" -f $operation.path, $operation.tracked_file_count)
    }
    if (-not $Apply) { Write-Host 'Report only. No files were removed.' }
}
