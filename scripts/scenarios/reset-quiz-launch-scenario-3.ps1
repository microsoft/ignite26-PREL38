[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [ValidateSet('preconfigured', 'configure')][string]$TargetAgent = 'preconfigured',
    [string]$ResourceGroupName
)
Import-Module (Join-Path $PSScriptRoot 'Caldova.QuizLaunch.psm1') -Force
Invoke-CaldovaQuizLaunchOperation -Operation Reset -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent -ScenarioNumber 3 | ConvertTo-Json -Depth 10 -Compress
