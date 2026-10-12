[CmdletBinding()]
param([Parameter(Mandatory)][ValidateRange(1,999)][int]$LearnerNumber,[ValidateSet('preconfigured','configure')][string]$TargetAgent='preconfigured',[string]$ResourceGroupName)
Import-Module (Join-Path $PSScriptRoot 'Caldova.CourseRecommendations.psm1') -Force
Invoke-CaldovaRecommendationsOperation -Operation Reset -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent | ConvertTo-Json -Depth 10 -Compress
