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
    $context | Add-Member -NotePropertyName BaseUri -NotePropertyValue $context.State.publicEndpoint
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
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            return Invoke-CaldovaAz -Arguments @(
                'containerapp', 'exec',
                '--resource-group', $Context.State.resourceGroupName,
                '--name', $app.name,
                '--command', $Command
            )
        } catch {
            if ($attempt -eq 4 -or $_.Exception.Message -notmatch '429 Too Many Requests') {
                throw
            }
            Start-Sleep -Seconds (10 * $attempt)
        }
    }
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
    $names = @('CALDOVA_QUIZ_MODE', 'POSTGRES_POOL_MAX', 'POSTGRES_CONNECT_TIMEOUT_MS', 'CALDOVA_DB_HOLD_MS', 'CALDOVA_SECRET_REFRESH')
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
                $response = Invoke-WebRequest -Uri "${Uri}?pressure=$Attempt" -TimeoutSec 10 -UseBasicParsing -SkipHttpErrorCheck
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
    $scriptPath = Join-Path ([IO.Path]::GetTempPath()) "caldova-worker-$([guid]::NewGuid().ToString('N')).sh"
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
    $wrapper = "printf '%s' '$payload' | base64 -d | /usr/bin/env bash"
    [IO.File]::WriteAllText($scriptPath, $wrapper, [Text.UTF8Encoding]::new($false))
    try {
        return Invoke-CaldovaAz -Arguments @(
            'vm', 'run-command', 'invoke',
            '--resource-group', $Context.State.resourceGroupName,
            '--name', $worker.name,
            '--command-id', 'RunShellScript',
            '--scripts', "@$scriptPath",
            '--output', 'json'
        ) -ReturnJson
    } finally {
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
    }
}

function Assert-CaldovaReportingReady {
    param([Parameter(Mandatory)]$Context)
    $ready = Assert-CaldovaQuizLaunchReady -Context $Context
    $alert = Invoke-CaldovaAz -Arguments @('monitor', 'scheduled-query', 'show', '--resource-group', $Context.State.resourceGroupName, '--name', $script:ReportingAlert, '--output', 'json') -ReturnJson
    $frequency = if ($alert.evaluationFrequency) { $alert.evaluationFrequency } else { $alert.properties.evaluationFrequency }
    if ($frequency -notin @('PT5M', '0:05:00', '00:05:00')) { throw "Azure Monitor alert '$script:ReportingAlert' must evaluate every five minutes." }
    $result = Invoke-CaldovaWorkerCommand -Context $Context -Script "set -euo pipefail; mountpoint -q /var/lib/caldova; test -d /var/lib/caldova/exports; test ! -e '$script:ReportingFiller'; echo CALDOVA_REPORTING_READY"
    if (($result.value.message | Out-String) -notmatch 'CALDOVA_REPORTING_READY') {
        throw 'Recent report output is not on the dedicated healthy export volume. Run Reset before starting.'
    }
    Reset-CaldovaRecoveredReportingAlertLifecycle -Context $Context | Out-Null
    return $ready
}

function Wait-CaldovaReportingAlert {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][DateTime]$NotBeforeUtc)
    $workspaceId = (Invoke-CaldovaAz -Arguments @('monitor', 'log-analytics', 'workspace', 'show', '--resource-group', $Context.State.resourceGroupName, '--workspace-name', $Context.State.logAnalyticsWorkspaceName, '--query', 'id', '--output', 'tsv') | Out-String).Trim()
    $deadline = [DateTime]::UtcNow.AddMinutes(8)
    do {
        $url = "https://management.azure.com/subscriptions/$($Context.State.subscriptionId)/providers/Microsoft.AlertsManagement/alerts?api-version=$script:AlertsApiVersion"
        $result = $null
        for ($attempt = 1; $attempt -le 4; $attempt++) {
            try {
                $result = Invoke-CaldovaAz -Arguments @('rest', '--method', 'get', '--url', $url, '--output', 'json') -ReturnJson
                break
            } catch {
                if ($attempt -eq 4 -or $_.Exception.Message -notmatch '(?i)(429|Too Many Requests|quota exceeded)') {
                    throw
                }
                Start-Sleep -Seconds (15 * $attempt)
            }
        }
        $match = @($result.value) | Where-Object {
            $essentials = $_.properties.essentials
            $null -ne $essentials -and
            $essentials.PSObject.Properties.Name -contains 'alertRule' -and
            $essentials.PSObject.Properties.Name -contains 'targetResource' -and
            $essentials.PSObject.Properties.Name -contains 'monitorCondition' -and
            $essentials.PSObject.Properties.Name -contains 'startDateTime' -and
            $essentials.alertRule -match [regex]::Escape($script:ReportingAlert) -and
            $essentials.targetResource -eq $workspaceId -and
            $essentials.monitorCondition -eq 'Fired' -and
            [DateTime]$essentials.startDateTime -ge $NotBeforeUtc
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

function Get-CaldovaReportingAlerts {
    param([Parameter(Mandatory)]$Context)

    $workspaceId = (Invoke-CaldovaAz -Arguments @(
        'monitor', 'log-analytics', 'workspace', 'show',
        '--resource-group', $Context.State.resourceGroupName,
        '--workspace-name', $Context.State.logAnalyticsWorkspaceName,
        '--query', 'id',
        '--output', 'tsv'
    ) | Out-String).Trim()
    $url = "/subscriptions/$($Context.State.subscriptionId)/providers/Microsoft.AlertsManagement/alerts"
    $result = $null
    foreach ($attempt in 1..4) {
        try {
            $result = Invoke-CaldovaAz -Arguments @(
                'rest', '--method', 'get', '--url', $url,
                '--url-parameters', "api-version=$script:AlertsApiVersion",
                '--output', 'json'
            ) -ReturnJson
            break
        } catch {
            if ($attempt -eq 4 -or $_.Exception.Message -notmatch '(?i)(429|Too Many Requests|quota exceeded)') { throw }
            Start-Sleep -Seconds (15 * $attempt)
        }
    }

    return @($result.value | Where-Object {
        $essentials = $_.properties.essentials
        $null -ne $essentials -and
        $essentials.PSObject.Properties.Name -contains 'alertRule' -and
        $essentials.PSObject.Properties.Name -contains 'targetResource' -and
        ($essentials.alertRule -split '/')[-1] -eq $script:ReportingAlert -and
        $essentials.targetResource -eq $workspaceId
    } | Sort-Object { [DateTime]$_.properties.essentials.startDateTime } -Descending)
}

function Deploy-CaldovaReportingAlertRule {
    param([Parameter(Mandatory)]$Context)

    $templatePath = Join-Path $PSScriptRoot '..\..\infra\modules\reporting-alert.bicep'
    Assert-CaldovaFile -Path $templatePath -Purpose 'Dedicated reporting alert module'
    $workspaceId = (Invoke-CaldovaAz -Arguments @(
        'monitor', 'log-analytics', 'workspace', 'show',
        '--resource-group', $Context.State.resourceGroupName,
        '--workspace-name', $Context.State.logAnalyticsWorkspaceName,
        '--query', 'id',
        '--output', 'tsv'
    ) | Out-String).Trim()
    $parameterPath = New-CaldovaProtectedParameterFile -Parameters @{
        location = $Context.State.location
        tags = @{}
        logAnalyticsWorkspaceId = $workspaceId
    }
    try {
        Invoke-CaldovaAz -Arguments @(
            'deployment', 'group', 'create',
            '--resource-group', $Context.State.resourceGroupName,
            '--name', "caldova-reporting-alert-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))",
            '--template-file', $templatePath,
            '--parameters', "@$parameterPath",
            '--output', 'none'
        ) | Out-Null
    } finally {
        Remove-CaldovaProtectedParameterFile -Path $parameterPath
    }

    $rule = Invoke-CaldovaAz -Arguments @(
        'monitor', 'scheduled-query', 'show',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $script:ReportingAlert,
        '--output', 'json'
    ) -ReturnJson
    $query = if ($rule.criteria) { $rule.criteria.allOf[0].query } else { $rule.properties.criteria.allOf[0].query }
    if ($query -notmatch 'LastFailure > LastSuccess') {
        throw "Reporting alert '$script:ReportingAlert' was deployed, but the recovered-state query was not applied."
    }
    return $rule
}

function Reset-CaldovaRecoveredReportingAlertLifecycle {
    param(
        [Parameter(Mandatory)]$Context,
        [ValidateRange(1, 30)][int]$RecoveryWindowMinutes = 10
    )

    $rule = Invoke-CaldovaAz -Arguments @(
        'monitor', 'scheduled-query', 'show',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $script:ReportingAlert,
        '--output', 'json'
    ) -ReturnJson
    $ruleCreatedAtUtc = if ($rule.systemData.createdAt) { [DateTime]$rule.systemData.createdAt } else { [DateTime]::MinValue }
    $deadline = [DateTime]::UtcNow.AddMinutes($RecoveryWindowMinutes)
    do {
        $alerts = @(Get-CaldovaReportingAlerts -Context $Context | Where-Object {
            [DateTime]$_.properties.essentials.startDateTime -ge $ruleCreatedAtUtc
        })
        $latest = $alerts | Select-Object -First 1
        if ($null -eq $latest -or $latest.properties.essentials.monitorCondition -eq 'Resolved') {
            return [pscustomobject]@{ recycled = $false; reason = 'resolved-or-no-prior-alert' }
        }
        if ($latest.properties.essentials.alertState -ne 'Closed') {
            throw "Reporting alert '$(($latest.id -split '/')[-1])' is still open; refusing to recycle the alert rule."
        }
        if ([DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Seconds 30
        }
    } while ([DateTime]::UtcNow -lt $deadline)

    if (-not (Test-CaldovaRecentReporting -Context $Context)) {
        throw 'The reporting worker is not verified recovered; refusing to recycle the alert rule.'
    }
    $alerts = @(Get-CaldovaReportingAlerts -Context $Context | Where-Object {
        [DateTime]$_.properties.essentials.startDateTime -ge $ruleCreatedAtUtc
    })
    $open = @($alerts | Where-Object { $_.properties.essentials.alertState -ne 'Closed' })
    $latest = $alerts | Select-Object -First 1
    if ($open.Count -gt 0) {
        throw 'A reporting alert is open; refusing to recycle the alert rule.'
    }
    if ($null -eq $latest -or $latest.properties.essentials.monitorCondition -ne 'Fired') {
        return [pscustomobject]@{ recycled = $false; reason = 'resolved-during-recovery-window' }
    }

    $staleAlertId = ($latest.id -split '/')[-1]
    Invoke-CaldovaAz -Arguments @(
        'monitor', 'scheduled-query', 'delete',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $script:ReportingAlert,
        '--yes',
        '--output', 'none'
    ) | Out-Null
    Deploy-CaldovaReportingAlertRule -Context $Context | Out-Null
    return [pscustomobject]@{
        recycled = $true
        staleAlertId = $staleAlertId
        preservedEvidence = $true
        alertName = $script:ReportingAlert
    }
}

function Get-CaldovaActiveLatencyAlert {
    param([Parameter(Mandatory)]$Context)
    $workspaceId = (Invoke-CaldovaAz -Arguments @(
        'monitor', 'log-analytics', 'workspace', 'show',
        '--resource-group', $Context.State.resourceGroupName,
        '--workspace-name', $Context.State.logAnalyticsWorkspaceName,
        '--query', 'id',
        '--output', 'tsv'
    ) | Out-String).Trim()
    $url = "https://management.azure.com/subscriptions/$($Context.State.subscriptionId)/providers/Microsoft.AlertsManagement/alerts?api-version=$($script:AlertsApiVersion)"
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            $result = Invoke-CaldovaAz -Arguments @('rest', '--method', 'get', '--url', $url, '--output', 'json') -ReturnJson
            break
        } catch {
            if ($attempt -eq 4 -or $_.Exception.Message -notmatch '(?i)(429|Too Many Requests|quota exceeded)') {
                throw
            }
            Start-Sleep -Seconds (15 * $attempt)
        }
    }
    return @($result.value | Where-Object {
        $essentials = $_.properties.essentials
        $null -ne $essentials -and
        $essentials.PSObject.Properties.Name -contains 'alertRule' -and
        $essentials.PSObject.Properties.Name -contains 'targetResource' -and
        $essentials.PSObject.Properties.Name -contains 'monitorCondition' -and
        $essentials.PSObject.Properties.Name -contains 'startDateTime' -and
        $essentials.alertRule -match 'Caldova-quiz-response-time-elevated' -and
        $essentials.targetResource -eq $workspaceId -and
        $essentials.monitorCondition -eq 'Fired'
    } | Sort-Object { [DateTime]$_.properties.essentials.startDateTime } -Descending) | Select-Object -First 1
}

function Send-CaldovaHealthyLatencySamples {
    param([Parameter(Mandatory)]$Context)
    foreach ($sample in 1..10) {
        $response = Invoke-WebRequest -Uri "$($Context.BaseUri)/api/quiz/OPS-201-M1?recoverySample=$([DateTime]::UtcNow.Ticks)-$sample" -TimeoutSec 20 -UseBasicParsing
        if ($response.StatusCode -ne 200) {
            throw "Healthy latency sample returned HTTP $($response.StatusCode); the alert cannot be resolved until quiz requests succeed."
        }
        Start-Sleep -Milliseconds 500
    }
}

function Assert-CaldovaNoActiveLatencyAlert {
    param([Parameter(Mandatory)]$Context)
    $active = Get-CaldovaActiveLatencyAlert -Context $Context
    if ($null -ne $active) {
        $alertId = ($active.id -split '/')[-1]
        throw "Latency alert '$alertId' is still Fired from a prior exercise. Run Reset and wait for Azure Monitor to resolve it before starting a new quiz-search-slow scenario."
    }
}

function Wait-CaldovaLatencyAlertResolution {
    param([Parameter(Mandatory)]$Context)
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    do {
        Send-CaldovaHealthyLatencySamples -Context $Context
        Start-Sleep -Seconds 30
        if ($null -eq (Get-CaldovaActiveLatencyAlert -Context $Context)) {
            return
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    $active = Get-CaldovaActiveLatencyAlert -Context $Context
    $alertId = if ($null -ne $active) { ($active.id -split '/')[-1] } else { 'unknown' }
    throw "Latency alert '$alertId' remained Fired for 10 minutes after healthy response-time samples. Inspect the scheduled-query rule before rerunning the scenario."
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
            Assert-CaldovaNoActiveLatencyAlert -Context $context
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
            $prewarm = Invoke-CaldovaWebProbe -Uri "$($context.PublicQuizUri)?pressurePrewarm=$([DateTime]::UtcNow.Ticks)" -TimeoutSec 15
            if ($prewarm.status -ne 200) { throw "The bounded PostgreSQL pool could not be prewarmed; quiz returned HTTP $($prewarm.status)." }
            $impact = Measure-CaldovaConcurrentQuizTraffic -Context $context
            if ($impact.failures -lt 1 -or $impact.successes -lt 1) { throw "Controlled traffic did not produce both successes and failures (successes=$($impact.successes), failures=$($impact.failures))." }
            $alert = Wait-CaldovaQuizLaunchAlert -Context $context -NotBeforeUtc $notBefore
            return [pscustomobject]@{ changed = $true; scenarioId = $ScenarioId; impact = $impact; trafficRequests = $impact.requests; alertId = $alert.id; investigationUrl = $context.SelectedPortalUrl }
        }
        if ($ScenarioId -eq 'quiz-consistent-failures') {
            $snapshot = Get-CaldovaAppEnvironmentSnapshot -Context $context
            Save-CaldovaScenarioSnapshot -Context $context -Snapshot @{ kind = 'quiz-availability-setting'; app = $snapshot } | Out-Null
            Write-Host '::phase::impact::45::Activating consistent request failures'
            Set-CaldovaAppVariables -Context $context -Values @('CALDOVA_QUIZ_MODE=unavailable')
            Wait-CaldovaApiReady -Context $context | Out-Null
            $impact = Wait-CaldovaHttpState -Uri $context.PublicQuizUri -State Impacted
            $traffic = Start-CaldovaFailureTraffic -Context $context
            $alert = Wait-CaldovaQuizLaunchAlert -Context $context -NotBeforeUtc $notBefore
            return [pscustomobject]@{ changed = $true; scenarioId = $ScenarioId; impact = @{ publicStatus = $impact.status }; trafficRequests = $traffic; alertId = $alert.id; investigationUrl = $context.SelectedPortalUrl }
        }
        $worker = Get-CaldovaWorker -Context $context
        Save-CaldovaScenarioSnapshot -Context $context -Snapshot @{ kind = 'report-output'; workerName = $worker.name; fillerPath = $script:ReportingFiller; fillerExisted = $false } | Out-Null
        Write-Host '::phase::impact::45::Interrupting recent report output'
        $fill = "set -euo pipefail; mountpoint -q /var/lib/caldova; test ! -e '$script:ReportingFiller'; device=`$(findmnt -n -o SOURCE /var/lib/caldova); tune2fs -m 0 `"`$device`"; available=`$(df --output=avail -k /var/lib/caldova | tail -1); kib=`$((available-8)); test `$kib -gt 1024; fallocate -l `"`${kib}K`" '$script:ReportingFiller'; dd if=/dev/zero of='$script:ReportingFiller' bs=64K oflag=append conv=notrunc status=none || true; systemctl start caldova-reporting.service || true; test -f '$script:ReportingFiller'; journalctl -t caldova-reporting --since '-2 minutes' --no-pager | grep 'status=FAILED'; echo CALDOVA_REPORTING_IMPACTED"
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
                Restore-CaldovaAppVariables -Context $context -Snapshot $snapshot.app
                Wait-CaldovaApiReady -Context $context | Out-Null
            } else {
                Invoke-CaldovaWorkerCommand -Context $context -Script "set -euo pipefail; mountpoint -q /var/lib/caldova; rm -f -- '$script:ReportingFiller'; device=`$(findmnt -n -o SOURCE /var/lib/caldova); tune2fs -m 5 `"`$device`"; systemctl start caldova-reporting.service; echo CALDOVA_FILLER_REMOVED" | Out-Null
            }
        } elseif ($ScenarioId -eq 'reporting-output-missing') {
            Invoke-CaldovaWorkerCommand -Context $context -Script "set -euo pipefail; mountpoint -q /var/lib/caldova; rm -f -- '$script:ReportingFiller'; device=`$(findmnt -n -o SOURCE /var/lib/caldova); tune2fs -m 5 `"`$device`"" | Out-Null
        } elseif ($ScenarioId -eq 'quiz-search-slow' -and -not (Get-CaldovaIndexStatus -Context $context).present) {
            Set-CaldovaIndexState -Context $context -Action recreate | Out-Null
        }
        Write-Host '::phase::verify::85::Verifying learner-visible recovery'
        $recovery = if ($ScenarioId -eq 'quiz-search-slow') {
            $latency = Measure-CaldovaQuizLatency -Context $context
            if ($latency.medianMs -ge $RecoveredThresholdMs) { throw "Median response time remains $($latency.medianMs) ms." }
            Wait-CaldovaLatencyAlertResolution -Context $context
            @{ recovered = $true; latency = $latency }
        } elseif ($ScenarioId -eq 'reporting-output-missing') {
            if (-not (Test-CaldovaRecentReporting -Context $context)) { throw 'A recent successful report and heartbeat were not verified.' }
            @{ recovered = $true; recentExport = $true; heartbeat = $true }
        } else {
            $probe = Wait-CaldovaHttpState -Uri $context.PublicQuizUri -State Healthy
            @{ recovered = $true; publicStatus = $probe.status }
        }
        $closedAlerts = Close-CaldovaRecoveredAlerts -Context $context -AlertName $context.AlertName
        $alertLifecycle = if ($ScenarioId -eq 'reporting-output-missing') {
            Reset-CaldovaRecoveredReportingAlertLifecycle -Context $context
        } else {
            $null
        }
        if ($Operation -eq 'Reset') {
            Restore-CaldovaOwnership -Context $context
            Remove-CaldovaScenarioSnapshot -Context $context
            return [pscustomobject](@{ reset = $true; closedAlerts = $closedAlerts; alertLifecycle = $alertLifecycle } + $recovery)
        }
        return [pscustomobject](@{ closedAlerts = $closedAlerts; alertLifecycle = $alertLifecycle } + $recovery)
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
