param(
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GalleryPath = "projects/showcase_gallery/showcase_gallery.sentinel"
)

$ErrorActionPreference = "Stop"
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)

function Read-Utf8Json([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, $utf8Strict) | ConvertFrom-Json
}

function Write-Utf8JsonAtomically([string]$Path, [object]$Value) {
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $json = $Value | ConvertTo-Json -Depth 100
        [System.IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Replace($temporary, $Path, $null)
    } finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

$galleryFile = Join-Path $WorkspaceRoot $GalleryPath
if (-not (Test-Path -LiteralPath $galleryFile)) {
    throw "Gallery project not found: $galleryFile"
}

$imports = @(
    @{ Slug = "living_room_sdf";      Project = "projects/living_room_sdf/living_room_sdf.sentinel";           IdMap = @{} },
    @{ Slug = "face_collage";         Project = "projects/face_collage/face_collage.sentinel";                 IdMap = @{} },
    @{ Slug = "fruit_atlas_scatter";  Project = "projects/fruit_atlas_scatter/fruit_atlas_scatter.sentinel"; IdMap = @{} },
    @{ Slug = "topographic_hud";      Project = "projects/topographic_hud/topographic_hud.sentinel";         IdMap = @{} },
    @{ Slug = "strata";               Project = "projects/strata/strata.sentinel";                           IdMap = @{ post = "post_1" } },
    @{ Slug = "desert_totem";         Project = "projects/desert_totem/desert_totem.sentinel";               IdMap = @{ post = "post_2"; signal = "signal_1" } },
    @{ Slug = "industrial_lattice";   Project = "projects/industrial_lattice/industrial_lattice.sentinel";   IdMap = @{ post = "post_3" } }
)

$gallery = Read-Utf8Json $galleryFile
$report = @()

foreach ($import in $imports) {
    $sourceFile = Join-Path $WorkspaceRoot $import.Project
    $source = Read-Utf8Json $sourceFile
    $groups = @($source.graph.nodes | Where-Object { $_.sceneGroup -eq $true })
    if ($groups.Count -ne 1) {
        throw "$($import.Slug) must have exactly one flat Scene Group; found $($groups.Count)"
    }

    $group = $groups[0]
    $activePreset = [string]$group.sceneGroupActivePreset
    $preset = @($group.sceneGroupPresets | Where-Object { $_.name -eq $activePreset })
    if ($preset.Count -ne 1) {
        throw "$($import.Slug) active preset '$activePreset' was not found exactly once"
    }

    $pipelineCount = 0
    $parameterCount = 0
    $expressionCount = 0
    $bypassCount = 0

    foreach ($sourcePipelineProperty in $preset[0].pipelineValues.PSObject.Properties) {
        $sourceId = $sourcePipelineProperty.Name
        $galleryId = if ($import.IdMap.ContainsKey($sourceId)) { $import.IdMap[$sourceId] } else { $sourceId }
        $target = @($gallery.pipelines | Where-Object { $_.id -eq $galleryId })
        if ($target.Count -ne 1) {
            throw "$($import.Slug) pipeline '$sourceId' maps to '$galleryId', found $($target.Count) gallery matches"
        }

        $pipelineCount++
        foreach ($parameter in $sourcePipelineProperty.Value.PSObject.Properties) {
            if ($parameter.Name -eq "project_dir") {
                continue
            }

            $existing = $target[0].parameters.PSObject.Properties[$parameter.Name]
            if ($null -eq $existing) {
                $target[0].parameters | Add-Member -NotePropertyName $parameter.Name -NotePropertyValue $parameter.Value
            } else {
                $existing.Value = $parameter.Value
            }
            $parameterCount++
        }

        if ($null -ne $target[0].expressions) {
            $staleNames = @(
                $target[0].expressions.PSObject.Properties |
                    Where-Object { [string]$_.Value -match '/sentinel/groups/' } |
                    ForEach-Object { $_.Name }
            )
            foreach ($name in $staleNames) {
                $target[0].expressions.PSObject.Properties.Remove($name)
                $expressionCount++
            }
            if ($target[0].expressions.PSObject.Properties.Count -eq 0) {
                $target[0].expressions = $null
            }
        }
    }

    foreach ($sourceBypassProperty in $preset[0].pipelineBypass.PSObject.Properties) {
        $sourceId = $sourceBypassProperty.Name
        $galleryId = if ($import.IdMap.ContainsKey($sourceId)) { $import.IdMap[$sourceId] } else { $sourceId }
        $target = @($gallery.pipelines | Where-Object { $_.id -eq $galleryId })
        if ($target.Count -ne 1) {
            throw "$($import.Slug) bypass pipeline '$sourceId' maps to '$galleryId', found $($target.Count) gallery matches"
        }
        $target[0].enabled = [bool]$sourceBypassProperty.Value
        $bypassCount++
    }

    $report += [pscustomobject]@{
        project = $import.Slug
        active_preset = $activePreset
        pipelines_baked = $pipelineCount
        parameters_baked = $parameterCount
        stale_group_expressions_removed = $expressionCount
        bypass_states_baked = $bypassCount
    }
}

Write-Utf8JsonAtomically $galleryFile $gallery

$report | ConvertTo-Json -Depth 4
