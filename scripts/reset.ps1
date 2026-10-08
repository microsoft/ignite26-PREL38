[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [string]$Scenario = 'baseline'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Caldova.Lifecycle.psm1') -Force

$state = Get-CaldovaState -LearnerNumber $LearnerNumber
$repositoryRoot = Get-CaldovaRepositoryRoot
$resetScript = Join-Path $repositoryRoot "scripts/scenarios/reset-$Scenario.ps1"
Assert-CaldovaFile -Path $resetScript -Purpose "Scenario reset entry point for '$Scenario'"

& $resetScript -ResourceGroupName $state.resourceGroupName -LearnerNumber $LearnerNumber
if ($LASTEXITCODE -ne 0) {
    throw "Scenario reset '$Scenario' failed with exit code $LASTEXITCODE. The lab was not reported as healthy."
}

& (Join-Path $PSScriptRoot 'readiness.ps1') -LearnerNumber $LearnerNumber
if ($LASTEXITCODE -ne 0) {
    throw "Scenario reset completed, but readiness did not pass for user$LearnerNumber."
}
