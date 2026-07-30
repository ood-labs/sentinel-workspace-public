[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'validate-official-examples.ps1'
$promoter = Join-Path $PSScriptRoot 'promote-public.ps1'
$moduleUi = Join-Path $PSScriptRoot 'module-ui.ps1'
$powerShellExe = (Get-Process -Id $PID).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("sentinel-official-examples-{0}" -f [guid]::NewGuid().ToString('N'))
$sourceRoot = Join-Path $testRoot 'private'
$publicRoot = Join-Path $testRoot 'public'
$projectRoot = Join-Path $sourceRoot 'projects/industrial_lattice'
$config = Join-Path $testRoot 'fixture-config.psd1'

function Write-Utf8([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n").Replace("`r", "`n"), [Text.UTF8Encoding]::new($false))
}

function Invoke-JsonScript([string]$Script, [string[]]$Arguments, [int]$ExpectedExit) {
    if ((Split-Path -Leaf $Script) -eq 'validate-official-examples.ps1') {
        $rootIndex = [Array]::IndexOf($Arguments, '-Root')
        if ($rootIndex -ge 0 -and $rootIndex + 1 -lt $Arguments.Count) {
            $fixtureRoot = $Arguments[$rootIndex + 1]
            if (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot '.git'))) {
                git -C $fixtureRoot init -q
                if ($LASTEXITCODE -ne 0) { throw "git init failed for fixture root: $fixtureRoot" }
                git -C $fixtureRoot config core.autocrlf false
            }
            git -C $fixtureRoot add -A
            if ($LASTEXITCODE -ne 0) { throw "git add failed for fixture root: $fixtureRoot" }
        }
    }
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

try {
    New-Item -ItemType Directory -Path $sourceRoot, $publicRoot -Force | Out-Null
    git -C $sourceRoot init -q
    git -C $publicRoot init -q
    git -C $sourceRoot config core.autocrlf false
    git -C $publicRoot config core.autocrlf false
    Write-Utf8 $config @'
@{
    MinimumSentinelVersion = '0.5.35'
    Projects = @{
        industrial_lattice = @{
            ProjectFile = 'industrial_lattice.sentinel'
            SharedModules = @()
            ProofRecords = @('projects/industrial_lattice/proof/review.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
    }
    AllowedProjectDirectories = @('assets', 'cues', 'images', 'modules', 'proof')
    AllowedTopLevelFiles = @('README*', 'LICENSE*')
    GlobalSharedPaths = @()
    ForbiddenDirectoryNames = @('.cache', '.shadercache', 'captures', 'checkpoint', 'checkpoints', 'recovery', 'shader_cache', 'shadercache')
    ForbiddenFileNames = @('.env', '.env.*', 'DEBRIEF.md', 'provider*.json', 'vision.json', '*.cso', '*.log', '*.pdb', '*.tmp')
    TextExtensions = @('.fx', '.hlsl', '.hlsli', '.json', '.md', '.ps1', '.sentinel', '.txt', '.yaml', '.yml')
}
'@
    Write-Utf8 (Join-Path $projectRoot 'README.md') "# Industrial Lattice Fixture`n"
    Write-Utf8 (Join-Path $projectRoot 'proof/output.txt') "fixture proof`n"
    Write-Utf8 (Join-Path $projectRoot 'proof/review.json') "{`"approved`":true}`n"
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
    $escapedModule = Join-Path $testRoot 'modules/escaped_shared_fixture'
    Write-Utf8 (Join-Path $escapedModule 'manifest.yaml') "name: Escaped Shared Module`n"
    New-FixtureProject '../../../modules/escaped_shared_fixture'
    $escaped = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 1
    if (-not (@($escaped.projects[0].errors) -match 'escapes workspace root')) { throw 'Workspace-escaping module path was not rejected.' }
    New-FixtureProject 'modules/Active'

    Write-Utf8 (Join-Path $projectRoot 'duplicate.sentinel') "{}`n"
    $duplicate = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 1
    if (-not (@($duplicate.projects[0].errors) -match 'project root .sentinel files must exactly match config')) { throw 'Duplicate root project file was not rejected.' }
    Remove-Item -LiteralPath (Join-Path $projectRoot 'duplicate.sentinel') -Force

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

    # Dry-run must be non-mutating and list only the selected fixture project.
    $dryRun = Invoke-JsonScript $promoter @('-SourceRoot', $sourceRoot, '-DestinationRoot', $publicRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 0
    if ($dryRun.mode -ne 'dry-run') { throw 'Promotion did not default to dry-run.' }
    if (Test-Path -LiteralPath (Join-Path $publicRoot 'projects/industrial_lattice')) { throw 'Dry-run mutated the public fixture.' }
    if (@($dryRun.projects).Count -ne 1 -or $dryRun.projects[0].project -ne 'industrial_lattice') { throw 'Dry-run escaped the selected project allowlist.' }

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

    Write-Host 'PASS normalized manifest hashing is checkout-line-ending invariant'
    Write-Host 'PASS validator reports absolute path, orphan module, and shader cache independently'
    Write-Host 'PASS repaired fixture validates cleanly'
    Write-Host 'PASS validator rejects workspace escapes and duplicate root project files'
    Write-Host 'PASS validator rejects insufficient presets, missing Performance, and out-of-range group controls'
    Write-Host 'PASS promotion dry-run is allowlisted and non-mutating'
    Write-Host 'PASS disposable public promotion validates and matches normalized source content'
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
