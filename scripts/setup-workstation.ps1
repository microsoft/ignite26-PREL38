[CmdletBinding()]
param(
    [ValidateSet('ImageAuthoring', 'PreRun')][string]$Mode = 'PreRun',
    [string]$ApprovedSrectlVersion = '1.0.43'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:CALDOVA_ATTENDEE_RUNTIME -eq '1') {
    throw 'Workstation setup is an image-authoring/pre-run activity, not an attendee activity. Use the prepared workstation and contact the facilitator.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npm) {
    throw 'npm is unavailable. Install Node.js 22+ in the base image before running this offline setup.'
}

Write-Host "Preparing Caldova repository dependencies in $Mode mode. Network downloads are disabled."
foreach ($relativePath in @('src/api', 'src/portal')) {
    $packageRoot = Join-Path $repositoryRoot $relativePath
    $lockPath = Join-Path $packageRoot 'package-lock.json'
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        throw "Offline setup cannot continue because '$lockPath' is missing."
    }
    & $npm.Source --prefix $packageRoot ci --offline --ignore-scripts --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
        throw "Offline npm setup failed for '$relativePath'. Populate the image's npm cache during image authoring and rerun; attendee-time downloads are prohibited."
    }
}

& (Join-Path $PSScriptRoot 'check-workstation.ps1') -ApprovedSrectlVersion $ApprovedSrectlVersion
if ($LASTEXITCODE -ne 0) {
    throw 'Workstation verification failed after offline setup. Review the prerequisite errors above.'
}

Write-Host 'Offline Caldova workstation setup completed. No package was downloaded.'

