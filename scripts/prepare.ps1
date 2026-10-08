[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Caldova.Lifecycle.psm1') -Force

$state = Get-CaldovaState -LearnerNumber $LearnerNumber
$repositoryRoot = Get-CaldovaRepositoryRoot
$seedScript = Join-Path $repositoryRoot 'src/workload/seed.ps1'
Assert-CaldovaFile -Path $seedScript -Purpose 'Caldova workload seed entry point'
Invoke-CaldovaAz -Arguments @('account', 'set', '--subscription', $state.subscriptionId) | Out-Null

try {
    $response = Invoke-WebRequest -Uri "$($state.publicEndpoint.TrimEnd('/'))/health" -Method Get -TimeoutSec 20 -UseBasicParsing
} catch {
    throw "Caldova health check failed before seeding at '$($state.publicEndpoint)/health': $($_.Exception.Message). Confirm the application images are deployed and healthy."
}
if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 400) {
    throw "Caldova health check returned HTTP $($response.StatusCode) before seeding. Fix the deployed application before preparing lab data."
}

& $seedScript -ResourceGroupName $state.resourceGroupName -LearnerNumber $LearnerNumber

$baseUri = $state.publicEndpoint.TrimEnd('/')
$trafficPaths = @(
    '/health',
    '/ready',
    '/api/summary',
    '/api/courses',
    '/api/quiz/OPS-201-M1',
    '/api/grades/learner/LRN-1001',
    '/api/exports/recent'
)
$measurements = [System.Collections.Generic.List[object]]::new()
foreach ($round in 1..3) {
    foreach ($path in $trafficPaths) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $trafficResponse = Invoke-WebRequest -Uri "$baseUri$path" -Method Get -TimeoutSec 30 -UseBasicParsing
        } catch {
            throw "Baseline traffic failed for '$path' in round ${round}: $($_.Exception.Message). Confirm Application Gateway, the portal, the API, and PostgreSQL are healthy."
        } finally {
            $stopwatch.Stop()
        }
        if ($trafficResponse.StatusCode -lt 200 -or $trafficResponse.StatusCode -ge 300) {
            throw "Baseline traffic returned HTTP $($trafficResponse.StatusCode) for '$path' in round $round."
        }
        $measurements.Add([pscustomobject]@{
            round = $round
            path = $path
            statusCode = $trafficResponse.StatusCode
            elapsedMs = $stopwatch.ElapsedMilliseconds
        })
    }
}

$apiName = Invoke-CaldovaAz -Arguments @(
    'containerapp', 'list',
    '--resource-group', $state.resourceGroupName,
    '--query', "[?starts_with(name, 'ca-caldova-api-')].name | [0]",
    '--output', 'tsv'
)
$apiName = ($apiName | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($apiName)) {
    throw "Caldova API container app was not found in '$($state.resourceGroupName)' after seeding."
}
$databaseCheck = Invoke-CaldovaAz -Arguments @(
    'containerapp', 'exec',
    '--resource-group', $state.resourceGroupName,
    '--name', $apiName,
    '--command', 'node /app/scripts/db-check.js'
)
if (($databaseCheck | Out-String) -notmatch '"status"\s*:\s*"ok"') {
    throw "Caldova database verification did not return an ok status through the private API container path. Output:`n$($databaseCheck | Out-String)"
}

$workspaceCustomerId = Invoke-CaldovaAz -Arguments @(
    'monitor', 'log-analytics', 'workspace', 'show',
    '--resource-group', $state.resourceGroupName,
    '--workspace-name', $state.logAnalyticsWorkspaceName,
    '--query', 'customerId',
    '--output', 'tsv'
)
$workspaceCustomerId = ($workspaceCustomerId | Out-String).Trim()
$heartbeatQuery = @"
Syslog
| where TimeGenerated > ago(15m)
| where ProcessName == "caldova-reporting"
| where SyslogMessage has "category=CaldovaReportingHeartbeat"
| where SyslogMessage has "status=ok"
| top 1 by TimeGenerated desc
| project TimeGenerated, SyslogMessage
"@
$heartbeat = $null
$heartbeatDeadline = [DateTime]::UtcNow.AddMinutes(8)
do {
    $heartbeat = Invoke-CaldovaAz -Arguments @(
        'monitor', 'log-analytics', 'query',
        '--workspace', $workspaceCustomerId,
        '--analytics-query', $heartbeatQuery,
        '--output', 'json'
    ) -ReturnJson
    if (@($heartbeat).Count -gt 0) {
        break
    }
    Start-Sleep -Seconds 20
} while ([DateTime]::UtcNow -lt $heartbeatDeadline)
if (@($heartbeat).Count -eq 0) {
    throw "No successful Caldova reporting heartbeat reached Log Analytics within 8 minutes. On '$($state.reportingWorkerName)', inspect cloud-init, caldova-reporting.timer, managed-identity access to Key Vault, and PostgreSQL connectivity."
}

$baselinePath = Join-Path (Split-Path (Get-CaldovaStatePath -LearnerNumber $LearnerNumber) -Parent) "baseline-user$LearnerNumber.json"
@{
    schemaVersion = 1
    learnerNumber = $LearnerNumber
    preparedAtUtc = [DateTime]::UtcNow.ToString('o')
    publicEndpoint = $state.publicEndpoint
    traffic = $measurements
    databaseCheck = (($databaseCheck | Out-String).Trim())
    reportingHeartbeat = @($heartbeat)[0]
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $baselinePath -Encoding utf8NoBOM

Write-Host "Prepare complete for user$LearnerNumber. Baseline: $baselinePath"
foreach ($measurement in $measurements) {
    Write-Host ("HTTP {0} {1} ms={2}" -f $measurement.statusCode, $measurement.path, $measurement.elapsedMs)
}
