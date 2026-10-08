[CmdletBinding()]
param([Parameter(Mandatory)][ValidateRange(1,999)][int]$LearnerNumber,[ValidateSet('preconfigured','configure')][string]$TargetAgent='preconfigured',[string]$ResourceGroupName)
Import-Module (Join-Path $PSScriptRoot 'Caldova.DataScenarios.psm1') -Force
Invoke-CaldovaDataScenarioOperation -Operation Reset -ScenarioId quiz-intermittent-failures -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent | ConvertTo-Json -Depth 10 -Compress
