[CmdletBinding()]
param([Parameter(Mandatory)][ValidateRange(1,999)][int]$LearnerNumber,[Parameter(Mandatory)][ValidateSet('preconfigured','configure')][string]$TargetAgent,[string]$ResourceGroupName)
Import-Module (Join-Path $PSScriptRoot 'Caldova.DataScenarios.psm1') -Force
Invoke-CaldovaDataScenarioOperation -Operation Break -ScenarioId quiz-intermittent-failures -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent | ConvertTo-Json -Depth 10 -Compress
