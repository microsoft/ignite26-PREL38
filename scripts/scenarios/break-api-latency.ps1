[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [Parameter(Mandatory)][ValidateSet('preconfigured', 'configure')][string]$TargetAgent,
    [ValidateRange(100, 10000)][int]$ImpactedThresholdMs = 900,
    [ValidateRange(100, 10000)][int]$RecoveredThresholdMs = 600,
    [string]$ResourceGroupName
)

Import-Module (Join-Path $PSScriptRoot 'Caldova.ApiLatency.psm1') -Force
Invoke-CaldovaApiLatencyOperation -Operation Break -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent -ImpactedThresholdMs $ImpactedThresholdMs -RecoveredThresholdMs $RecoveredThresholdMs |
    ConvertTo-Json -Depth 10 -Compress
