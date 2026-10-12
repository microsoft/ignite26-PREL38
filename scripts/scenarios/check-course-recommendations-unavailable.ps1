[CmdletBinding()]
param([Parameter(Mandatory)][ValidateRange(1,999)][int]$LearnerNumber,[Parameter(Mandatory)][ValidateSet('preconfigured','configure')][string]$TargetAgent,[string]$ResourceGroupName)
Import-Module (Join-Path $PSScriptRoot 'Caldova.CourseRecommendations.psm1') -Force
Invoke-CaldovaRecommendationsOperation -Operation Check -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent | ConvertTo-Json -Depth 10 -Compress
