[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [ValidateRange(1024, 65535)][int]$Port = 7070,
    [switch]$Mock,
    [switch]$NoBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$serverPath = Join-Path $repositoryRoot 'simulator/server.js'
if (-not (Test-Path -LiteralPath $serverPath -PathType Leaf)) {
    throw "Simulator entry point is missing at '$serverPath'. Restore the packaged repository and retry."
}
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    throw 'Node.js 22+ is unavailable. The workstation image must be repaired before the lab; attendee-time downloads are not supported.'
}

$baseUrl = "http://127.0.0.1:$Port"
$learnerUrl = "$baseUrl/?learnerNumber=$LearnerNumber"
try {
    $existing = Invoke-WebRequest -Uri "$baseUrl/api/status?learnerNumber=$LearnerNumber" -TimeoutSec 2 -UseBasicParsing
    if ($existing.StatusCode -eq 200) {
        throw "A simulator is already listening at $baseUrl. Use that window or stop its owning terminal before starting another instance."
    }
} catch {
    if ($_.Exception.Message -like 'A simulator is already listening*') {
        throw
    }
}

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $node.Source
$startInfo.ArgumentList.Add($serverPath)
$startInfo.WorkingDirectory = $repositoryRoot
$startInfo.UseShellExecute = $false
$startInfo.Environment['PORT'] = [string]$Port
$startInfo.Environment['CALDOVA_LEARNER_NUMBER'] = [string]$LearnerNumber
if ($Mock) {
    $startInfo.Environment['SIMULATOR_DRIVER'] = 'mock'
}

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
    throw 'The local simulator process could not be started.'
}

try {
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    $status = $null
    do {
        if ($process.HasExited) {
            throw "The simulator exited before readiness with code $($process.ExitCode). Review the console output above."
        }
        try {
            $page = Invoke-WebRequest -Uri $learnerUrl -TimeoutSec 2 -UseBasicParsing
            $statusResponse = Invoke-RestMethod -Uri "$baseUrl/api/status?learnerNumber=$LearnerNumber" -TimeoutSec 2
            if ($page.StatusCode -eq 200 -and $statusResponse.learnerNumber -eq $LearnerNumber) {
                $status = $statusResponse
                break
            }
        } catch {
            Start-Sleep -Milliseconds 300
        }
    } while ([DateTime]::UtcNow -lt $deadline)

    if ($null -eq $status) {
        throw "The simulator did not become ready at $learnerUrl within 20 seconds. Stop this command, inspect port $Port, and retry."
    }

    Write-Host "Caldova simulator ready: $learnerUrl"
    Write-Host "Status endpoint: $baseUrl/api/status?learnerNumber=$LearnerNumber"
    Write-Host 'Keep this terminal open. Press Ctrl+C to stop the local simulator cleanly.'
    if (-not $NoBrowser) {
        Start-Process $learnerUrl
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "The simulator exited with code $($process.ExitCode)."
    }
} finally {
    if (-not $process.HasExited) {
        $process.Kill($true)
        $process.WaitForExit(5000) | Out-Null
        Write-Host 'Caldova simulator stopped.'
    }
    $process.Dispose()
}

