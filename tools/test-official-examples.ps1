[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'validate-official-examples.ps1'
$promoter = Join-Path $PSScriptRoot 'promote-public.ps1'
$moduleUi = Join-Path $PSScriptRoot 'module-ui.ps1'
$manifestUpdater = Join-Path $PSScriptRoot 'update-workspace-manifest.ps1'
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
        sources = @()
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
        outputObjects = @()
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
            ProofRecords = @('.release/reviews/fixture.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
    }
    AllowedProjectDirectories = @('assets', 'cues', 'images', 'modules', 'tools')
    AllowedTopLevelFiles = @('README*', 'LICENSE*')
    GlobalSharedPaths = @()
    RequiredProjectReadmeHeading = '## Component map'
    Scientifica = @{
        FileName = 'scientifica_ascii.hlsli'
        Sha256 = 'fda36f3bad9f8d0090f824b53bc7818249845b00ad3f347337d5e4b6f8616f56'
        LicenseFileName = 'SCIENTIFICA_LICENSE.txt'
    }
    ForbiddenDirectoryNames = @('.cache', '.shadercache', 'captures', 'checkpoint', 'checkpoints', 'recovery', 'shader_cache', 'shadercache')
    ForbiddenFileNames = @('.env', '.env.*', 'DEBRIEF.md', 'provider*.json', 'vision.json', '*.cso', '*.log', '*.pdb', '*.tmp')
    TextExtensions = @('.fx', '.hlsl', '.hlsli', '.json', '.md', '.ps1', '.sentinel', '.txt', '.yaml', '.yml')
}
'@
    $fixtureReadme = @'
# Industrial Lattice Fixture

## Component map

| Component | Role |
| --- | --- |
| Active | Project-local renderer Module. |
| Final Output | Scene Group output endpoint. |
'@
    Write-Utf8 (Join-Path $projectRoot 'README.md') $fixtureReadme
    Write-Utf8 (Join-Path $sourceRoot '.release/reviews/fixture.json') "{`"approved`":true}`n"
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

    # Dependency closure must reject dead shared files and cross-project includes.
    $unusedShared = Join-Path $projectRoot 'modules/_shared/unused.hlsli'
    Write-Utf8 $unusedShared "float unused_fixture() { return 0.0; }`n"
    $unused = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 1
    if (@($unused.projects[0].unused_shared_files).Count -eq 0) {
        throw 'Unused project-local shared shader was not rejected.'
    }
    Remove-Item -LiteralPath $unusedShared -Force

    $foreignShared = Join-Path $sourceRoot 'projects/other/modules/_shared/leak.hlsli'
    Write-Utf8 $foreignShared "float leaked_fixture() { return 1.0; }`n"
    Write-Utf8 (Join-Path $projectRoot 'modules/Active/render.hlsl') @'
#include "../../../other/modules/_shared/leak.hlsli"
float4 mainImage(float2 uv) { return float4(leaked_fixture(), uv, 1.0); }
'@
    $crossProject = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 1
    if (-not (@($crossProject.projects[0].dependency_errors) -match 'outside its project')) {
        throw 'Cross-project shader include was not rejected.'
    }
    Remove-Item -LiteralPath (Join-Path $sourceRoot 'projects/other') -Force -Recurse
    Write-Utf8 (Join-Path $projectRoot 'modules/Active/render.hlsl') "float4 mainImage(float2 uv) { return float4(uv, 0.0, 1.0); }`n"

    # Every saved source/pipeline/output object must be explained in the README map.
    Write-Utf8 (Join-Path $projectRoot 'README.md') ($fixtureReadme.Replace('| Final Output | Scene Group output endpoint. |', ''))
    $missingComponent = Invoke-JsonScript $validator @('-Root', $sourceRoot, '-Projects', 'industrial_lattice', '-ConfigPath', $config, '-Json') 1
    if (-not (@($missingComponent.projects[0].errors) -match "README component map does not mention 'Final_Output'")) {
        throw 'Incomplete README component map was not rejected.'
    }
    Write-Utf8 (Join-Path $projectRoot 'README.md') $fixtureReadme

    # The public scaffold must create a fully project-local, valid UI module.
    $uiRoot = Join-Path $testRoot 'ui-root'
    New-Item -ItemType Directory -Path (Join-Path $uiRoot 'projects/fixture') -Force | Out-Null
    & $moduleUi new 'projects/fixture/modules/scaffolded' -Name 'Fixture UI' -Root $uiRoot | Out-Null
    & $moduleUi validate -Root $uiRoot | Out-Null
    foreach ($expected in @(
        'projects/fixture/modules/scaffolded/manifest.yaml',
        'projects/fixture/modules/scaffolded/render.hlsl',
        'projects/fixture/modules/scaffolded/_ui.generated.hlsli',
        'projects/fixture/modules/_shared/fonts/scientifica_ascii.hlsli',
        'projects/fixture/modules/_shared/fonts/SCIENTIFICA_LICENSE.txt'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $uiRoot $expected) -PathType Leaf)) {
            throw "Scaffold did not create $expected"
        }
    }

    Write-Utf8 (Join-Path $uiRoot 'projects/fixture/modules/_shared/ui/sui3_core.hlsli') "conflict`n"
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $conflictOutput = & $powerShellExe -NoProfile -File $moduleUi new 'projects/fixture/modules/rejected' -Name 'Rejected UI' -Root $uiRoot 2>&1
        $conflictExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($conflictExit -eq 0) {
        throw "Conflicting scaffold unexpectedly succeeded.`n$($conflictOutput -join "`n")"
    }
    if (Test-Path -LiteralPath (Join-Path $uiRoot 'projects/fixture/modules/rejected')) {
        throw 'Conflicting scaffold left a partial target behind.'
    }

    # Manifest regeneration must reject unsafe historical tombstones before
    # writing, while retaining safe hash-pinned tombstones.
    $manifestRoot = Join-Path $testRoot 'manifest-root'
    New-Item -ItemType Directory -Path $manifestRoot -Force | Out-Null
    git -C $manifestRoot init -q
    git -C $manifestRoot config core.autocrlf false
    Write-Utf8 (Join-Path $manifestRoot 'README.md') "fixture`n"
    $manifestConfig = Join-Path $testRoot 'manifest-config.psd1'
    Write-Utf8 $manifestConfig @'
@{
    Projects = @{}
    WorkspaceManifest = @{
        Prefixes = @()
        Files = @('README.md')
    }
    TextExtensions = @('.md')
}
'@
    $manifestPath = Join-Path $manifestRoot '.sentinel-workspace-manifest.json'
    Write-Utf8 $manifestPath @'
{
  "files": [],
  "orphan_candidates": [
    {
      "path": "../escape",
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
    }
  ],
  "schema_version": 1,
  "source_commit": "0000000000000000000000000000000000000000"
}
'@
    git -C $manifestRoot add -A
    $unsafeManifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    $zeroCommit = ('0' * 40) -join ''
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $unsafeOutput = & $powerShellExe -NoProfile -File $manifestUpdater -Root $manifestRoot -ConfigPath $manifestConfig -SourceCommit $zeroCommit 2>&1
        $unsafeExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($unsafeExit -eq 0) {
        throw "Unsafe manifest tombstone unexpectedly succeeded.`n$($unsafeOutput -join "`n")"
    }
    if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $unsafeManifestHash) {
        throw 'Unsafe manifest input was modified before rejection.'
    }

    Write-Utf8 $manifestPath @'
{
  "files": [],
  "orphan_candidates": [
    {
      "path": "retired/example.txt",
      "sha256": "1111111111111111111111111111111111111111111111111111111111111111"
    }
  ],
  "schema_version": 1,
  "source_commit": "0000000000000000000000000000000000000000"
}
'@
    & $manifestUpdater -Root $manifestRoot -ConfigPath $manifestConfig -SourceCommit $zeroCommit | Out-Null
    $updatedManifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    if (@($updatedManifest.files).Count -ne 1 -or $updatedManifest.files[0].path -ne 'README.md') {
        throw 'Manifest updater did not emit the exact managed fixture file.'
    }
    if (@($updatedManifest.orphan_candidates).Count -ne 1 -or
        $updatedManifest.orphan_candidates[0].path -ne 'retired/example.txt') {
        throw 'Manifest updater did not retain the safe hash-pinned tombstone.'
    }
    $lfManifestHash = [string]$updatedManifest.files[0].sha256
    [IO.File]::WriteAllText(
        (Join-Path $manifestRoot 'README.md'),
        "fixture`r`n",
        [Text.UTF8Encoding]::new($false)
    )
    & $manifestUpdater -Root $manifestRoot -ConfigPath $manifestConfig -SourceCommit $zeroCommit | Out-Null
    $crlfManifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    if ([string]$crlfManifest.files[0].sha256 -ne $lfManifestHash) {
        throw 'Managed text hash changed after LF-to-CRLF checkout conversion.'
    }

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
    Write-Utf8 (Join-Path $publicRoot '.release/reviews/fixture.json') "{`"approved`":true}`n"
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
    Write-Host 'PASS dependency closure rejects unused shared code and cross-project includes'
    Write-Host 'PASS README component maps cover every saved graph component'
    Write-Host 'PASS project-local UI scaffold validates and rolls back conflicts'
    Write-Host 'PASS manifest regeneration rejects unsafe tombstones and retains safe ones'
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
