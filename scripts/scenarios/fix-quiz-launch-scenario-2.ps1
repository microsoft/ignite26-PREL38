<#
.SYNOPSIS
Restores the saved live baseline for Scenario 2. This is mitigation only; Reset also restores response-plan ownership and clears exercise state.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [Parameter(Mandatory)][ValidateSet('preconfigured', 'configure')][string]$TargetAgent,
    [string]$ResourceGroupName
)
Import-Module (Join-Path $PSScriptRoot 'Caldova.QuizLaunch.psm1') -Force
Invoke-CaldovaQuizLaunchOperation -Operation Fix -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent -ScenarioNumber 2 | ConvertTo-Json -Depth 10 -Compress
