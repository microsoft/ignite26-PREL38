[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$Location,
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [Parameter(Mandatory)][string]$DeploymentToken,
    [Parameter(Mandatory)][string]$PortalImage,
    [Parameter(Mandatory)][string]$ApiImage,
    [Parameter(Mandatory)][string]$ApiLatencyImage,
    [ValidateRange(100, 10000)][int]$QuizLatencyThresholdMs = 900,
    [Parameter(Mandatory)][string]$VmAdminSshPublicKey,
    [string]$PostgresLocation,
    [string]$ApprovedSrectlVersion = '1.0.43'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Stage {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    Write-Host "==> $Name"
    try {
        & $Action
        if ($LASTEXITCODE -ne 0) {
            throw "Process returned exit code $LASTEXITCODE."
        }
        Write-Host "<== $Name completed"
    } catch {
        throw "$Name failed for learner $LearnerNumber. $($_.Exception.Message)"
    }
}

Invoke-Stage -Name 'Workstation prerequisite check' -Action {
    & (Join-Path $PSScriptRoot 'check-workstation.ps1') -ApprovedSrectlVersion $ApprovedSrectlVersion
}

Invoke-Stage -Name 'Provision' -Action {
    $arguments = @{
        SubscriptionId = $SubscriptionId
        Location = $Location
        LearnerNumber = $LearnerNumber
        DeploymentToken = $DeploymentToken
        PortalImage = $PortalImage
        ApiImage = $ApiImage
        ApiLatencyImage = $ApiLatencyImage
        QuizLatencyThresholdMs = $QuizLatencyThresholdMs
        VmAdminSshPublicKey = $VmAdminSshPublicKey
    }
    if (-not [string]::IsNullOrWhiteSpace($PostgresLocation)) {
        $arguments.PostgresLocation = $PostgresLocation
    }
    & (Join-Path $PSScriptRoot 'provision.ps1') @arguments
}

Invoke-Stage -Name 'Configure' -Action {
    & (Join-Path $PSScriptRoot 'configure.ps1') -LearnerNumber $LearnerNumber
}

Invoke-Stage -Name 'Prepare' -Action {
    & (Join-Path $PSScriptRoot 'prepare.ps1') -LearnerNumber $LearnerNumber
}

Invoke-Stage -Name 'Readiness' -Action {
    & (Join-Path $PSScriptRoot 'readiness.ps1') -LearnerNumber $LearnerNumber
}

Import-Module (Join-Path $PSScriptRoot 'Caldova.Lifecycle.psm1') -Force
$state = Get-CaldovaState -LearnerNumber $LearnerNumber
$simulatorUrl = "http://127.0.0.1:7070/?learnerNumber=$LearnerNumber"

Write-Host ''
Write-Host "Caldova learner $LearnerNumber is ready."
Write-Host "Portal: $($state.publicEndpoint)"
Write-Host "Preconfigured agent: $($state.preconfiguredAgentPortalUrl)"
Write-Host "Configure-path agent: $($state.configuredAgentPortalUrl)"
Write-Host "Simulator: $simulatorUrl"
Write-Host "Start simulator: pwsh -NoProfile -File scripts/start-simulator.ps1 -LearnerNumber $LearnerNumber"

