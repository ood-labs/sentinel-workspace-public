[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'validate-official-examples.ps1'
$config = Join-Path $PSScriptRoot 'official-examples.config.psd1'
$moduleUi = Join-Path $PSScriptRoot 'module-ui.ps1'
$powerShellExe = (Get-Process -Id $PID).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("sentinel-official-examples-{0}" -f [guid]::NewGuid().ToString('N'))
$sourceRoot = Join-Path $testRoot 'private'
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
                }
            )
        }
    }
    Write-Utf8 (Join-Path $projectRoot 'industrial_lattice.sentinel') (($project | ConvertTo-Json -Depth 12) + "`n")
}

try {
    New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
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

    Write-Host 'PASS normalized manifest hashing is checkout-line-ending invariant'
    Write-Host 'PASS validator reports absolute path, orphan module, and shader cache independently'
    Write-Host 'PASS repaired fixture validates cleanly'
    Write-Host 'PASS validator rejects workspace escapes and duplicate root project files'
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
