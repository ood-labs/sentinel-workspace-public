param(
    [string]$GalleryProject = "projects/showcase_gallery/showcase_gallery.sentinel",
    [string]$ProjectsRoot = "projects"
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$galleryPath = [IO.Path]::GetFullPath((Join-Path $workspaceRoot $GalleryProject))
$projectsPath = [IO.Path]::GetFullPath((Join-Path $workspaceRoot $ProjectsRoot))
$galleryDir = Split-Path -Parent $galleryPath

if (-not (Test-Path -LiteralPath $galleryPath -PathType Leaf)) {
    throw "Gallery project not found: $galleryPath"
}
if (-not (Test-Path -LiteralPath $projectsPath -PathType Container)) {
    throw "Projects root not found: $projectsPath"
}

$groups = @(
    [pscustomobject]@{
        EntityId = 'annotation_87'; Slug = 'living_room_sdf'; File = 'living_room_sdf.sentinel'
        Pipelines = @('LR_Architecture','LR_Cinematic_Grade','LR_Furnishings','LR_Group_Output','LR_Lighting','LR_Materials','LR_SDF_Renderer')
        PresetTypes = @('module:LR_Furnishings_2')
    },
    [pscustomobject]@{
        EntityId = 'annotation_88'; Slug = 'face_collage'; File = 'face_collage.sentinel'
        Pipelines = @('Accum','Clone_Overlay','Editorial_Post','Face_Collage_Group_Output','Face_Cutout','Face_DS','Face_Guide','Face_Stitch','Face_Track','Overlay_Comp','Prompt_LFO','SD_Face')
        PresetTypes = @('module:face_cutout','module:collage_post')
    },
    [pscustomobject]@{
        EntityId = 'annotation_89'; Slug = 'fruit_atlas_scatter'; File = 'fruit_atlas_scatter.sentinel'
        Pipelines = @('Fruit_Atlas','Fruit_Depth','Fruit_Group_Output','Fruit_Guide','Fruit_LFO','Fruit_Matte','Fruit_SD','Fruit_Scene')
        PresetTypes = @('module:Fruit_LFO','module:Fruit_Scene')
    },
    [pscustomobject]@{
        EntityId = 'annotation_90'; Slug = 'topographic_hud'; File = 'topographic_hud.sentinel'
        Pipelines = @('Topo_Conductor','Topo_Group_Output','atmosphere','compositor','contour_accent','contour_blue','field_gen','frame_hud','grid_warp','label_gen','label_render','link_gen','link_render','node_gen','node_render','post','signal')
        PresetTypes = @('module:node_gen','module:signal')
    },
    [pscustomobject]@{
        EntityId = 'annotation_91'; Slug = 'strata'; File = 'strata.sentinel'
        Pipelines = @('Strata_Group_Output','blob_layout','blob_render','corner_thread','features_0','marble_panel','marks','plate_comp','post_1','strata_bg','strata_control','wire_render')
        PresetTypes = @('module:strata_control','module:blob_render')
    },
    [pscustomobject]@{
        EntityId = 'annotation_92'; Slug = 'desert_totem'; File = 'desert_totem.sentinel'
        Pipelines = @('Desert_Group_Output','dada_control','dada_layout','dada_render','dada_scatter','post_2','signal_1')
        PresetTypes = @('module:dada_layout','module:dada_control','module:dada_render','module:post')
    },
    [pscustomobject]@{
        EntityId = 'annotation_93'; Slug = 'industrial_lattice'; File = 'industrial_lattice.sentinel'
        Pipelines = @('Industrial_Group_Output','lattice','post_3')
        PresetTypes = @('module:steel_lattice','module:industrial_mono_post')
    }
)

function Test-BindEndpoint {
    param(
        [string]$Path,
        [Collections.Generic.HashSet[string]]$PipelineIds,
        [string]$GroupId
    )
    if ($Path -match '^/sentinel/pipelines/([^/]+)/') {
        return $PipelineIds.Contains($Matches[1])
    }
    if ($Path -match '^/sentinel/groups/([^/]+)/') {
        return $Matches[1] -eq $GroupId
    }
    return $false
}

function Copy-BundledDirectory {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $Destination -Force)
    }
    Get-ChildItem -LiteralPath $Source -Force |
        Where-Object { $_.Name -ne '.sentinel' } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force }
}

function Get-BaselineProject {
    param([string]$TargetFile)
    $baseUri = [Uri]($workspaceRoot.TrimEnd('\') + '\')
    $targetUri = [Uri]$TargetFile
    $relative = [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString())
    $gitText = & git show "HEAD:$relative" 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitText) {
        return (($gitText -join [Environment]::NewLine) | ConvertFrom-Json)
    }
    if (Test-Path -LiteralPath $TargetFile -PathType Leaf) {
        return (Get-Content -LiteralPath $TargetFile -Raw | ConvertFrom-Json)
    }
    return $null
}

function Get-CompatibleSceneGroupPresets {
    param(
        $BaselineProject,
        [Collections.Generic.HashSet[string]]$PipelineIds,
        [object[]]$CurrentPipelines
    )
    if ($null -eq $BaselineProject) { return @() }
    $baselineGroup = $BaselineProject.graph.nodes | Where-Object { $_.sceneGroup } | Select-Object -First 1
    if ($null -eq $baselineGroup -or @($baselineGroup.sceneGroupPresets).Count -eq 0) { return @() }

    $currentDirs = @{}
    foreach ($pipeline in $CurrentPipelines) {
        if ($pipeline.type -eq 'module') { $currentDirs[$pipeline.id] = [string]$pipeline.parameters.project_dir }
    }

    $result = [Collections.Generic.List[object]]::new()
    foreach ($sourcePreset in @($baselineGroup.sceneGroupPresets)) {
        $preset = $sourcePreset | ConvertTo-Json -Depth 100 | ConvertFrom-Json

        $values = [ordered]@{}
        foreach ($property in $preset.pipelineValues.PSObject.Properties) {
            if (-not $PipelineIds.Contains($property.Name)) { continue }
            $pipelineValues = $property.Value
            if ($currentDirs.ContainsKey($property.Name) -and
                $pipelineValues.PSObject.Properties.Name -contains 'project_dir') {
                $pipelineValues.project_dir = $currentDirs[$property.Name]
            }
            $values[$property.Name] = $pipelineValues
        }
        $preset.pipelineValues = [pscustomobject]$values

        $bypass = [ordered]@{}
        foreach ($property in $preset.pipelineBypass.PSObject.Properties) {
            if ($PipelineIds.Contains($property.Name)) { $bypass[$property.Name] = $property.Value }
        }
        $preset.pipelineBypass = [pscustomobject]$bypass
        $result.Add($preset)
    }
    return @($result.ToArray())
}

$gallery = Get-Content -LiteralPath $galleryPath -Raw | ConvertFrom-Json
$results = [Collections.Generic.List[object]]::new()

foreach ($group in $groups) {
    $targetDir = Join-Path $projectsPath $group.Slug
    $targetFile = Join-Path $targetDir $group.File
    $baselineProject = Get-BaselineProject -TargetFile $targetFile

    $pipelineIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($pipelineId in $group.Pipelines) { [void]$pipelineIds.Add($pipelineId) }

    $annotation = $gallery.graph.nodes | Where-Object { $_.entityId -eq $group.EntityId } | Select-Object -First 1
    if ($null -eq $annotation) { throw "Missing Scene Group $($group.EntityId)" }

    $project = $gallery | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $project.name = $group.Slug
    $project.saved_at_ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $project.layout = ''

    $keptPipelines = @($project.pipelines | Where-Object { $pipelineIds.Contains($_.id) })
    if ($keptPipelines.Count -ne $group.Pipelines.Count) {
        $found = @($keptPipelines | ForEach-Object id)
        $missing = @($group.Pipelines | Where-Object { $found -notcontains $_ })
        throw "$($group.Slug): missing pipelines: $($missing -join ', ')"
    }
    foreach ($pipeline in $keptPipelines) {
        $pipeline.enabled = $true
        $pipeline.running = $true
        $pipeline.panelOpen = ($pipeline.type -eq 'groupoutput')
    }
    $project.pipelines = $keptPipelines

    $keptNodes = @($project.graph.nodes | Where-Object {
        $_.entityId -eq $group.EntityId -or $pipelineIds.Contains($_.entityId)
    })
    $nodeIds = [Collections.Generic.HashSet[int]]::new()
    foreach ($node in $keptNodes) { [void]$nodeIds.Add([int]$node.id) }

    $dx = 80.0 - [double]$annotation.posX
    $dy = 80.0 - [double]$annotation.posY
    foreach ($node in $keptNodes) {
        $node.posX = [double]$node.posX + $dx
        $node.posY = [double]$node.posY + $dy
        if ($pipelineIds.Contains($node.entityId)) {
            $node.previewVisible = ($keptPipelines | Where-Object { $_.id -eq $node.entityId } | Select-Object -First 1).type -eq 'groupoutput'
        }
    }
    $portablePresets = Get-CompatibleSceneGroupPresets -BaselineProject $baselineProject -PipelineIds $pipelineIds -CurrentPipelines $keptPipelines
    $keptAnnotation = $keptNodes | Where-Object { $_.entityId -eq $group.EntityId } | Select-Object -First 1
    $keptAnnotation.sceneGroupPresets = @($portablePresets)
    $project.graph.nodes = $keptNodes

    $keptPins = @($project.graph.pins | Where-Object { $nodeIds.Contains([int]$_.nodeId) })
    $pinIds = [Collections.Generic.HashSet[int]]::new()
    foreach ($pin in $keptPins) { [void]$pinIds.Add([int]$pin.id) }
    $project.graph.pins = $keptPins
    $project.graph.links = @($project.graph.links | Where-Object {
        $pinIds.Contains([int]$_.startPinId) -and $pinIds.Contains([int]$_.endPinId)
    })
    $project.graph.canvasZoom = 0.72

    $keptBinds = [Collections.Generic.List[object]]::new()
    foreach ($bind in $project.binds) {
        if ($bind.Count -eq 2 -and
            (Test-BindEndpoint -Path ([string]$bind[0]) -PipelineIds $pipelineIds -GroupId $group.EntityId) -and
            (Test-BindEndpoint -Path ([string]$bind[1]) -PipelineIds $pipelineIds -GroupId $group.EntityId)) {
            $keptBinds.Add([object]$bind)
        }
    }
    $project.binds = @($keptBinds.ToArray())
    $project.nodePresets = @($project.nodePresets | Where-Object { $group.PresetTypes -contains $_.pipelineType })

    $payloads = [ordered]@{}
    foreach ($property in $project.statePayloads.PSObject.Properties) {
        if ($pipelineIds.Contains($property.Name)) { $payloads[$property.Name] = $property.Value }
    }
    $project.statePayloads = [pscustomobject]$payloads

    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $targetDir)
    }

    foreach ($pipeline in $keptPipelines) {
        if ($pipeline.type -ne 'module') { continue }
        $relativeDir = [string]$pipeline.parameters.project_dir
        if ([string]::IsNullOrWhiteSpace($relativeDir)) { throw "$($pipeline.id): missing project_dir" }
        $sourceDir = Join-Path $galleryDir $relativeDir
        $destDir = Join-Path $targetDir $relativeDir
        if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
            throw "$($pipeline.id): bundled module not found: $sourceDir"
        }
        Copy-BundledDirectory -Source $sourceDir -Destination $destDir
    }

    $sharedSource = Join-Path $galleryDir 'modules/_shared'
    $sharedDest = Join-Path $targetDir 'modules/_shared'
    if (Test-Path -LiteralPath $sharedSource -PathType Container) {
        Copy-BundledDirectory -Source $sharedSource -Destination $sharedDest
    }

    $json = $project | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($targetFile, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

    $results.Add([pscustomobject]@{
        project = $group.Slug
        file = $targetFile
        pipelines = $keptPipelines.Count
        modules = @($keptPipelines | Where-Object type -eq 'module').Count
        nodes = $keptNodes.Count
        links = @($project.graph.links).Count
        binds = @($project.binds).Count
        presets = @($project.nodePresets).Count
        state_payloads = @($project.statePayloads.PSObject.Properties).Count
    })
}

$results | ConvertTo-Json -Depth 5
