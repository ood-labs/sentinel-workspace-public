[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$DestinationRoot,
    [string[]]$Projects,
    [string]$ConfigPath,
    [string]$ReportPath,
    [switch]$Apply,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

if (-not $SourceRoot) { $SourceRoot = Split-Path -Parent $PSScriptRoot }
if (-not $DestinationRoot) { $DestinationRoot = Join-Path (Split-Path -Parent $SourceRoot) 'sentinel-workspace-public' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'official-examples.config.psd1' }

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Get-RelativePath([string]$BasePath, [string]$TargetPath) {
    $base = Get-FullPath $BasePath
    $target = Get-FullPath $TargetPath
    $baseUri = [Uri]($base.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar)
    $targetUri = [Uri]$target
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('\', '/').TrimEnd('/')
}

function Normalize-Relative([string]$Path) {
    return $Path.Replace('\', '/').TrimStart('./').TrimEnd('/')
}

function Test-IsUnder([string]$ParentPath, [string]$CandidatePath) {
    $parent = (Get-FullPath $ParentPath) + [IO.Path]::DirectorySeparatorChar
    $candidate = (Get-FullPath $CandidatePath) + [IO.Path]::DirectorySeparatorChar
    return $candidate.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)
}

function Get-ContentHash([string]$Path, [bool]$NormalizeText) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = if ($NormalizeText) {
            $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
            [Text.Encoding]::UTF8.GetBytes($text)
        } else {
            [IO.File]::ReadAllBytes($Path)
        }
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Test-Forbidden([IO.FileSystemInfo]$Entry, $Config) {
    if ($Entry.PSIsContainer) {
        $name = $Entry.Name.ToLowerInvariant()
        return ($name -in @($Config.ForbiddenDirectoryNames | ForEach-Object { $_.ToLowerInvariant() }) -or $name -match '^checkpoint(?:_|$)')
    }
    foreach ($pattern in $Config.ForbiddenFileNames) {
        if ($Entry.Name -like $pattern) { return $true }
    }
    return $false
}

function Add-FilesFromDirectory([string]$Directory, [string]$Root, [hashtable]$FileMap, $Config) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $Directory -File -Force -Recurse) {
        $blocked = $false
        $cursor = $file.Directory
        while ($cursor -and (Test-IsUnder $Directory $cursor.FullName)) {
            if (Test-Forbidden $cursor $Config) { $blocked = $true; break }
            if ((Get-FullPath $cursor.FullName) -eq (Get-FullPath $Directory)) { break }
            $cursor = $cursor.Parent
        }
        if ($blocked -or (Test-Forbidden $file $Config)) { continue }
        $relative = Normalize-Relative (Get-RelativePath $Root $file.FullName)
        $FileMap[$relative] = $file.FullName
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Official-example config is missing: $ConfigPath"
}
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$sourceFull = Get-FullPath $SourceRoot
$destinationFull = Get-FullPath $DestinationRoot

if (-not (Test-Path -LiteralPath $sourceFull -PathType Container)) { throw "Source root does not exist: $sourceFull" }
if (-not (Test-Path -LiteralPath $destinationFull -PathType Container)) { throw "Destination root does not exist: $destinationFull" }
if ($sourceFull -eq $destinationFull) { throw 'Source and destination roots must differ.' }

if (-not $PSBoundParameters.ContainsKey('Projects') -or $Projects.Count -eq 0) {
    $Projects = @(
        $config.Projects.GetEnumerator() |
            Where-Object { $_.Value.Promote -ne $false } |
            ForEach-Object { $_.Key } |
            Sort-Object
    )
}
$unknown = @($Projects | Where-Object { -not $config.Projects.ContainsKey($_) })
if ($unknown.Count -gt 0) { throw "Unknown official project(s): $($unknown -join ', ')" }
$reviewOnly = @($Projects | Where-Object { $config.Projects[$_].Promote -eq $false })
if ($reviewOnly.Count -gt 0) {
    throw "Promotion refuses review-only project(s): $($reviewOnly -join ', ')"
}

$fileMap = @{}
$replaceDirectories = [Collections.Generic.List[string]]::new()
$projectSummaries = [Collections.Generic.List[object]]::new()

foreach ($projectName in $Projects) {
    $definition = $config.Projects[$projectName]
    $projectRoot = Join-Path $sourceFull "projects/$projectName"
    $projectFileNames = if ($null -ne $definition.ProjectFiles) {
        @($definition.ProjectFiles)
    } else {
        @($definition.ProjectFile)
    }
    if ($projectFileNames.Count -eq 0) { throw "Official project '$projectName' has no project files configured." }
    $projectFiles = [Collections.Generic.List[string]]::new()
    $projectJsons = [Collections.Generic.List[object]]::new()
    $activeDirectories = [Collections.Generic.List[string]]::new()

    foreach ($projectFileName in $projectFileNames) {
        $projectFile = Join-Path $projectRoot $projectFileName
        if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) { throw "Project file is missing: $projectFile" }
        $projectFiles.Add($projectFile)
        $projectJsons.Add((Get-Content -Raw -LiteralPath $projectFile | ConvertFrom-Json))
        $projectRelative = Normalize-Relative (Get-RelativePath $sourceFull $projectFile)
        $fileMap[$projectRelative] = $projectFile
    }

    foreach ($pattern in $config.AllowedTopLevelFiles) {
        foreach ($file in Get-ChildItem -LiteralPath $projectRoot -File -Filter $pattern -ErrorAction SilentlyContinue) {
            if (Test-Forbidden $file $config) { continue }
            $relative = Normalize-Relative (Get-RelativePath $sourceFull $file.FullName)
            $fileMap[$relative] = $file.FullName
        }
    }
    foreach ($directoryName in $config.AllowedProjectDirectories) {
        if ($directoryName -eq 'modules') { continue }
        Add-FilesFromDirectory (Join-Path $projectRoot $directoryName) $sourceFull $fileMap $config
    }

    foreach ($projectJson in $projectJsons) {
        foreach ($pipeline in @($projectJson.pipelines)) {
            if ($pipeline.type -notin @('module', 'shaderproject')) { continue }
            $declared = [string]$pipeline.parameters.project_dir
            if ([string]::IsNullOrWhiteSpace($declared)) { throw "Module pipeline '$($pipeline.id)' in $projectName has no project_dir" }
            if ([IO.Path]::IsPathRooted($declared)) { throw "Promotion refuses absolute project_dir '$declared' in $projectName" }
            $resolved = Get-FullPath (Join-Path $projectRoot $declared)
            if (-not (Test-IsUnder $sourceFull $resolved)) { throw "Promotion path escapes the source workspace: $declared" }
            $workspaceRelative = Normalize-Relative (Get-RelativePath $sourceFull $resolved)
            $projectPrefix = "projects/$projectName/modules/"
            $approvedShared = @($definition.SharedModules | ForEach-Object { Normalize-Relative ([string]$_) })
            if (-not $workspaceRelative.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase) -and $workspaceRelative -notin $approvedShared) {
                throw "Promotion refuses non-allowlisted module '$workspaceRelative' in $projectName"
            }
            if (-not (Test-Path -LiteralPath (Join-Path $resolved 'manifest.yaml') -PathType Leaf)) {
                throw "Promotion cannot resolve active module '$workspaceRelative'"
            }
            if (-not $activeDirectories.Contains($workspaceRelative)) { $activeDirectories.Add($workspaceRelative) }
            Add-FilesFromDirectory $resolved $sourceFull $fileMap $config
        }
    }

    $projectShared = Join-Path $projectRoot 'modules/_shared'
    if (Test-Path -LiteralPath $projectShared -PathType Container) {
        Add-FilesFromDirectory $projectShared $sourceFull $fileMap $config
    }
    Add-FilesFromDirectory (Join-Path $sourceFull 'modules/_shared') $sourceFull $fileMap $config

    $replaceDirectories.Add("projects/$projectName")
    foreach ($activeDirectory in $activeDirectories) {
        if ($activeDirectory.StartsWith('modules/', [StringComparison]::OrdinalIgnoreCase) -and $activeDirectory -ne 'modules/_shared') {
            if (-not $replaceDirectories.Contains($activeDirectory)) { $replaceDirectories.Add($activeDirectory) }
        }
    }
    $projectSummaries.Add([pscustomobject]@{
        project = $projectName
        project_files = @($projectFiles | ForEach-Object { Normalize-Relative (Get-RelativePath $sourceFull $_) })
        active_modules = @($activeDirectories)
    })
}

foreach ($relative in @($fileMap.Keys)) {
    $segments = @($relative -split '/')
    $directorySegments = if ($segments.Count -gt 1) { @($segments[0..($segments.Count - 2)]) } else { @() }
    $blockedDirectory = $false
    foreach ($segment in $directorySegments) {
        $lower = $segment.ToLowerInvariant()
        if ($lower -in @($config.ForbiddenDirectoryNames | ForEach-Object { $_.ToLowerInvariant() }) -or
            $lower -match '^checkpoint(?:_|$)') {
            $blockedDirectory = $true
            break
        }
    }
    $blockedFile = $false
    foreach ($pattern in $config.ForbiddenFileNames) {
        if ($segments[-1] -like $pattern) { $blockedFile = $true; break }
    }
    if ($blockedDirectory -or $blockedFile) { $fileMap.Remove($relative) }
}

$operations = [Collections.Generic.List[object]]::new()
foreach ($relative in @($fileMap.Keys | Sort-Object)) {
    $sourcePath = $fileMap[$relative]
    $destinationPath = Join-Path $destinationFull $relative
    $isText = [IO.Path]::GetExtension($sourcePath).ToLowerInvariant() -in $config.TextExtensions
    $sourceHash = Get-ContentHash $sourcePath $isText
    $destinationHash = if (Test-Path -LiteralPath $destinationPath -PathType Leaf) { Get-ContentHash $destinationPath $isText } else { $null }
    $action = if (-not $destinationHash) { 'add' } elseif ($sourceHash -ne $destinationHash) { 'update' } else { 'unchanged' }
    $operations.Add([pscustomobject]@{
        action = $action
        path = $relative
        text_normalized = $isText
        source_sha256 = $sourceHash
        destination_sha256 = $destinationHash
    })
}

foreach ($relativeDirectory in $replaceDirectories) {
    $destinationDirectory = Join-Path $destinationFull $relativeDirectory
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $destinationDirectory -File -Force -Recurse) {
        $blocked = Test-Forbidden $file $config
        $cursor = $file.Directory
        while (-not $blocked -and $cursor -and (Test-IsUnder $destinationDirectory $cursor.FullName)) {
            if (Test-Forbidden $cursor $config) { $blocked = $true; break }
            if ((Get-FullPath $cursor.FullName) -eq (Get-FullPath $destinationDirectory)) { break }
            $cursor = $cursor.Parent
        }
        if ($blocked -or -not (Test-Path -LiteralPath $file.FullName -PathType Leaf)) { continue }
        $relative = Normalize-Relative (Get-RelativePath $destinationFull $file.FullName)
        if (-not $fileMap.ContainsKey($relative)) {
            $operations.Add([pscustomobject]@{
                action = 'delete'
                path = $relative
                text_normalized = $false
                source_sha256 = $null
                destination_sha256 = Get-ContentHash $file.FullName $false
            })
        }
    }
}

$validation = @()
if ($Apply) {
    foreach ($relativeDirectory in $replaceDirectories) {
        if ($relativeDirectory -eq 'modules/_shared') { continue }
        $targetDirectory = Get-FullPath (Join-Path $destinationFull $relativeDirectory)
        if (-not (Test-IsUnder $destinationFull $targetDirectory)) { throw "Unsafe replacement target: $targetDirectory" }
        if (Test-Path -LiteralPath $targetDirectory) { Remove-Item -LiteralPath $targetDirectory -Force -Recurse }
    }

    foreach ($relative in @($fileMap.Keys | Sort-Object)) {
        $sourcePath = $fileMap[$relative]
        $destinationPath = Join-Path $destinationFull $relative
        $parent = Split-Path -Parent $destinationPath
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }

    foreach ($relativeDirectory in @($replaceDirectories | Sort-Object -Unique)) {
        $targetDirectory = Get-FullPath (Join-Path $destinationFull $relativeDirectory)
        if (-not (Test-IsUnder $destinationFull $targetDirectory)) { throw "Unsafe cleanup target: $targetDirectory" }
        if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) { continue }

        $forbiddenFiles = @(Get-ChildItem -LiteralPath $targetDirectory -File -Force -Recurse |
            Where-Object { Test-Forbidden $_ $config })
        foreach ($file in $forbiddenFiles) { Remove-Item -LiteralPath $file.FullName -Force }

        $forbiddenDirectories = @(Get-ChildItem -LiteralPath $targetDirectory -Directory -Force -Recurse |
            Where-Object { Test-Forbidden $_ $config } |
            Sort-Object { $_.FullName.Length } -Descending)
        foreach ($directory in $forbiddenDirectories) {
            if (Test-Path -LiteralPath $directory.FullName) {
                Remove-Item -LiteralPath $directory.FullName -Force -Recurse
            }
        }
    }

    foreach ($operation in $operations | Where-Object { $_.action -ne 'delete' }) {
        $destinationPath = Join-Path $destinationFull $operation.path
        $destinationHash = Get-ContentHash $destinationPath ([bool]$operation.text_normalized)
        $operation.destination_sha256 = $destinationHash
        if ($destinationHash -ne $operation.source_sha256) {
            throw "Promoted content mismatch: $($operation.path)"
        }
    }

    $validator = Join-Path $PSScriptRoot 'validate-official-examples.ps1'
    $powerShellExe = (Get-Process -Id $PID).Path
    foreach ($projectName in $Projects) {
        $validationText = & $powerShellExe -NoProfile -File $validator -Root $destinationFull -Projects $projectName -ConfigPath $ConfigPath -Json
        $validationExit = $LASTEXITCODE
        $validationResult = ($validationText -join "`n") | ConvertFrom-Json
        $validation += $validationResult.projects[0]
        if ($validationExit -ne 0 -or -not $validationResult.portable) {
            throw "Promoted project '$projectName' failed validation."
        }
    }
}

$report = [pscustomobject]@{
    schema_version = 1
    mode = if ($Apply) { 'apply' } else { 'dry-run' }
    source_root = $sourceFull
    destination_root = $destinationFull
    projects = @($projectSummaries)
    operations = @($operations | Sort-Object path, action)
    validation = @($validation)
    changed = @($operations | Where-Object { $_.action -ne 'unchanged' }).Count
    pushed = $false
}

$jsonText = $report | ConvertTo-Json -Depth 10
if ($ReportPath) {
    $reportFull = if ([IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $sourceFull $ReportPath }
    $parent = Split-Path -Parent $reportFull
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    [IO.File]::WriteAllText($reportFull, $jsonText + "`n", [Text.UTF8Encoding]::new($false))
}

if ($Json) {
    Write-Output $jsonText
} else {
    Write-Host ("Promotion {0}: {1} project(s), {2} changed operation(s)" -f $report.mode, $Projects.Count, $report.changed)
    foreach ($operation in $report.operations | Where-Object { $_.action -ne 'unchanged' }) {
        Write-Host ("  {0,-6} {1}" -f $operation.action.ToUpperInvariant(), $operation.path)
    }
    if (-not $Apply) { Write-Host 'Dry-run only. Re-run with -Apply to copy and validate; this tool never pushes.' }
}
