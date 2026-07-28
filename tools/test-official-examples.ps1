[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'validate-official-examples.ps1'
$promoter = Join-Path $PSScriptRoot 'promote-public.ps1'
$config = Join-Path $PSScriptRoot 'official-examples.config.psd1'
$moduleUi = Join-Path $PSScriptRoot 'module-ui.ps1'
$powerShellExe = (Get-Process -Id $PID).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("sentinel-official-examples-{0}" -f [guid]::NewGuid().ToString('N'))
$sourceRoot = Join-Path $testRoot 'private'
$publicRoot = Join-Path $testRoot 'public'
$projectRoot = Join-Path $sourceRoot 'projects/industrial_lattice'

function Write-Utf8([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n").Replace("`r", "`n"), [Text.UTF8Encoding]::new($false))
}

function Invoke-JsonScript([string]$Script, [string[]]$Arguments, [int]$ExpectedExit) {
    $output = & $powerShellExe -NoProfile -File $Script @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne $ExpectedExit) {
        throw "$(Split-Path -Leaf $Script) exited $exitCode; expected $ExpectedExit.`n$($output -join "`n")"
    }
    return (($output -join "`n") | ConvertFrom-Json)
}

function New-FixtureProject([string]$ProjectDir) {
    $sceneParameters = 1..6 | ForEach-Object { [ordered]@{ name = "Control_$_"; pipelineId = 'Active'; paramName = "control_$_" } }
    $project = [ordered]@{
        version = '0.5.33'
        name = 'Official Example Fixture'
        pipelines = @(
            [ordered]@{
                id = 'Active'
                displayName = 'Active'
                type = 'module'
                parameters = [ordered]@{ project_dir = $ProjectDir }
            },
            [ordered]@{
                id = 'Final_Output'
                displayName = 'Final Output'
                type = 'groupoutput'
                parameters = [ordered]@{}
            }
        )
        nodePresets = @(
            [ordered]@{ name = 'Structure A'; identity = 'module:fixture' },
            [ordered]@{ name = 'Structure B'; identity = 'module:fixture' }
        )
        graph = [ordered]@{
            nodes = @(
                [ordered]@{
                    entityId = 'annotation_1'
                    sceneGroup = $true
                    sceneGroupParameters = @($sceneParameters)
                    sceneGroupPresets = @(
                        [ordered]@{ name = 'Performance' },
                        [ordered]@{ name = 'Fidelity' },
                        [ordered]@{ name = 'Hero' }
                    )
                },
                [ordered]@{
                    entityId = 'Active'
                    type = 1
                    previewVisible = $true
                }
            )
        }
    }
    Write-Utf8 (Join-Path $projectRoot 'industrial_lattice.sentinel') (($project | ConvertTo-Json -Depth 12) + "`n")
}

function New-GalleryFixture {
    $galleryRoot = Join-Path $sourceRoot 'projects/showcase_gallery'
    $groups = @()
    $outputs = @()
    $nodes = @()
    $pins = @()
    $links = @()
    $allowed = @()
    for ($index = 1; $index -le 7; $index++) {
        $groupId = "annotation_$index"
        $outputId = "Output_$index"
        $groupX = ($index - 1) * 1000
        $nodeId = 100 + $index
        $pinId = 200 + $index
        $groups += [ordered]@{
            entityId = $groupId; sceneGroup = $true; posX = $groupX; posY = 0
            width = 900; height = 900; sceneGroupParameters = @(); sceneGroupPresets = @()
        }
        $outputs += [ordered]@{ id = $outputId; displayName = $outputId; type = 'groupoutput'; parameters = [ordered]@{} }
        $nodes += [ordered]@{ entityId = $outputId; id = $nodeId; posX = $groupX + 700; posY = 700 }
        $pins += [ordered]@{ id = $pinId; nodeId = $nodeId; kind = 0; name = 'Video'; slotIndex = 0; type = 0 }
        $links += [ordered]@{ id = $index; startPinId = 300 + $index; endPinId = $pinId }
        $allowed += $groupId
    }
    $mux = [ordered]@{
        id = 'Gallery_Mux'; displayName = 'Gallery Mux'; type = 'mux'; enabled = $true
        parameters = [ordered]@{
            source_mode = '1'; solo_upstream = 'true'; allowed_groups = ($allowed -join ',')
            selected_group = $allowed[0]; fade_time = '0.75'
        }
    }
    $passiveBuses = @(
        [ordered]@{ id = 'signal'; project_dir = 'modules/signal' },
        [ordered]@{ id = 'strata_control'; project_dir = 'modules/strata_control' },
        [ordered]@{ id = 'dada_control'; project_dir = 'modules/dada_control' }
    )
    $busPipelines = foreach ($bus in $passiveBuses) {
        $moduleRoot = Join-Path $galleryRoot $bus.project_dir
        Write-Utf8 (Join-Path $moduleRoot 'manifest.yaml') @"
name: Passive Bus Fixture
resolution: [480, 270]
viewport:
  hint: "Passive preview. Edit in Properties."
passes:
  - name: Bus
    type: pixel
    shader: display.hlsl
outputs:
  - { name: "Bus", pass: Bus }
"@
        Write-Utf8 (Join-Path $moduleRoot 'display.hlsl') "float4 mainImage(float2 uv) { return float4(uv, 0.0, 1.0); }`n"
        [ordered]@{
            id = $bus.id
            displayName = $bus.id
            type = 'module'
            parameters = [ordered]@{
                project_dir = $bus.project_dir
                resolution_width = '480'
                resolution_height = '270'
            }
        }
    }
    $project = [ordered]@{
        version = '0.5.33'; name = 'Gallery Fixture'; pipelines = @($busPipelines) + @($outputs) + @($mux); nodePresets = @()
        graph = [ordered]@{ nodes = @($nodes) + @($groups); pins = $pins; links = $links }
    }
    Write-Utf8 (Join-Path $galleryRoot 'showcase_gallery.sentinel') (($project | ConvertTo-Json -Depth 12) + "`n")
    Write-Utf8 (Join-Path $galleryRoot 'README.md') "# Gallery Fixture`n"
    Write-Utf8 (Join-Path $galleryRoot 'proof/output.txt') "gallery fixture proof`n"
}

try {
    New-Item -ItemType Directory -Path $sourceRoot, $publicRoot -Force | Out-Null
    Write-Utf8 (Join-Path $projectRoot 'README.md') "# Industrial Lattice Fixture`n"
    Write-Utf8 (Join-Path $projectRoot 'proof/output.txt') "fixture proof`n"
    Write-Utf8 (Join-Path $projectRoot 'modules/Active/manifest.yaml') @'
name: Official Fixture Module
resolution: [640, 360]
passes:
  - name: Main
    type: pixel
    shader: render.hlsl
'@
    Write-Utf8 (Join-Path $projectRoot 'modules/Active/render.hlsl') "float4 mainImage(float2 uv) { return float4(uv, 0.0, 1.0); }`n"

    # Generate a UI header from LF input, materialize the manifest as CRLF,
    # and require the real validator to accept the same logical text.
    $hashModule = Join-Path $testRoot 'hash-module'
    Write-Utf8 (Join-Path $hashModule 'manifest.yaml') @'
name: Hash Fixture
resolution: [640, 360]
parameters:
  - { name: amount, type: float, min: 0.0, max: 1.0, default: 0.5 }
viewport:
  controls:
    - { id: amount, kind: slider, param: amount, rect: [0.1, 0.1, 0.8, 0.2], label: "Amount" }
'@
    & $moduleUi generate $hashModule | Out-Null
    $manifestPath = Join-Path $hashModule 'manifest.yaml'
    $lfText = [IO.File]::ReadAllText($manifestPath).Replace("`r`n", "`n")
    [IO.File]::WriteAllText($manifestPath, $lfText.Replace("`n", "`r`n"), [Text.UTF8Encoding]::new($false))
    & $moduleUi validate $hashModule | Out-Null

    # Seed all three defects required by the phase acceptance contract.
    New-FixtureProject 'C:/Users/example/private/Active'
    Write-Utf8 (Join-Path $projectRoot 'modules/Orphan/manifest.yaml') "name: Orphan`n"
    Write-Utf8 (Join-Path $projectRoot 'shader_cache/fixture.cso') "not-a-real-cache`n"

    $bad = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 1
    $badProject = $bad.projects[0]
    if ($badProject.absolute_paths.Count -eq 0) { throw 'Seeded absolute path was not reported.' }
    if ($badProject.orphan_modules.Count -eq 0) { throw 'Seeded orphan module was not reported.' }
    if ($badProject.forbidden_artifacts.Count -eq 0) { throw 'Seeded shader cache was not reported.' }

    # Repair the same fixture and require a clean result.
    New-FixtureProject 'modules/Active'
    Remove-Item -LiteralPath (Join-Path $projectRoot 'modules/Orphan') -Force -Recurse
    Remove-Item -LiteralPath (Join-Path $projectRoot 'shader_cache') -Force -Recurse
    $clean = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 0
    if (-not $clean.portable) { throw 'Repaired fixture did not validate as portable.' }

    $previewConfig = Join-Path $testRoot 'preview-config.psd1'
    $previewConfigText = [IO.File]::ReadAllText($config).Replace(
        'industrial_lattice = @{',
        "industrial_lattice = @{`n            RequireNodePreviews = `$true"
    )
    Write-Utf8 $previewConfig $previewConfigText
    $fixtureFile = Join-Path $projectRoot 'industrial_lattice.sentinel'
    $fixtureJson = [IO.File]::ReadAllText($fixtureFile) | ConvertFrom-Json
    ($fixtureJson.graph.nodes | Where-Object { $_.entityId -eq 'Active' }).previewVisible = $false
    Write-Utf8 $fixtureFile (($fixtureJson | ConvertTo-Json -Depth 12) + "`n")
    $closedPreview = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $previewConfig, '-Json') 1
    if (-not (@($closedPreview.projects[0].errors) -match 'preview visible by default')) {
        throw 'Closed default node preview was not rejected.'
    }

    New-FixtureProject 'modules/Active'
    $zeroOutputConfig = Join-Path $testRoot 'zero-output-config.psd1'
    $zeroOutputConfigText = [IO.File]::ReadAllText($config).Replace(
        'industrial_lattice = @{',
        "industrial_lattice = @{`n            ExpectedGroupOutputs = 0"
    )
    Write-Utf8 $zeroOutputConfig $zeroOutputConfigText
    $forbiddenOutput = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $zeroOutputConfig, '-Json') 1
    if (-not (@($forbiddenOutput.projects[0].errors) -match 'exactly 0 Group Outputs')) {
        throw 'Forbidden standalone Group Output was not rejected.'
    }
    New-FixtureProject 'modules/Active'

    # A path that normalizes to an approved shared module must still fail if
    # its resolved location escapes the workspace root.
    $escapedModule = Join-Path $testRoot 'modules/industrial_mono_post'
    Write-Utf8 (Join-Path $escapedModule 'manifest.yaml') "name: Escaped Shared Module`n"
    New-FixtureProject '../../../modules/industrial_mono_post'
    $escaped = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 1
    if (-not (@($escaped.projects[0].errors) -match 'escapes workspace root')) { throw 'Workspace-escaping module path was not rejected.' }
    New-FixtureProject 'modules/Active'

    Write-Utf8 (Join-Path $projectRoot 'duplicate.sentinel') "{}`n"
    $duplicate = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 1
    if (-not (@($duplicate.projects[0].errors) -match 'exactly one .sentinel')) { throw 'Duplicate root project file was not rejected.' }
    Remove-Item -LiteralPath (Join-Path $projectRoot 'duplicate.sentinel') -Force

    # The gallery needs seven owned, connected Group Outputs and one exact
    # groups-mode Mux; exercise each central structural failure independently.
    New-GalleryFixture
    $galleryClean = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'showcase_gallery', '-ConfigPath', $config, '-Json') 0
    if (-not $galleryClean.portable) { throw 'Valid gallery fixture did not pass.' }
    $galleryFile = Join-Path $sourceRoot 'projects/showcase_gallery/showcase_gallery.sentinel'

    $galleryJson = [IO.File]::ReadAllText($galleryFile) | ConvertFrom-Json
    $galleryJson.pipelines = @($galleryJson.pipelines | Where-Object { $_.id -ne 'Output_1' })
    Write-Utf8 $galleryFile (($galleryJson | ConvertTo-Json -Depth 12) + "`n")
    $missingOutput = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'showcase_gallery', '-ConfigPath', $config, '-Json') 1
    if (-not (@($missingOutput.projects[0].errors) -match 'Group Output')) { throw 'Missing gallery Group Output was not rejected.' }

    New-GalleryFixture
    $galleryJson = [IO.File]::ReadAllText($galleryFile) | ConvertFrom-Json
    $galleryJson.pipelines = @($galleryJson.pipelines | Where-Object { $_.type -ne 'mux' })
    Write-Utf8 $galleryFile (($galleryJson | ConvertTo-Json -Depth 12) + "`n")
    $missingMux = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'showcase_gallery', '-ConfigPath', $config, '-Json') 1
    if (-not (@($missingMux.projects[0].errors) -match 'final Mux')) { throw 'Missing gallery Mux was not rejected.' }

    New-GalleryFixture
    $galleryJson = [IO.File]::ReadAllText($galleryFile) | ConvertFrom-Json
    ($galleryJson.pipelines | Where-Object { $_.type -eq 'mux' }).parameters.allowed_groups = 'annotation_1'
    Write-Utf8 $galleryFile (($galleryJson | ConvertTo-Json -Depth 12) + "`n")
    $badAllowList = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'showcase_gallery', '-ConfigPath', $config, '-Json') 1
    if (-not (@($badAllowList.projects[0].errors) -match 'allowed_groups')) { throw 'Incomplete gallery allow-list was not rejected.' }

    New-GalleryFixture
    $galleryJson = [IO.File]::ReadAllText($galleryFile) | ConvertFrom-Json
    ($galleryJson.graph.nodes | Where-Object { $_.entityId -eq 'Output_1' }).posX = 950
    Write-Utf8 $galleryFile (($galleryJson | ConvertTo-Json -Depth 12) + "`n")
    $badOwnership = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'showcase_gallery', '-ConfigPath', $config, '-Json') 1
    if (-not (@($badOwnership.projects[0].errors) -match 'must contain exactly one Group Output')) { throw 'Out-of-group gallery output was not rejected.' }
    New-GalleryFixture

    $galleryJson = [IO.File]::ReadAllText($galleryFile) | ConvertFrom-Json
    ($galleryJson.pipelines | Where-Object { $_.type -eq 'mux' }).parameters.source_mode = '0'
    Write-Utf8 $galleryFile (($galleryJson | ConvertTo-Json -Depth 12) + "`n")
    $badMuxMode = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'showcase_gallery', '-ConfigPath', $config, '-Json') 1
    if (-not (@($badMuxMode.projects[0].errors) -match 'Groups source mode')) { throw 'Non-Groups gallery Mux was not rejected.' }
    New-GalleryFixture

    $galleryJson = [IO.File]::ReadAllText($galleryFile) | ConvertFrom-Json
    ($galleryJson.pipelines | Where-Object { $_.type -eq 'mux' }).parameters.solo_upstream = 'false'
    Write-Utf8 $galleryFile (($galleryJson | ConvertTo-Json -Depth 12) + "`n")
    $badSolo = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'showcase_gallery', '-ConfigPath', $config, '-Json') 1
    if (-not (@($badSolo.projects[0].errors) -match 'enable solo_upstream')) { throw 'Disabled gallery solo_upstream was not rejected.' }
    New-GalleryFixture

    New-FixtureProject 'modules/Active'
    $fixtureFile = Join-Path $projectRoot 'industrial_lattice.sentinel'
    $fixtureJson = [IO.File]::ReadAllText($fixtureFile) | ConvertFrom-Json
    $fixtureJson.graph.nodes[0].sceneGroupPresets = @($fixtureJson.graph.nodes[0].sceneGroupPresets | Select-Object -First 2)
    Write-Utf8 $fixtureFile (($fixtureJson | ConvertTo-Json -Depth 12) + "`n")
    $tooFewPresets = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 1
    if (-not (@($tooFewPresets.projects[0].errors) -match 'at least 3 presets')) { throw 'Too few Scene Group presets were not rejected.' }

    New-FixtureProject 'modules/Active'
    $fixtureJson = [IO.File]::ReadAllText($fixtureFile) | ConvertFrom-Json
    ($fixtureJson.graph.nodes[0].sceneGroupPresets | Where-Object { $_.name -eq 'Performance' }).name = 'Alternate'
    Write-Utf8 $fixtureFile (($fixtureJson | ConvertTo-Json -Depth 12) + "`n")
    $missingPerformance = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 1
    if (-not (@($missingPerformance.projects[0].errors) -match "named 'Performance'")) { throw 'Missing Performance preset was not rejected.' }

    New-FixtureProject 'modules/Active'
    $fixtureJson = [IO.File]::ReadAllText($fixtureFile) | ConvertFrom-Json
    $fixtureJson.graph.nodes[0].sceneGroupParameters = @($fixtureJson.graph.nodes[0].sceneGroupParameters | Select-Object -First 5)
    Write-Utf8 $fixtureFile (($fixtureJson | ConvertTo-Json -Depth 12) + "`n")
    $tooFewControls = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 1
    if (-not (@($tooFewControls.projects[0].errors) -match 'expose 6-10 controls')) { throw 'Out-of-range Scene Group control count was not rejected.' }
    New-FixtureProject 'modules/Active'

    $galleryJson = [IO.File]::ReadAllText($galleryFile) | ConvertFrom-Json
    ($galleryJson.pipelines | Where-Object { $_.id -eq 'signal' }).parameters.resolution_width = '481'
    Write-Utf8 $galleryFile (($galleryJson | ConvertTo-Json -Depth 12) + "`n")
    $badPassiveBus = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'showcase_gallery', '-ConfigPath', $config, '-Json') 1
    if (-not (@($badPassiveBus.projects[0].errors) -match "passive bus 'signal' project resolution")) {
        throw 'Passive-bus project resolution drift was not rejected.'
    }
    New-GalleryFixture

    # Dry-run must be non-mutating and list only the selected fixture project.
    $dryRun = Invoke-JsonScript $promoter @('-SourceRoot', $sourceRoot, '-DestinationRoot', $publicRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 0
    if ($dryRun.mode -ne 'dry-run') { throw 'Promotion did not default to dry-run.' }
    if (Test-Path -LiteralPath (Join-Path $publicRoot 'projects/industrial_lattice')) { throw 'Dry-run mutated the public fixture.' }
    if (@($dryRun.projects).Count -ne 1 -or $dryRun.projects[0].project -ne 'industrial_lattice') { throw 'Dry-run escaped the selected project allowlist.' }

    $promotionConfig = Join-Path $testRoot 'promotion-config.psd1'
    Write-Utf8 $promotionConfig @'
@{
    MinimumSentinelVersion = '0.5.35'
    Projects = @{
        industrial_lattice = @{
            ProjectFile = 'industrial_lattice.sentinel'
            SharedModules = @()
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
        showcase_gallery = @{
            ProjectFile = 'showcase_gallery.sentinel'
            Promote = $false
            SharedModules = @()
            MinimumSceneGroups = 7
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 7
            RequiresGroupsMux = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 0
            Exemptions = @('scene-group-controls', 'scene-group-presets', 'node-presets')
        }
    }
    AllowedProjectDirectories = @('assets', 'cues', 'modules', 'proof')
    AllowedTopLevelFiles = @('README*', 'LICENSE*')
    GlobalSharedPaths = @('modules/_shared')
    ForbiddenDirectoryNames = @('.cache', '.shadercache', 'captures', 'checkpoint', 'checkpoints', 'recovery', 'shader_cache', 'shadercache')
    ForbiddenFileNames = @('.env', '.env.*', 'DEBRIEF.md', 'provider*.json', 'vision.json', '*.cso', '*.log', '*.pdb', '*.tmp')
    TextExtensions = @('.fx', '.hlsl', '.hlsli', '.json', '.md', '.ps1', '.sentinel', '.txt', '.yaml', '.yml')
}
'@
    $defaultDryRun = Invoke-JsonScript $promoter @('-SourceRoot', $sourceRoot, '-DestinationRoot', $publicRoot, '-ConfigPath', $promotionConfig, '-Json') 0
    if (@($defaultDryRun.projects).Count -ne 1 -or $defaultDryRun.projects[0].project -ne 'industrial_lattice') {
        throw 'Default promotion did not omit the review-only Gallery.'
    }

    # Apply into the disposable public root, validate there, and prove normalized parity.
    $applied = Invoke-JsonScript $promoter @('-SourceRoot', $sourceRoot, '-DestinationRoot', $publicRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Apply', '-Json') 0
    if ($applied.mode -ne 'apply' -or @($applied.validation).Count -ne 1 -or -not $applied.validation[0].portable) {
        throw 'Applied promotion was not validator-clean.'
    }
    foreach ($operation in @($applied.operations | Where-Object { $_.action -ne 'delete' })) {
        if ($operation.source_sha256 -ne $operation.destination_sha256) {
            throw "Normalized promotion mismatch: $($operation.path)"
        }
    }

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $reviewOnlyOutput = & $powerShellExe -NoProfile -File $promoter `
            -SourceRoot $sourceRoot -DestinationRoot $publicRoot `
            -Projects showcase_gallery -ConfigPath $config -Json 2>&1
        $reviewOnlyExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($reviewOnlyExit -eq 0 -or ($reviewOnlyOutput -join "`n") -notmatch 'review-only') {
        throw 'Review-only Gallery promotion was not refused.'
    }

    Write-Host 'PASS normalized manifest hashing is checkout-line-ending invariant'
    Write-Host 'PASS validator reports absolute path, orphan module, and shader cache independently'
    Write-Host 'PASS repaired fixture validates cleanly'
    Write-Host 'PASS validator rejects workspace escapes and duplicate root project files'
    Write-Host 'PASS gallery validator enforces outputs, ownership, links, Mux mode, soloing, and exact allow-list'
    Write-Host 'PASS validator rejects insufficient presets, missing Performance, and out-of-range group controls'
    Write-Host 'PASS validator rejects passive-bus resolution drift'
    Write-Host 'PASS promotion dry-run is allowlisted and non-mutating'
    Write-Host 'PASS default promotion omits the review-only Showcase Gallery'
    Write-Host 'PASS disposable public promotion validates and matches normalized source content'
    Write-Host 'PASS promotion refuses the review-only Showcase Gallery'
} finally {
    $tempFull = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $testFull = [IO.Path]::GetFullPath($testRoot)
    if (Test-Path -LiteralPath $testFull) {
        if (-not $testFull.StartsWith($tempFull, [StringComparison]::OrdinalIgnoreCase) -or $testFull -eq $tempFull) {
            throw "Refusing unsafe fixture cleanup: $testFull"
        }
        Remove-Item -LiteralPath $testFull -Force -Recurse
    }
}
