[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [Parameter(Mandatory)][ValidateSet('Apply', 'Enable', 'Disable', 'Verify')][string]$Operation,
    [ValidateSet('enabled', 'disabled')][string]$Expected
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Caldova.Lifecycle.psm1') -Force

$state = Get-CaldovaState -LearnerNumber $LearnerNumber
$adapter = Join-Path $PSScriptRoot 'configure-guided-recommendations.mjs'
Assert-CaldovaFile -Path $adapter -Purpose 'Guided recommendations lifecycle adapter'
Assert-CaldovaCommand -Name 'node'

$operationName = $Operation.ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($Expected)) {
    $Expected = if ($Operation -eq 'Enable') { 'enabled' } else { 'disabled' }
}

& node $adapter $operationName `
    --subscription $state.subscriptionId `
    --resource-group $state.resourceGroupName `
    --preconfigured-agent $state.preconfiguredAgentName `
    --configure-agent $state.configuredAgentName `
    --expected $Expected
if ($LASTEXITCODE -ne 0) {
    throw "Guided recommendations '$Operation' failed with exit code $LASTEXITCODE. Review the actionable error above and retry."
}
