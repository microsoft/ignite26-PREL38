Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\Caldova.Lifecycle.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Caldova.QuizLaunch.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Caldova.ApiLatency.psm1') -Force

$script:QuestionBankIndex = 'idx_question_bank_assessment_active'
$script:ReportingFiller = '/var/lib/caldova/.caldova-reporting-output-missing.filler'
$script:ReportingAlert = 'Caldova-reporting-output-missing'
$script:AlertsApiVersion = '2019-03-01'

function Get-CaldovaDataScenarioContext {
    param(
        [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
        [Parameter(Mandatory)][ValidateSet('preconfigured', 'configure')][string]$TargetAgent,
        [Parameter(Mandatory)][ValidateSet('quiz-search-slow', 'quiz-intermittent-failures', 'quiz-consistent-failures', 'reporting-output-missing')][string]$ScenarioId
    )
    $context = Get-CaldovaQuizLaunchContext -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent -ScenarioNumber 3
    $context.ScenarioId = $ScenarioId
    $context.AlertName = if ($ScenarioId -eq 'quiz-search-slow') {
        'Caldova-quiz-response-time-elevated'
    } elseif ($ScenarioId -eq 'reporting-output-missing') {
        $script:ReportingAlert
    } else {
        'Caldova-quiz-launch-failing'
    }
    return $context
}

function Invoke-CaldovaApiExec {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$Command
    )
    $app = Get-CaldovaApiApp -Context $Context
    return Invoke-CaldovaAz -Arguments @(
        'containerapp', 'exec',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $app.name,
        '--command', $Command
    )
}

function Get-CaldovaIndexStatus {
    param([Parameter(Mandatory)]$Context)
    $output = Invoke-CaldovaApiExec -Context $Context -Command 'node /app/scripts/question-bank-index.js status'
    $line = @($output) | Where-Object { $_ -match '^\{' } | Select-Object -Last 1
    if (-not $line) { throw 'The private question lookup check did not return a result.' }
    return $line | ConvertFrom-Json
}

function Set-CaldovaIndexState {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][ValidateSet('drop', 'recreate')][string]$Action
    )
    $output = Invoke-CaldovaApiExec -Context $Context -Command "node /app/scripts/question-bank-index.js $Action"
    $line = @($output) | Where-Object { $_ -match '^\{' } | Select-Object -Last 1
    if (-not $line) { throw "The private question lookup action '$Action' did not return a result." }
    $result = $line | ConvertFrom-Json
    $expected = $Action -eq 'recreate'
    if ([bool]$result.present -ne $expected -or $result.index -ne $script:QuestionBankIndex) {
        throw "Question lookup action '$Action' did not reach the expected state."
    }
    return $result
}

function Get-CaldovaAppEnvironmentSnapshot {
    param([Parameter(Mandatory)]$Context)
    $app = Get-CaldovaApiApp -Context $Context
    $names = @('POSTGRES_POOL_MAX', 'POSTGRES_CONNECT_TIMEOUT_MS', 'CALDOVA_DB_HOLD_MS', 'CALDOVA_SECRET_REFRESH')
    $values = @{}
    foreach ($name in $names) {
        $entry = @($app.properties.template.containers[0].env) | Where-Object { $_.name -eq $name } | Select-Object -First 1
        $values[$name] = if ($null -eq $entry) {
            @{ present = $false }
        } else {
            @{ present = $true; value = [string]$entry.value; secretRef = [string]$entry.secretRef }
        }
    }
    return [pscustomobject]@{
        appName = $app.name
        image = $app.properties.template.containers[0].image
        revisionMode = $app.properties.configuration.activeRevisionsMode
        latestRevisionName = $app.properties.latestRevisionName
        latestReadyRevisionName = $app.properties.latestReadyRevisionName
        environment = $values
    }
}

function Set-CaldovaAppVariables {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string[]]$Values
    )
    $app = Get-CaldovaApiApp -Context $Context
    $arguments = @(
        'containerapp', 'update',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $app.name,
        '--set-env-vars'
    ) + $Values + @('--output', 'none')
    Invoke-CaldovaAz -Arguments $arguments | Out-Null
}

function Restore-CaldovaAppVariables {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Snapshot
    )
    $set = [System.Collections.Generic.List[string]]::new()
    $remove = [System.Collections.Generic.List[string]]::new()
    foreach ($property in $Snapshot.environment.PSObject.Properties) {
        if ($property.Value.present) {
            if (-not [string]::IsNullOrWhiteSpace($property.Value.secretRef)) {
                throw "Refusing to restore scenario variable '$($property.Name)' from a secret value."
            }
            $set.Add("$($property.Name)=$($property.Value.value)")
        } else {
            $remove.Add($property.Name)
        }
    }
    $appName = $Snapshot.appName
    if ($set.Count -gt 0) {
        $arguments = @('containerapp', 'update', '--resource-group', $Context.State.resourceGroupName, '--name', $appName, '--set-env-vars') + @($set) + @('--output', 'none')
        Invoke-CaldovaAz -Arguments $arguments | Out-Null
    }
    if ($remove.Count -gt 0) {
        $arguments = @('containerapp', 'update', '--resource-group', $Context.State.resourceGroupName, '--name', $appName, '--remove-env-vars') + @($remove) + @('--output', 'none')
        Invoke-CaldovaAz -Arguments $arguments | Out-Null
    }
}

function Wait-CaldovaApiReady {
    param([Parameter(Mandatory)]$Context, [int]$TimeoutSeconds = 300)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $app = Get-CaldovaApiApp -Context $Context
        if ($app.properties.latestReadyRevisionName -eq $app.properties.latestRevisionName) { return $app }
        Start-Sleep -Seconds 10
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'The quiz service did not reach a ready state within five minutes.'
}

function Measure-CaldovaConcurrentQuizTraffic {
    param(
        [Parameter(Mandatory)]$Context,
        [int]$Requests = 12
    )
    $jobs = foreach ($attempt in 1..$Requests) {
        Start-ThreadJob -ScriptBlock {
            param($Uri, $Attempt)
            try {
                $response = Invoke-WebRequest -Uri "$Uri?pressure=$Attempt" -TimeoutSec 10 -UseBasicParsing -SkipHttpErrorCheck
                [pscustomobject]@{ status = [int]$response.StatusCode }
            } catch {
                [pscustomobject]@{ status = 0 }
            }
        } -ArgumentList $Context.PublicQuizUri, $attempt
    }
    $results = @($jobs | Wait-Job | Receive-Job)
    $jobs | Remove-Job -Force
    return [pscustomobject]@{
        requests = $Requests
        successes = @($results | Where-Object status -eq 200).Count
        failures = @($results | Where-Object { $_.status -eq 0 -or $_.status -ge 500 }).Count
    }
}

function Get-CaldovaPostgresSecretSnapshot {
    param([Parameter(Mandatory)]$Context)
    $app = Get-CaldovaApiApp -Context $Context
    $secret = @($app.properties.configuration.secrets) | Where-Object { $_.name -eq 'postgres-password' } | Select-Object -First 1
    $env = @($app.properties.template.containers[0].env) | Where-Object { $_.name -eq 'POSTGRES_PASSWORD' } | Select-Object -First 1
    if ($null -eq $secret -or [string]::IsNullOrWhiteSpace($secret.keyVaultUrl) -or [string]::IsNullOrWhiteSpace($secret.identity)) {
        throw 'The quiz service credential reference is not the expected managed reference. Restore the baseline before starting.'
    }
    if ($env.secretRef -ne 'postgres-password') {
        throw 'The quiz service does not use the expected managed credential reference.'
    }
    return [pscustomobject]@{
        appName = $app.name
        keyVaultUrl = [string]$secret.keyVaultUrl
        identity = [string]$secret.identity
        envName = [string]$env.name
        secretRef = [string]$env.secretRef
        revisionMode = [string]$app.properties.configuration.activeRevisionsMode
        latestRevisionName = [string]$app.properties.latestRevisionName
        latestReadyRevisionName = [string]$app.properties.latestReadyRevisionName
    }
}

function Set-CaldovaSecretReference {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][string]$KeyVaultUrl,
        [Parameter(Mandatory)][string]$Identity
    )
    $setting = "postgres-password=keyvaultref:$KeyVaultUrl,identityref:$Identity"
    Invoke-CaldovaAz -Arguments @(
        'containerapp', 'secret', 'set',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $AppName,
        '--secrets', $setting,
        '--output', 'none'
    ) | Out-Null
}

function Restart-CaldovaApiRevision {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][string]$RevisionName
    )
    Invoke-CaldovaAz -Arguments @(
        'containerapp', 'revision', 'restart',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $AppName,
        '--revision', $RevisionName,
        '--output', 'none'
    ) | Out-Null
}

function Get-CaldovaWorker {
    param([Parameter(Mandatory)]$Context)
    return Get-CaldovaTaggedResource -Context $Context -ResourceType 'Microsoft.Compute/virtualMachines' -NamePrefix 'vm-caldova-worker-'
}

function Invoke-CaldovaWorkerCommand {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$Script
    )
    $worker = Get-CaldovaWorker -Context $Context
    return Invoke-CaldovaAz -Arguments @(
        'vm', 'run-command', 'invoke',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $worker.name,
        '--command-id', 'RunShellScript',
        '--scripts', $Script,
        '--output', 'json'
    ) -ReturnJson
}

function Assert-CaldovaReportingReady {
    param([Parameter(Mandatory)]$Context)
    $ready = Assert-CaldovaQuizLaunchReady -Context $Context
    $alert = Invoke-CaldovaAz -Arguments @('monitor', 'scheduled-query', 'show', '--resource-group', $Context.State.resourceGroupName, '--name', $script:ReportingAlert, '--output', 'json') -ReturnJson
    $frequency = if ($alert.evaluationFrequency) { $alert.evaluationFrequency } else { $alert.properties.evaluationFrequency }
    if ($frequency -ne 'PT1M') { throw "Azure Monitor alert '$script:ReportingAlert' must evaluate every minute." }
    $result = Invoke-CaldovaWorkerCommand -Context $Context -Script "set -euo pipefail; mountpoint -q /var/lib/caldova; test -d /var/lib/caldova/exports; test ! -e '$script:ReportingFiller'; echo CALDOVA_REPORTING_READY"
    if (($result.value.message | Out-String) -notmatch 'CALDOVA_REPORTING_READY') {
        throw 'Recent report output is not on the dedicated healthy export volume. Run Reset before starting.'
    }
    return $ready
}

function Wait-CaldovaReportingAlert {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][DateTime]$NotBeforeUtc)
    $workspaceId = (Invoke-CaldovaAz -Arguments @('monitor', 'log-analytics', 'workspace', 'show', '--resource-group', $Context.State.resourceGroupName, '--workspace-name', $Context.State.logAnalyticsWorkspaceName, '--query', 'id', '--output', 'tsv') | Out-String).Trim()
    $deadline = [DateTime]::UtcNow.AddMinutes(8)
    do {
        $target = [Uri]::EscapeDataString($workspaceId)
        $url = "https://management.azure.com/subscriptions/$($Context.State.subscriptionId)/providers/Microsoft.AlertsManagement/alerts?api-version=$script:AlertsApiVersion&targetResource=$target&timeRange=1h"
        $result = Invoke-CaldovaAz -Arguments @('rest', '--method', 'get', '--url', $url, '--output', 'json') -ReturnJson
        $match = @($result.value) | Where-Object {
            $_.properties.essentials.alertRule -match [regex]::Escape($script:ReportingAlert) -and
            $_.properties.essentials.monitorCondition -eq 'Fired' -and
            [DateTime]$_.properties.essentials.startDateTime -ge $NotBeforeUtc
        } | Select-Object -First 1
        if ($match) { return $match }
        Start-Sleep -Seconds 15
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Azure Monitor did not report fresh alert '$script:ReportingAlert' within eight minutes."
}

function Test-CaldovaRecentReporting {
    param([Parameter(Mandatory)]$Context)
    $result = Invoke-CaldovaWorkerCommand -Context $Context -Script "set -euo pipefail; systemctl start caldova-reporting.service; test -n `"`$(find /var/lib/caldova/exports -type f -name 'caldova-grades-*.csv' -mmin -5 -print -quit)`"; journalctl -t caldova-reporting --since '-5 minutes' --no-pager | grep 'category=CaldovaReportingHeartbeat status=ok'; echo CALDOVA_REPORTING_RECOVERED"
    return ($result.value.message | Out-String) -match 'CALDOVA_REPORTING_RECOVERED'
}

function Invoke-CaldovaDataScenarioOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Check', 'Break', 'Verify', 'Fix', 'Reset')][string]$Operation,
        [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
        [Parameter(Mandatory)][ValidateSet('preconfigured', 'configure')][string]$TargetAgent,
        [Parameter(Mandatory)][ValidateSet('quiz-search-slow', 'quiz-intermittent-failures', 'quiz-consistent-failures', 'reporting-output-missing')][string]$ScenarioId,
        [ValidateRange(100, 10000)][int]$ImpactedThresholdMs = 900,
        [ValidateRange(100, 10000)][int]$RecoveredThresholdMs = 600
    )
    $context = Get-CaldovaDataScenarioContext -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent -ScenarioId $ScenarioId
    $snapshotPath = Get-CaldovaScenarioSnapshotPath -Context $context

    if ($Operation -eq 'Check') {
        Write-Host '::phase::readiness::35::Checking learner deployment and selected response plan'
        if ($ScenarioId -eq 'quiz-search-slow') {
            Invoke-CaldovaApiLatencyOperation -Operation Check -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent -ImpactedThresholdMs $ImpactedThresholdMs -RecoveredThresholdMs $RecoveredThresholdMs
            if (-not (Get-CaldovaIndexStatus -Context $context).present) { throw 'Question lookup is not at the healthy baseline. Run Reset before starting.' }
        } elseif ($ScenarioId -eq 'reporting-output-missing') {
            Assert-CaldovaReportingReady -Context $context
        } else {
            Assert-CaldovaQuizLaunchReady -Context $context
            if ((Invoke-CaldovaWebProbe -Uri $context.PublicQuizUri).status -ne 200) { throw 'The learner-visible quiz path is not healthy. Run Reset before starting.' }
        }
        return
    }

    if ($Operation -eq 'Break') {
        if (Test-Path -LiteralPath $snapshotPath) { throw "The selected exercise already has saved state. Use Check recovery or Reset before starting it again." }
        Set-CaldovaSelectedOwnership -Context $context
        Write-Host '::phase::snapshot::30::Saving the exact healthy baseline'
        $notBefore = [DateTime]::UtcNow.AddSeconds(-30)
        if ($ScenarioId -eq 'quiz-search-slow') {
            if (-not (Get-CaldovaIndexStatus -Context $context).present) { throw 'Question lookup is not healthy; no change was made.' }
            Save-CaldovaScenarioSnapshot -Context $context -Snapshot @{ kind = 'question-lookup'; indexName = $script:QuestionBankIndex; present = $true } | Out-Null
            Write-Host '::phase::impact::45::Activating elevated response times'
            Set-CaldovaIndexState -Context $context -Action drop | Out-Null
            $latency = Measure-CaldovaQuizLatency -Context $context
            if ($latency.medianMs -lt $ImpactedThresholdMs) { throw "Learner-visible median response time was $($latency.medianMs) ms; the exercise threshold was not reached." }
            $traffic = Start-CaldovaControlledTraffic -Context $context
            $alert = Wait-CaldovaLatencyAlert -Context $context -NotBeforeUtc $notBefore
            return [pscustomobject]@{ changed = $true; scenarioId = $ScenarioId; latency = $latency; trafficRequests = $traffic; alertId = $alert.id; investigationUrl = $context.SelectedPortalUrl }
        }
        if ($ScenarioId -eq 'quiz-intermittent-failures') {
            $snapshot = Get-CaldovaAppEnvironmentSnapshot -Context $context
            Save-CaldovaScenarioSnapshot -Context $context -Snapshot @{ kind = 'bounded-request-pressure'; app = $snapshot } | Out-Null
            Write-Host '::phase::impact::45::Activating intermittent request failures'
            Set-CaldovaAppVariables -Context $context -Values @('POSTGRES_POOL_MAX=1', 'POSTGRES_CONNECT_TIMEOUT_MS=250', 'CALDOVA_DB_HOLD_MS=1500')
            Wait-CaldovaApiReady -Context $context | Out-Null
            $impact = Measure-CaldovaConcurrentQuizTraffic -Context $context
            if ($impact.failures -lt 1 -or $impact.successes -lt 1) { throw "Controlled traffic did not produce both successes and failures (successes=$($impact.successes), failures=$($impact.failures))." }
            $alert = Wait-CaldovaQuizLaunchAlert -Context $context -NotBeforeUtc $notBefore
            return [pscustomobject]@{ changed = $true; scenarioId = $ScenarioId; impact = $impact; trafficRequests = $impact.requests; alertId = $alert.id; investigationUrl = $context.SelectedPortalUrl }
        }
        if ($ScenarioId -eq 'quiz-consistent-failures') {
            $snapshot = Get-CaldovaPostgresSecretSnapshot -Context $context
            Save-CaldovaScenarioSnapshot -Context $context -Snapshot @{ kind = 'managed-credential-reference'; app = $snapshot } | Out-Null
            Write-Host '::phase::impact::45::Activating consistent request failures'
            $invalidUrl = $snapshot.keyVaultUrl -replace '/[^/]+$', '/00000000000000000000000000000000'
            Set-CaldovaSecretReference -Context $context -AppName $snapshot.appName -KeyVaultUrl $invalidUrl -Identity $snapshot.identity
            Restart-CaldovaApiRevision -Context $context -AppName $snapshot.appName -RevisionName $snapshot.latestReadyRevisionName
            $impact = Wait-CaldovaHttpState -Uri $context.PublicQuizUri -State Impacted
            $traffic = Start-CaldovaFailureTraffic -Context $context
            $alert = Wait-CaldovaQuizLaunchAlert -Context $context -NotBeforeUtc $notBefore
            return [pscustomobject]@{ changed = $true; scenarioId = $ScenarioId; impact = @{ publicStatus = $impact.status }; trafficRequests = $traffic; alertId = $alert.id; investigationUrl = $context.SelectedPortalUrl }
        }
        $worker = Get-CaldovaWorker -Context $context
        Save-CaldovaScenarioSnapshot -Context $context -Snapshot @{ kind = 'report-output'; workerName = $worker.name; fillerPath = $script:ReportingFiller; fillerExisted = $false } | Out-Null
        Write-Host '::phase::impact::45::Interrupting recent report output'
        $fill = "set -euo pipefail; mountpoint -q /var/lib/caldova; test ! -e '$script:ReportingFiller'; available=`$(df --output=avail -k /var/lib/caldova | tail -1); kib=`$((available-256)); test `$kib -gt 1024; fallocate -l `"`${kib}K`" '$script:ReportingFiller'; systemctl start caldova-reporting.service || true; test -f '$script:ReportingFiller'; echo CALDOVA_REPORTING_IMPACTED"
        $result = Invoke-CaldovaWorkerCommand -Context $context -Script $fill
        if (($result.value.message | Out-String) -notmatch 'CALDOVA_REPORTING_IMPACTED') { throw 'The reporting exercise did not reach the expected learner-visible state.' }
        $alert = Wait-CaldovaReportingAlert -Context $context -NotBeforeUtc $notBefore
        return [pscustomobject]@{ changed = $true; scenarioId = $ScenarioId; impact = @{ recentExport = $false; heartbeat = $false }; alertId = $alert.id; investigationUrl = $context.SelectedPortalUrl }
    }

    if ($Operation -in @('Fix', 'Reset')) {
        if (Test-Path -LiteralPath $snapshotPath) {
            $snapshot = Get-CaldovaScenarioSnapshot -Context $context
            Write-Host '::phase::restore::55::Restoring the saved healthy baseline'
            if ($ScenarioId -eq 'quiz-search-slow') {
                Set-CaldovaIndexState -Context $context -Action recreate | Out-Null
            } elseif ($ScenarioId -eq 'quiz-intermittent-failures') {
                Restore-CaldovaAppVariables -Context $context -Snapshot $snapshot.app
                Wait-CaldovaApiReady -Context $context | Out-Null
            } elseif ($ScenarioId -eq 'quiz-consistent-failures') {
                Set-CaldovaSecretReference -Context $context -AppName $snapshot.app.appName -KeyVaultUrl $snapshot.app.keyVaultUrl -Identity $snapshot.app.identity
                Restart-CaldovaApiRevision -Context $context -AppName $snapshot.app.appName -RevisionName $snapshot.app.latestReadyRevisionName
                Wait-CaldovaApiReady -Context $context | Out-Null
            } else {
                Invoke-CaldovaWorkerCommand -Context $context -Script "set -euo pipefail; mountpoint -q /var/lib/caldova; rm -f -- '$script:ReportingFiller'; systemctl start caldova-reporting.service; echo CALDOVA_FILLER_REMOVED" | Out-Null
            }
        } elseif ($ScenarioId -eq 'reporting-output-missing') {
            Invoke-CaldovaWorkerCommand -Context $context -Script "set -euo pipefail; mountpoint -q /var/lib/caldova; rm -f -- '$script:ReportingFiller'" | Out-Null
        } elseif ($ScenarioId -eq 'quiz-search-slow' -and -not (Get-CaldovaIndexStatus -Context $context).present) {
            Set-CaldovaIndexState -Context $context -Action recreate | Out-Null
        }
        Write-Host '::phase::verify::85::Verifying learner-visible recovery'
        $recovery = if ($ScenarioId -eq 'quiz-search-slow') {
            $latency = Measure-CaldovaQuizLatency -Context $context
            if ($latency.medianMs -ge $RecoveredThresholdMs) { throw "Median response time remains $($latency.medianMs) ms." }
            @{ recovered = $true; latency = $latency }
        } elseif ($ScenarioId -eq 'reporting-output-missing') {
            if (-not (Test-CaldovaRecentReporting -Context $context)) { throw 'A recent successful report and heartbeat were not verified.' }
            @{ recovered = $true; recentExport = $true; heartbeat = $true }
        } else {
            $probe = Wait-CaldovaHttpState -Uri $context.PublicQuizUri -State Healthy
            @{ recovered = $true; publicStatus = $probe.status }
        }
        if ($Operation -eq 'Reset') {
            Restore-CaldovaOwnership -Context $context
            Remove-CaldovaScenarioSnapshot -Context $context
            return [pscustomobject](@{ reset = $true } + $recovery)
        }
        return [pscustomobject]$recovery
    }

    Write-Host '::phase::recovery::65::Checking learner-visible recovery'
    if ($ScenarioId -eq 'quiz-search-slow') {
        $latency = Measure-CaldovaQuizLatency -Context $context
        return [pscustomobject]@{ recovered = $latency.medianMs -lt $RecoveredThresholdMs; latency = $latency }
    }
    if ($ScenarioId -eq 'reporting-output-missing') {
        $healthy = Test-CaldovaRecentReporting -Context $context
        return [pscustomobject]@{ recovered = $healthy; recentExport = $healthy; heartbeat = $healthy }
    }
    $probe = Invoke-CaldovaWebProbe -Uri $context.PublicQuizUri
    return [pscustomobject]@{ recovered = $probe.status -eq 200; publicStatus = $probe.status }
}

Export-ModuleMember -Function Invoke-CaldovaDataScenarioOperation
