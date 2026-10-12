[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Caldova.Lifecycle.psm1') -Force

$state = Get-CaldovaState -LearnerNumber $LearnerNumber
if ($state.resourceGroupName -notmatch "^rg-caldova-user$LearnerNumber-[a-z0-9]+$") {
    throw "Refusing teardown because resource group '$($state.resourceGroupName)' does not match the Caldova user$LearnerNumber naming contract."
}

Invoke-CaldovaAz -Arguments @('account', 'set', '--subscription', $state.subscriptionId) | Out-Null
$target = "$($state.resourceGroupName) in subscription $($state.subscriptionId)"
if ($Force -or $PSCmdlet.ShouldProcess($target, 'Delete Caldova learner resource group')) {
    if (
        $state.PSObject.Properties.Name -contains 'imageRegistryResourceId' -and
        $state.PSObject.Properties.Name -contains 'appIdentityPrincipalId' -and
        -not [string]::IsNullOrWhiteSpace($state.imageRegistryResourceId) -and
        -not [string]::IsNullOrWhiteSpace($state.appIdentityPrincipalId)
    ) {
        $registryAssignments = @(
            Invoke-CaldovaAz -Arguments @(
                'role', 'assignment', 'list',
                '--scope', $state.imageRegistryResourceId,
                '--assignee-object-id', $state.appIdentityPrincipalId,
                '--role', 'AcrPull',
                '--query', '[].id',
                '--output', 'json'
            ) -ReturnJson
        )
        foreach ($assignmentId in $registryAssignments) {
            Invoke-CaldovaAz -Arguments @(
                'role', 'assignment', 'delete',
                '--ids', $assignmentId,
                '--output', 'none'
            ) | Out-Null
        }
    }

    Invoke-CaldovaAz -Arguments @('group', 'delete', '--name', $state.resourceGroupName, '--yes', '--no-wait') | Out-Null
    Remove-Item -LiteralPath (Get-CaldovaStatePath -LearnerNumber $LearnerNumber) -Force
    Write-Host "Teardown accepted for $target. Azure deletion is running asynchronously."
}
