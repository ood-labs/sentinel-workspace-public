param(
    [Parameter(Mandatory = $true)]
    [string]$Tool,

    [Parameter(Mandatory = $true)]
    [string]$ArgumentsJson
)

$ErrorActionPreference = 'Stop'

$server = 'C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe'
$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $server
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.CreateNoWindow = $true

$process = [Diagnostics.Process]::Start($startInfo)

function Send-Message([hashtable]$Message) {
    $json = $Message | ConvertTo-Json -Depth 30 -Compress
    $process.StandardInput.WriteLine($json)
    $process.StandardInput.Flush()
}

function Read-Response([int]$Id) {
    while (-not $process.HasExited) {
        $line = $process.StandardOutput.ReadLine()
        if ($null -eq $line) { break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $message = $line | ConvertFrom-Json
        if ($message.id -eq $Id) { return $message }
    }
    throw "Sentinel MCP closed before response id $Id"
}

try {
    Send-Message @{
        jsonrpc = '2.0'
        id = 1
        method = 'initialize'
        params = @{
            protocolVersion = '2025-03-26'
            capabilities = @{}
            clientInfo = @{ name = 'codex-local'; version = '1.0' }
        }
    }
    $null = Read-Response 1

    Send-Message @{
        jsonrpc = '2.0'
        method = 'notifications/initialized'
        params = @{}
    }

    $argumentsObject = $ArgumentsJson | ConvertFrom-Json
    $arguments = @{}
    foreach ($property in $argumentsObject.PSObject.Properties) {
        $arguments[$property.Name] = $property.Value
    }
    Send-Message @{
        jsonrpc = '2.0'
        id = 2
        method = 'tools/call'
        params = @{
            name = $Tool
            arguments = $arguments
        }
    }

    $response = Read-Response 2
    $response | ConvertTo-Json -Depth 30
}
finally {
    if (-not $process.HasExited) {
        $process.Kill()
        $process.WaitForExit()
    }
}
