[CmdletBinding()]
param(
    [string]$ApprovedSrectlVersion = '1.0.43',
    [switch]$SkipRepositoryDependencies
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$requiredAzmcpVersion = '3.0.0-beta.43'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)
    $failures.Add($Message)
}

function Get-CommandOutput {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $output = & $Command @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw (($output | Out-String).Trim())
    }
    return (($output | Out-String).Trim())
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Add-Failure "PowerShell 7 or later is required; found $($PSVersionTable.PSVersion). Install it in the workstation image before the lab."
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Add-Failure 'Node.js 22 or later is missing. Install it during image authoring; attendee-time downloads are not supported.'
} else {
    try {
        $nodeVersion = Get-CommandOutput -Command $node.Source -Arguments @('--version')
        $nodeMajor = [int](($nodeVersion -replace '^v', '').Split('.')[0])
        if ($nodeMajor -lt 22) {
            Add-Failure "Node.js 22 or later is required; found $nodeVersion."
        }
    } catch {
        Add-Failure "Node.js version check failed: $($_.Exception.Message)"
    }
}

$npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npm) {
    Add-Failure 'npm is missing. Install it with Node.js during image authoring.'
} else {
    try {
        $globalRoot = Get-CommandOutput -Command $npm.Source -Arguments @('root', '-g')
        $azureMcpPackage = Join-Path $globalRoot '@azure/mcp/package.json'
        if (-not (Test-Path -LiteralPath $azureMcpPackage -PathType Leaf)) {
            Add-Failure "@azure/mcp@$requiredAzmcpVersion is not installed globally. Preinstall the pinned package in the workstation image."
        } else {
            $installedAzmcpVersion = (Get-Content -LiteralPath $azureMcpPackage -Raw | ConvertFrom-Json).version
            if ($installedAzmcpVersion -ne $requiredAzmcpVersion) {
                Add-Failure "@azure/mcp must be exactly $requiredAzmcpVersion; found $installedAzmcpVersion."
            }
        }
    } catch {
        Add-Failure "Azure MCP package check failed: $($_.Exception.Message)"
    }
}

$az = Get-Command az -ErrorAction SilentlyContinue
if (-not $az) {
    Add-Failure 'Azure CLI is missing. Install it in the workstation image before the lab.'
} else {
    try {
        $null = Get-CommandOutput -Command $az.Source -Arguments @('version', '--output', 'json')
        $bicepVersion = Get-CommandOutput -Command $az.Source -Arguments @('bicep', 'version')
        if ($bicepVersion -notmatch 'Bicep CLI version') {
            Add-Failure "Azure CLI could not verify Bicep. Output: $bicepVersion"
        }
    } catch {
        Add-Failure "Azure CLI/Bicep check failed: $($_.Exception.Message)"
    }
}

$srectl = Get-Command srectl -ErrorAction SilentlyContinue
if (-not $srectl) {
    Add-Failure "The approved srectl $ApprovedSrectlVersion CLI is missing. Install the approved offline package during image authoring."
} else {
    try {
        $srectlVersionOutput = Get-CommandOutput -Command $srectl.Source -Arguments @('version')
        if ($srectlVersionOutput -notmatch [regex]::Escape($ApprovedSrectlVersion)) {
            Add-Failure "srectl must be the approved version $ApprovedSrectlVersion; the installed command reported a different version."
        }
    } catch {
        Add-Failure "srectl version check failed: $($_.Exception.Message)"
    }
}

if (-not $SkipRepositoryDependencies -and $npm) {
    foreach ($relativePath in @('src/api', 'src/portal')) {
        $packageRoot = Join-Path $repositoryRoot $relativePath
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'package-lock.json') -PathType Leaf)) {
            Add-Failure "$relativePath/package-lock.json is missing; offline dependency verification cannot be deterministic."
            continue
        }
        try {
            $null = Get-CommandOutput -Command $npm.Source -Arguments @('--prefix', $packageRoot, 'ls', '--depth=0')
        } catch {
            Add-Failure "$relativePath npm dependencies are not ready. Run scripts/setup-workstation.ps1 during image authoring or pre-run. Detail: $($_.Exception.Message)"
        }
    }
}

if ($failures.Count -gt 0) {
    $detail = ($failures | ForEach-Object { "- $_" }) -join [Environment]::NewLine
    throw "Caldova workstation prerequisites failed:`n$detail"
}

Write-Host 'Caldova workstation prerequisites passed.'
Write-Host "Node.js: $nodeVersion"
Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
Write-Host "Azure MCP: $requiredAzmcpVersion"
Write-Host "srectl: $ApprovedSrectlVersion"
Write-Host 'Azure CLI, Bicep, and repository npm dependencies are available.'

