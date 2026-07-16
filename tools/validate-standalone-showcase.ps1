param([string]$ProjectsRoot = 'projects')

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$root = [IO.Path]::GetFullPath((Join-Path $workspaceRoot $ProjectsRoot))

$projects = [ordered]@{
    living_room_sdf = 'living_room_sdf.sentinel'
    face_collage = 'face_collage.sentinel'
    fruit_atlas_scatter = 'fruit_atlas_scatter.sentinel'
    topographic_hud = 'topographic_hud.sentinel'
    strata = 'strata.sentinel'
    desert_totem = 'desert_totem.sentinel'
    industrial_lattice = 'industrial_lattice.sentinel'
}

function Get-EndpointOwner([string]$Path) {
    if ($Path -match '^/sentinel/pipelines/([^/]+)/') { return [pscustomobject]@{Kind='pipeline'; Id=$Matches[1]} }
    if ($Path -match '^/sentinel/groups/([^/]+)/') { return [pscustomobject]@{Kind='group'; Id=$Matches[1]} }
    return $null
}

$results = [Collections.Generic.List[object]]::new()
$failures = [Collections.Generic.List[string]]::new()

foreach ($entry in $projects.GetEnumerator()) {
    $slug = $entry.Key
    $projectDir = Join-Path $root $slug
    $projectFile = Join-Path $projectDir $entry.Value
    if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
        $failures.Add("${slug}: missing project file")
        continue
    }

    try { $project = Get-Content -LiteralPath $projectFile -Raw | ConvertFrom-Json }
    catch { $failures.Add("${slug}: invalid JSON: $($_.Exception.Message)"); continue }

    $pipelineIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($pipeline in @($project.pipelines)) { [void]$pipelineIds.Add($pipeline.id) }
    $groups = @($project.graph.nodes | Where-Object { $_.sceneGroup })
    $groupOutputs = @($project.pipelines | Where-Object { $_.type -eq 'groupoutput' })
    $muxes = @($project.pipelines | Where-Object { $_.type -eq 'mux' })
    $disabled = @($project.pipelines | Where-Object { -not $_.enabled })

    if ($groups.Count -ne 1) { $failures.Add("${slug}: expected one Scene Group, found $($groups.Count)") }
    if ($groupOutputs.Count -ne 1) { $failures.Add("${slug}: expected one Group Output, found $($groupOutputs.Count)") }
    if ($muxes.Count -ne 0) { $failures.Add("${slug}: contains a Mux/Scene Switcher") }
    if ($disabled.Count -ne 0) { $failures.Add("${slug}: disabled pipelines: $($disabled.id -join ', ')") }

    foreach ($pipeline in @($project.pipelines | Where-Object { $_.type -eq 'module' })) {
        $relative = [string]$pipeline.parameters.project_dir
        if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') {
            $failures.Add("$slug/$($pipeline.id): non-portable project_dir '$relative'")
            continue
        }
        $moduleDir = Join-Path $projectDir $relative
        if (-not (Test-Path -LiteralPath (Join-Path $moduleDir 'manifest.yaml') -PathType Leaf)) {
            $failures.Add("$slug/$($pipeline.id): missing bundled manifest at '$relative'")
        }
    }

    $groupId = if ($groups.Count -eq 1) { [string]$groups[0].entityId } else { '' }
    foreach ($bind in @($project.binds)) {
        if ($bind.Count -ne 2) { $failures.Add("${slug}: malformed bind network"); continue }
        foreach ($endpoint in $bind) {
            $owner = Get-EndpointOwner ([string]$endpoint)
            if ($null -eq $owner) { $failures.Add("${slug}: unsupported bind endpoint '$endpoint'") }
            elseif ($owner.Kind -eq 'pipeline' -and -not $pipelineIds.Contains($owner.Id)) { $failures.Add("${slug}: dangling bind pipeline '$($owner.Id)'") }
            elseif ($owner.Kind -eq 'group' -and $owner.Id -ne $groupId) { $failures.Add("${slug}: dangling bind group '$($owner.Id)'") }
        }
    }

    foreach ($pipeline in @($project.pipelines)) {
        if ($null -eq $pipeline.expressions) { continue }
        foreach ($expression in $pipeline.expressions.PSObject.Properties.Value) {
            foreach ($match in [regex]::Matches([string]$expression, 'ref\("([^/]+)/')) {
                $ownerId = $match.Groups[1].Value
                if (-not $pipelineIds.Contains($ownerId)) { $failures.Add("$slug/$($pipeline.id): dangling expression ref '$ownerId'") }
            }
        }
    }

    $pinIds = [Collections.Generic.HashSet[int]]::new()
    foreach ($pin in @($project.graph.pins)) { [void]$pinIds.Add([int]$pin.id) }
    foreach ($link in @($project.graph.links)) {
        if (-not $pinIds.Contains([int]$link.startPinId) -or -not $pinIds.Contains([int]$link.endPinId)) {
            $failures.Add("${slug}: graph link $($link.id) references a missing pin")
        }
    }

    foreach ($payload in $project.statePayloads.PSObject.Properties.Name) {
        if (-not $pipelineIds.Contains($payload)) { $failures.Add("${slug}: dangling state payload '$payload'") }
    }

    $results.Add([pscustomobject]@{
        project = $slug
        pipelines = @($project.pipelines).Count
        modules = @($project.pipelines | Where-Object type -eq 'module').Count
        links = @($project.graph.links).Count
        binds = @($project.binds).Count
        expressions = @($project.pipelines | ForEach-Object { if ($null -ne $_.expressions) { $_.expressions.PSObject.Properties } }).Count
        scene_group = $groupId
        group_output = if ($groupOutputs.Count -eq 1) { $groupOutputs[0].id } else { '' }
    })
}

[pscustomobject]@{
    ok = $failures.Count -eq 0
    projects = $results
    failures = $failures
} | ConvertTo-Json -Depth 6

if ($failures.Count -gt 0) { exit 1 }
