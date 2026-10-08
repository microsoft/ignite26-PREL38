[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [string]$AdapterPath,
    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Caldova.Lifecycle.psm1') -Force

$state = Get-CaldovaState -LearnerNumber $LearnerNumber
Invoke-CaldovaAz -Arguments @('account', 'set', '--subscription', $state.subscriptionId) | Out-Null

$repositoryRoot = Get-CaldovaRepositoryRoot
$bundlePath = Join-Path $repositoryRoot 'data/agent/configuration.json'
Assert-CaldovaFile -Path $bundlePath -Purpose 'Prepared SRE Agent configuration manifest'
if ([string]::IsNullOrWhiteSpace($AdapterPath)) {
    $AdapterPath = Join-Path $PSScriptRoot 'configure-agent.mjs'
}
Assert-CaldovaFile -Path $AdapterPath -Purpose 'Repository-owned Caldova SRE Agent configurator'
Assert-CaldovaCommand -Name 'node'

$mode = if ($CheckOnly) { 'check' } else { 'apply' }
& node $AdapterPath $mode `
    --subscription $state.subscriptionId `
    --resource-group $state.resourceGroupName `
    --preconfigured-agent $state.preconfiguredAgentName `
    --configure-agent $state.configuredAgentName `
    --bundle $bundlePath
if ($LASTEXITCODE -ne 0) {
    throw "The repository-owned SRE Agent configurator failed in '$mode' mode with exit code $LASTEXITCODE. Review the actionable error above, update the Skillable image or Azure permissions, and retry."
}

if ($CheckOnly) {
    Write-Host "Caldova SRE Agent configuration prerequisites passed for user$LearnerNumber."
    exit 0
}

Write-Host "Prepared response configuration applied to $($state.preconfiguredAgentName)."
Write-Host "Secure connectors and source context applied to $($state.configuredAgentName); learner-authored skill, custom agent, and response plan remain intentionally absent."
