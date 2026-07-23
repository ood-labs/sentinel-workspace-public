[CmdletBinding()]
param(
    [string[]]$Roots,
    [switch]$Apply,
    [string]$BackupRoot
)

$ErrorActionPreference = 'Stop'

if (-not $Roots -or $Roots.Count -eq 0) {
    $privateRoot = Split-Path -Parent $PSScriptRoot
    $publicRoot = Join-Path (Split-Path -Parent $privateRoot) 'sentinel-workspace-public'
    $Roots = @($privateRoot, $publicRoot)
}

if (-not $BackupRoot) {
    $workspaceRoot = Split-Path -Parent $PSScriptRoot
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $BackupRoot = Join-Path $workspaceRoot "captures/scene_group_preset_repair_$stamp"
}

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-IsUnder([string]$ParentPath, [string]$CandidatePath) {
    $parent = (Get-FullPath $ParentPath) + [IO.Path]::DirectorySeparatorChar
    $candidate = Get-FullPath $CandidatePath
    return $candidate.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)
}

function Get-SceneGroupPresetSpans([string]$Text) {
    $marker = [regex]::new('"sceneGroupPresets"\s*:\s*\[')
    $search = 0
    $spans = [Collections.Generic.List[object]]::new()

    while (($match = $marker.Match($Text, $search)).Success) {
        $start = $match.Index
        $arrayStart = $Text.IndexOf('[', $start)
        $depth = 0
        $inString = $false
        $escape = $false
        $end = -1

        for ($i = $arrayStart; $i -lt $Text.Length; $i++) {
            $ch = $Text[$i]
            if ($inString) {
                if ($escape) {
                    $escape = $false
                } elseif ($ch -eq '\') {
                    $escape = $true
                } elseif ($ch -eq '"') {
                    $inString = $false
                }
                continue
            }

            if ($ch -eq '"') {
                $inString = $true
            } elseif ($ch -eq '[') {
                $depth++
            } elseif ($ch -eq ']') {
                $depth--
                if ($depth -eq 0) {
                    $end = $i
                    break
                }
            }
        }

        if ($end -lt 0) {
            throw "Unclosed sceneGroupPresets array at character $start"
        }

        $spans.Add([pscustomobject]@{ Start = $start; End = $end })
        $search = $end + 1
    }

    return $spans
}

function Remove-PresetProjectDirs([string]$Text) {
    $spans = @(Get-SceneGroupPresetSpans $Text)
    $removed = 0

    for ($spanIndex = $spans.Count - 1; $spanIndex -ge 0; $spanIndex--) {
        $span = $spans[$spanIndex]
        $block = $Text.Substring($span.Start, $span.End - $span.Start + 1)
        $lines = [regex]::Split($block, '(?<=\n)')
        $output = [Collections.Generic.List[string]]::new()

        foreach ($line in $lines) {
            if ($line -notmatch '^[ \t]*"project_dir":\s*"[^"\r\n]*",?[ \t]*(?:\r?\n)?$') {
                $output.Add($line)
                continue
            }

            $withoutNewline = $line.TrimEnd("`r", "`n").TrimEnd()
            if (-not $withoutNewline.EndsWith(',', [StringComparison]::Ordinal)) {
                for ($previous = $output.Count - 1; $previous -ge 0; $previous--) {
                    if ([string]::IsNullOrWhiteSpace($output[$previous])) { continue }
                    $output[$previous] = [regex]::Replace($output[$previous], ',([ \t]*)(\r?\n)?$', '$1$2')
                    break
                }
            }
            $removed++
        }

        $newBlock = [string]::Concat($output)
        $Text = $Text.Substring(0, $span.Start) + $newBlock + $Text.Substring($span.End + 1)
    }

    return [pscustomobject]@{ Text = $Text; Removed = $removed; GroupCount = $spans.Count }
}

function Get-PresetProjectDirCount($ProjectJson) {
    $count = 0
    foreach ($node in @($ProjectJson.graph.nodes)) {
        foreach ($preset in @($node.sceneGroupPresets)) {
            if ($null -eq $preset) { continue }
            foreach ($pipeline in $preset.pipelineValues.PSObject.Properties) {
                if ($pipeline.Value.PSObject.Properties.Name -contains 'project_dir') { $count++ }
            }
        }
    }
    return $count
}

function Get-TopLevelProjectDirs($ProjectJson) {
    $values = [Collections.Generic.List[string]]::new()
    foreach ($pipeline in @($ProjectJson.pipelines)) {
        if ($pipeline.parameters.PSObject.Properties.Name -contains 'project_dir') {
            $values.Add([string]$pipeline.parameters.project_dir)
        }
    }
    return @($values)
}

$results = [Collections.Generic.List[object]]::new()

foreach ($rootInput in $Roots) {
    $root = Get-FullPath $rootInput
    $projectsRoot = Join-Path $root 'projects'
    if (-not (Test-Path -LiteralPath $projectsRoot -PathType Container)) { continue }

    foreach ($projectDir in Get-ChildItem -LiteralPath $projectsRoot -Directory | Sort-Object Name) {
        foreach ($projectFile in Get-ChildItem -LiteralPath $projectDir.FullName -File -Filter '*.sentinel' | Sort-Object Name) {
            if (-not (Test-IsUnder $projectsRoot $projectFile.FullName)) {
                throw "Project file escaped the expected root: $($projectFile.FullName)"
            }

            $beforeText = [IO.File]::ReadAllText($projectFile.FullName)
            if ($beforeText -notmatch '"sceneGroupPresets"\s*:\s*\[') { continue }

            $beforeJson = $beforeText | ConvertFrom-Json
            $beforeCount = Get-PresetProjectDirCount $beforeJson
            $topLevelBefore = @(Get-TopLevelProjectDirs $beforeJson)
            $repair = Remove-PresetProjectDirs $beforeText
            $afterJson = $repair.Text | ConvertFrom-Json
            $afterCount = Get-PresetProjectDirCount $afterJson
            $topLevelAfter = @(Get-TopLevelProjectDirs $afterJson)

            if ($afterCount -ne 0) {
                throw "Preset project_dir entries remain in $($projectFile.FullName): $afterCount"
            }
            if (($topLevelBefore -join "`n") -ne ($topLevelAfter -join "`n")) {
                throw "Top-level module paths changed unexpectedly in $($projectFile.FullName)"
            }

            $changed = $beforeText -cne $repair.Text
            $backupPath = ''
            if ($Apply -and $changed) {
                $rootLabel = Split-Path $root -Leaf
                $backupDir = Join-Path $BackupRoot "$rootLabel/$($projectDir.Name)"
                New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
                $backupPath = Join-Path $backupDir $projectFile.Name
                Copy-Item -LiteralPath $projectFile.FullName -Destination $backupPath -Force
                [IO.File]::WriteAllText($projectFile.FullName, $repair.Text, [Text.UTF8Encoding]::new($false))
            }

            $results.Add([pscustomobject]@{
                root = $root
                project = $projectDir.Name
                file = $projectFile.Name
                scene_groups = $repair.GroupCount
                before = $beforeCount
                removed = $repair.Removed
                after = $afterCount
                top_level_paths = $topLevelAfter.Count
                changed = $changed
                applied = [bool]($Apply -and $changed)
                backup = $backupPath
            })
        }
    }
}

$summary = [pscustomobject]@{
    mode = $(if ($Apply) { 'apply' } else { 'dry_run' })
    roots = @($Roots | ForEach-Object { Get-FullPath $_ })
    files_checked = $results.Count
    files_changed = @($results | Where-Object changed).Count
    entries_removed = ($results | Measure-Object -Property removed -Sum).Sum
    backup_root = $(if ($Apply) { Get-FullPath $BackupRoot } else { '' })
    projects = @($results)
}

$summary | ConvertTo-Json -Depth 5
