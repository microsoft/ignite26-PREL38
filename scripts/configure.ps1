[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [string]$LearnerRepositoryUrl = $env:CALDOVA_GITHUB_REPOSITORY,
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
if ([string]::IsNullOrWhiteSpace($LearnerRepositoryUrl)) {
    throw 'LearnerRepositoryUrl or CALDOVA_GITHUB_REPOSITORY is required. Skillable/event operations must supply the isolated writable learner repository.'
}

$mode = if ($CheckOnly) { 'check' } else { 'apply' }
& node $AdapterPath $mode `
    --subscription $state.subscriptionId `
    --resource-group $state.resourceGroupName `
    --preconfigured-agent $state.preconfiguredAgentName `
    --configure-agent $state.configuredAgentName `
    --bundle $bundlePath `
    --repository $LearnerRepositoryUrl
if ($LASTEXITCODE -ne 0) {
    throw "The repository-owned SRE Agent configurator failed in '$mode' mode with exit code $LASTEXITCODE. Review the actionable error above, update the Skillable image or Azure permissions, and retry."
}

if ($CheckOnly) {
    Write-Host "Caldova SRE Agent configuration prerequisites passed for user$LearnerNumber."
    exit 0
}

Write-Host "Prepared incident skills, custom agent, response plan, GitHub source access, five weekly tasks, two Live Reports, evidence roles, and Getting started thread applied to $($state.preconfiguredAgentName)."
Write-Host "Safe evidence roles, Microsoft Learn, source context, and Getting started thread applied to $($state.configuredAgentName); GitHub OAuth and learner-created skills, response plan, tasks, and report remain intentionally incomplete."
