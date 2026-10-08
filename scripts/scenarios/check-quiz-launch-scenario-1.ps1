[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [Parameter(Mandatory)][ValidateSet('preconfigured', 'configure')][string]$TargetAgent,
    [string]$ResourceGroupName
)
Import-Module (Join-Path $PSScriptRoot 'Caldova.QuizLaunch.psm1') -Force
Invoke-CaldovaQuizLaunchOperation -Operation Check -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent -ScenarioNumber 1 | ConvertTo-Json -Depth 10 -Compress
