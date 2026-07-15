[CmdletBinding()]
param(
    [string]$Root,
    [string[]]$Projects,
    [string]$ConfigPath,
    [string]$ReportPath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
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

function Get-NormalizedSha256([string]$Path) {
    $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Add-Unique([Collections.Generic.List[string]]$List, [string]$Value) {
    if (-not $List.Contains($Value)) { $List.Add($Value) }
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Official-example config is missing: $ConfigPath"
}

$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$rootFull = Get-FullPath $Root
if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
    throw "Workspace root does not exist: $rootFull"
}

if (-not $PSBoundParameters.ContainsKey('Projects') -or $Projects.Count -eq 0) {
    $Projects = @($config.Projects.Keys | Sort-Object)
}

$unknown = @($Projects | Where-Object { -not $config.Projects.ContainsKey($_) })
if ($unknown.Count -gt 0) {
    throw "Unknown official project(s): $($unknown -join ', ')"
}

$results = [Collections.Generic.List[object]]::new()

foreach ($projectName in $Projects) {
    $definition = $config.Projects[$projectName]
    $projectRoot = Join-Path $rootFull "projects/$projectName"
    $projectFile = Join-Path $projectRoot $definition.ProjectFile
    $errors = [Collections.Generic.List[string]]::new()
    $warnings = [Collections.Generic.List[string]]::new()
    $absolutePaths = [Collections.Generic.List[string]]::new()
    $forbiddenArtifacts = [Collections.Generic.List[string]]::new()
    $missingPaths = [Collections.Generic.List[string]]::new()
    $orphanModules = [Collections.Generic.List[string]]::new()
    $generatedStale = [Collections.Generic.List[string]]::new()
    $activeModules = [Collections.Generic.List[object]]::new()
    $compileResults = [Collections.Generic.List[object]]::new()
    $filesChecked = 0
    $projectJson = $null

    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        Add-Unique $missingPaths ("projects/{0}" -f $projectName)
        $errors.Add('project directory is missing')
    }

    if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
        Add-Unique $missingPaths ("projects/{0}/{1}" -f $projectName, $definition.ProjectFile)
        $errors.Add("project file '$($definition.ProjectFile)' is missing")
    } else {
        try {
            $projectJson = Get-Content -Raw -LiteralPath $projectFile | ConvertFrom-Json
        } catch {
            $errors.Add("project JSON is invalid: $($_.Exception.Message)")
        }
    }

    if ($projectJson) {
        foreach ($pipeline in @($projectJson.pipelines)) {
            if ($pipeline.type -notin @('module', 'shaderproject')) { continue }
            $declared = [string]$pipeline.parameters.project_dir
            if ([string]::IsNullOrWhiteSpace($declared)) {
                $errors.Add("module pipeline '$($pipeline.id)' has no project_dir")
                continue
            }

            if ([IO.Path]::IsPathRooted($declared)) {
                Add-Unique $absolutePaths ("{0}: {1}" -f $pipeline.id, $declared)
            }

            $resolved = if ([IO.Path]::IsPathRooted($declared)) {
                Get-FullPath $declared
            } else {
                Get-FullPath (Join-Path $projectRoot $declared)
            }
            $workspaceRelative = Normalize-Relative (Get-RelativePath $rootFull $resolved)
            $projectModulePrefix = "projects/$projectName/modules/"
            $approvedShared = @($definition.SharedModules | ForEach-Object { Normalize-Relative ([string]$_) })
            $isProjectModule = $workspaceRelative.StartsWith($projectModulePrefix, [StringComparison]::OrdinalIgnoreCase)
            $isApprovedShared = $workspaceRelative -in $approvedShared

            if (-not $isProjectModule -and -not $isApprovedShared) {
                $errors.Add("module pipeline '$($pipeline.id)' references non-allowlisted path '$workspaceRelative'")
            }
            if (-not (Test-Path -LiteralPath (Join-Path $resolved 'manifest.yaml') -PathType Leaf)) {
                Add-Unique $missingPaths "$workspaceRelative/manifest.yaml"
                $errors.Add("module pipeline '$($pipeline.id)' cannot resolve '$declared'")
            }

            $activeModules.Add([pscustomobject]@{
                pipeline = [string]$pipeline.id
                declared = $declared.Replace('\', '/')
                workspace_relative = $workspaceRelative
                resolved = $resolved
            })
            $compileResults.Add([pscustomobject]@{
                pipeline = [string]$pipeline.id
                module = $workspaceRelative
                status = 'not_run'
                note = 'Run sentinel_pipeline compile_check during the project proof slice.'
            })
        }

        $sceneGroups = @($projectJson.graph.nodes | Where-Object { $_.sceneGroup -eq $true })
        if ($sceneGroups.Count -lt [int]$definition.MinimumSceneGroups) {
            $errors.Add("needs at least $($definition.MinimumSceneGroups) Scene Group(s); found $($sceneGroups.Count)")
        }

        # Official examples intentionally use a flat group model. Nested groups are
        # not yet part of the supported example contract, whether expressed by graph
        # geometry or by a preset that recalls child-group presets.
        foreach ($outerGroup in $sceneGroups) {
            $outerLeft = [double]$outerGroup.posX
            $outerTop = [double]$outerGroup.posY
            $outerRight = $outerLeft + [double]$outerGroup.width
            $outerBottom = $outerTop + [double]$outerGroup.height

            foreach ($innerGroup in $sceneGroups) {
                if ($innerGroup.entityId -eq $outerGroup.entityId) { continue }
                $innerCenterX = [double]$innerGroup.posX + ([double]$innerGroup.width / 2.0)
                $innerCenterY = [double]$innerGroup.posY + ([double]$innerGroup.height / 2.0)
                if ($innerCenterX -gt $outerLeft -and $innerCenterX -lt $outerRight -and
                    $innerCenterY -gt $outerTop -and $innerCenterY -lt $outerBottom) {
                    $errors.Add("Scene Group '$($outerGroup.entityId)' contains Scene Group '$($innerGroup.entityId)'; official examples require flat groups")
                }
            }

            foreach ($groupPreset in @($outerGroup.sceneGroupPresets)) {
                $childPresetCount = 0
                if ($null -ne $groupPreset.childGroupPresets) {
                    $childPresetCount = @($groupPreset.childGroupPresets.PSObject.Properties).Count
                }
                if ($childPresetCount -gt 0) {
                    $errors.Add("Scene Group preset '$($groupPreset.name)' recalls $childPresetCount child group preset(s); official examples require flat groups")
                }
            }
        }

        if ([bool]$definition.RequiresGroupOutput) {
            $groupOutputs = @($projectJson.pipelines | Where-Object { $_.type -eq 'groupoutput' })
            if ($groupOutputs.Count -ne 1) {
                $errors.Add("needs exactly one Group Output; found $($groupOutputs.Count)")
            }
        }

        $maximumPresetCount = 0
        $hasPerformancePreset = $false
        $maximumExposedControls = 0
        foreach ($group in $sceneGroups) {
            $groupPresets = @($group.sceneGroupPresets)
            $maximumPresetCount = [Math]::Max($maximumPresetCount, $groupPresets.Count)
            if (@($groupPresets | Where-Object { $_.name -eq 'Performance' }).Count -gt 0) {
                $hasPerformancePreset = $true
            }
            $maximumExposedControls = [Math]::Max($maximumExposedControls, @($group.sceneGroupParameters).Count)
        }
        if ($maximumPresetCount -lt [int]$definition.MinimumGroupPresets) {
            $errors.Add("needs a Scene Group with at least $($definition.MinimumGroupPresets) presets; found $maximumPresetCount")
        }
        $exemptions = @($definition.Exemptions)
        if ($projectName -ne 'interaction_lab' -and 'scene-group-presets' -notin $exemptions -and -not $hasPerformancePreset) {
            $errors.Add("needs a Scene Group preset named 'Performance'")
        }
        if ($projectName -ne 'interaction_lab' -and 'scene-group-controls' -notin $exemptions -and ($maximumExposedControls -lt 6 -or $maximumExposedControls -gt 10)) {
            $errors.Add("top-level Scene Group must expose 6-10 controls; found $maximumExposedControls")
        }

        $nodePresetCount = @($projectJson.nodePresets).Count
        if ($nodePresetCount -lt [int]$definition.MinimumNodePresets) {
            $errors.Add("needs at least $($definition.MinimumNodePresets) project-scoped node presets; found $nodePresetCount")
        }
    }

    if (Test-Path -LiteralPath $projectRoot -PathType Container) {
        $readmes = @(Get-ChildItem -LiteralPath $projectRoot -File -Filter 'README*' -ErrorAction SilentlyContinue)
        if ($readmes.Count -eq 0) {
            Add-Unique $missingPaths "projects/$projectName/README.md"
            $errors.Add('user-facing README is missing')
        }

        $proofRoot = Join-Path $projectRoot 'proof'
        $proofFiles = if (Test-Path -LiteralPath $proofRoot -PathType Container) {
            @(Get-ChildItem -LiteralPath $proofRoot -File -Recurse -ErrorAction SilentlyContinue)
        } else { @() }
        if ($proofFiles.Count -eq 0) {
            Add-Unique $missingPaths "projects/$projectName/proof"
            $errors.Add('compact proof bundle is missing or empty')
        }

        $allEntries = @(Get-ChildItem -LiteralPath $projectRoot -Force -Recurse -ErrorAction SilentlyContinue)
        foreach ($entry in $allEntries) {
            $relative = Normalize-Relative (Get-RelativePath $rootFull $entry.FullName)
            if ($entry.PSIsContainer) {
                $name = $entry.Name.ToLowerInvariant()
                if ($name -in @($config.ForbiddenDirectoryNames | ForEach-Object { $_.ToLowerInvariant() }) -or $name -match '^checkpoint(?:_|$)') {
                    Add-Unique $forbiddenArtifacts $relative
                }
                continue
            }

            $filesChecked++
            foreach ($pattern in $config.ForbiddenFileNames) {
                if ($entry.Name -like $pattern) {
                    Add-Unique $forbiddenArtifacts $relative
                    break
                }
            }

            if ($entry.Extension.ToLowerInvariant() -in $config.TextExtensions) {
                $lineNumber = 0
                foreach ($line in Get-Content -LiteralPath $entry.FullName -ErrorAction SilentlyContinue) {
                    $lineNumber++
                    # The negative lookbehind avoids treating URL schemes such as
                    # "http:/" as drive paths while still catching C:/ and C:\.
                    if ($line -match '(?i)(?:(?<![A-Z])[A-Z]:[\\/]|/Users/|/home/)') {
                        Add-Unique $absolutePaths ("{0}:{1}" -f $relative, $lineNumber)
                    }
                }
            }
        }

        $moduleRoot = Join-Path $projectRoot 'modules'
        if (Test-Path -LiteralPath $moduleRoot -PathType Container) {
            $activeProjectModules = @($activeModules | Where-Object {
                $_.workspace_relative.StartsWith("projects/$projectName/modules/", [StringComparison]::OrdinalIgnoreCase)
            } | ForEach-Object { $_.workspace_relative.ToLowerInvariant() })
            foreach ($moduleDir in Get-ChildItem -LiteralPath $moduleRoot -Directory -ErrorAction SilentlyContinue) {
                if ($moduleDir.Name -eq '_shared') { continue }
                if (-not (Test-Path -LiteralPath (Join-Path $moduleDir.FullName 'manifest.yaml') -PathType Leaf)) { continue }
                $relative = Normalize-Relative (Get-RelativePath $rootFull $moduleDir.FullName)
                if ($relative.ToLowerInvariant() -notin $activeProjectModules) {
                    Add-Unique $orphanModules $relative
                }
            }
        }
    }

    foreach ($module in $activeModules) {
        $manifestPath = Join-Path $module.resolved 'manifest.yaml'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
        $manifestText = [IO.File]::ReadAllText($manifestPath).Replace("`r`n", "`n").Replace("`r", "`n")
        $generatedPath = Join-Path $module.resolved '_ui.generated.hlsli'
        $declaresControls = $manifestText -match '(?m)^\s+controls\s*:'
        if (-not $declaresControls -and -not (Test-Path -LiteralPath $generatedPath -PathType Leaf)) { continue }
        if (-not (Test-Path -LiteralPath $generatedPath -PathType Leaf)) {
            Add-Unique $generatedStale "$($module.workspace_relative)/_ui.generated.hlsli (missing)"
            continue
        }
        $headerText = [IO.File]::ReadAllText($generatedPath)
        $headerMatch = [regex]::Match($headerText, 'manifest-sha256:\s*([0-9a-fA-F]{64})')
        $expectedHash = Get-NormalizedSha256 $manifestPath
        if (-not $headerMatch.Success -or $headerMatch.Groups[1].Value.ToLowerInvariant() -ne $expectedHash) {
            Add-Unique $generatedStale "$($module.workspace_relative)/_ui.generated.hlsli"
        }
    }

    foreach ($path in $absolutePaths) { $errors.Add("absolute path: $path") }
    foreach ($path in $forbiddenArtifacts) { $errors.Add("forbidden artifact: $path") }
    foreach ($path in $orphanModules) { $errors.Add("orphan module: $path") }
    foreach ($path in $generatedStale) { $errors.Add("stale generated UI: $path") }

    $results.Add([pscustomobject]@{
        project = $projectName
        files_checked = $filesChecked
        active_modules = @($activeModules)
        orphan_modules = @($orphanModules)
        absolute_paths = @($absolutePaths)
        forbidden_artifacts = @($forbiddenArtifacts)
        missing_paths = @($missingPaths)
        generated_stale = @($generatedStale)
        compile_results = @($compileResults)
        exemptions = @($definition.Exemptions)
        portable = ($errors.Count -eq 0)
        errors = @($errors)
        warnings = @($warnings)
    })
}

$aggregate = [pscustomobject]@{
    schema_version = 1
    root = $rootFull
    minimum_sentinel_version = $config.MinimumSentinelVersion
    project_count = $results.Count
    passed = @($results | Where-Object portable).Count
    failed = @($results | Where-Object { -not $_.portable }).Count
    portable = (@($results | Where-Object { -not $_.portable }).Count -eq 0)
    projects = @($results)
}

$jsonText = $aggregate | ConvertTo-Json -Depth 10
if ($ReportPath) {
    $reportFull = if ([IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $rootFull $ReportPath }
    $parent = Split-Path -Parent $reportFull
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    [IO.File]::WriteAllText($reportFull, $jsonText + "`n", [Text.UTF8Encoding]::new($false))
}

if ($Json) {
    Write-Output $jsonText
} else {
    foreach ($result in $results) {
        $state = if ($result.portable) { 'PASS' } else { 'FAIL' }
        Write-Host ("{0} {1}: {2} active, {3} orphan, {4} errors" -f $state, $result.project, $result.active_modules.Count, $result.orphan_modules.Count, $result.errors.Count)
        foreach ($errorText in $result.errors) { Write-Host "  - $errorText" }
    }
    Write-Host ("Official examples: {0} passed, {1} failed" -f $aggregate.passed, $aggregate.failed)
}

if (-not $aggregate.portable) { exit 1 }

