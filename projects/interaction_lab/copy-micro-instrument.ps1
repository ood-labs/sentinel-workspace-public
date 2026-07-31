[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Micro_LFO', 'Micro_Scope', 'Micro_Sequencer', 'Micro_Envelope')]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$TargetProject,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$labRoot = Split-Path -Parent $PSCommandPath
$sourceModule = Join-Path $labRoot "modules\$Name"
$sourceUi = Join-Path $labRoot 'modules\_shared\ui'
$targetRoot = [System.IO.Path]::GetFullPath($TargetProject)
$targetModules = Join-Path $targetRoot 'modules'
$targetModule = Join-Path $targetModules $Name
$targetUi = Join-Path $targetModules '_shared\ui'

if (-not (Test-Path -LiteralPath $sourceModule -PathType Container)) {
    throw "Source module not found: $sourceModule"
}
if ((Test-Path -LiteralPath $targetModule) -and -not $Force) {
    throw "Target already exists: $targetModule (use -Force to replace files)"
}

New-Item -ItemType Directory -Force -Path $targetModules | Out-Null
New-Item -ItemType Directory -Force -Path $targetUi | Out-Null
Copy-Item -Path (Join-Path $sourceUi '*') -Destination $targetUi -Recurse -Force
Copy-Item -LiteralPath $sourceModule -Destination $targetModules -Recurse -Force

Get-ChildItem -LiteralPath $targetModule -Directory -Recurse -Force |
    Where-Object { $_.Name -eq '.sentinel' } |
    Remove-Item -Recurse -Force

Write-Host "Copied $Name to $targetModule"
Write-Host "Copied shared SUI3 dependency closure to $targetUi"
