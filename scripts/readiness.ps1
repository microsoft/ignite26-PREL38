[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Caldova.Lifecycle.psm1') -Force

$state = Get-CaldovaState -LearnerNumber $LearnerNumber
Invoke-CaldovaAz -Arguments @('account', 'set', '--subscription', $state.subscriptionId) | Out-Null

$failures = [System.Collections.Generic.List[string]]::new()

try {
    Invoke-CaldovaAz -Arguments @('group', 'show', '--name', $state.resourceGroupName, '--output', 'none') | Out-Null
} catch {
    $failures.Add("Resource group '$($state.resourceGroupName)' is unavailable.")
}

foreach ($agentName in @($state.preconfiguredAgentName, $state.configuredAgentName)) {
    try {
        $agent = Invoke-CaldovaAz -Arguments @(
            'resource', 'show',
            '--resource-group', $state.resourceGroupName,
            '--resource-type', 'Microsoft.App/agents',
            '--name', $agentName,
            '--api-version', '2025-05-01-preview',
            '--output', 'json'
        ) -ReturnJson
        if ($agent.properties.incidentManagementConfiguration.type -ne 'AzMonitor') {
            $failures.Add("SRE Agent '$agentName' is not configured for Azure Monitor.")
        }
    } catch {
        $failures.Add("SRE Agent '$agentName' is unavailable.")
    }
}

try {
    Invoke-CaldovaAz -Arguments @(
        'monitor', 'scheduled-query', 'list',
        '--resource-group', $state.resourceGroupName,
        '--query', "length([?starts_with(name, 'Caldova-')])",
        '--output', 'tsv'
    ) | Out-Null
    $latencyAlert = Invoke-CaldovaAz -Arguments @(
        'monitor', 'scheduled-query', 'show',
        '--resource-group', $state.resourceGroupName,
        '--name', 'Caldova-quiz-response-time-elevated',
        '--output', 'json'
    ) -ReturnJson
    if ($latencyAlert.evaluationFrequency -notin @('PT5M', '0:05:00') -and $latencyAlert.properties.evaluationFrequency -notin @('PT5M', '0:05:00')) {
        $failures.Add("Quiz response-time alert is not configured for supported five-minute evaluation.")
    }
    $reportingAlert = Invoke-CaldovaAz -Arguments @(
        'monitor', 'scheduled-query', 'show',
        '--resource-group', $state.resourceGroupName,
        '--name', 'Caldova-reporting-output-missing',
        '--output', 'json'
    ) -ReturnJson
    if ($reportingAlert.evaluationFrequency -notin @('PT5M', '0:05:00') -and $reportingAlert.properties.evaluationFrequency -notin @('PT5M', '0:05:00')) {
        $failures.Add("Reporting output alert is not configured for supported five-minute evaluation.")
    }
    $quizLaunchAlert = Invoke-CaldovaAz -Arguments @(
        'monitor', 'scheduled-query', 'show',
        '--resource-group', $state.resourceGroupName,
        '--name', 'Caldova-quiz-launch-failing',
        '--output', 'json'
    ) -ReturnJson
    if ($quizLaunchAlert.evaluationFrequency -notin @('PT5M', '0:05:00') -and $quizLaunchAlert.properties.evaluationFrequency -notin @('PT5M', '0:05:00')) {
        $failures.Add("Quiz launch alert is not configured for supported five-minute evaluation.")
    }
} catch {
    $failures.Add('Caldova Azure Monitor scheduled-query rules could not be read.')
}

try {
    Assert-CaldovaCommand -Name 'azmcp'
    $taskOutput = & azmcp sreagent scheduledtasks list `
        --agent $state.preconfiguredAgentName `
        --subscription $state.subscriptionId `
        --resource-group $state.resourceGroupName
    if ($LASTEXITCODE -ne 0) {
        throw "azmcp scheduled-task list exited with code $LASTEXITCODE."
    }
    $taskPayload = $taskOutput | ConvertFrom-Json
    $tasks = @($taskPayload.results.tasks ?? $taskPayload.results ?? $taskPayload.tasks)
    $expectedTasks = @(
        'Caldova weekly NSG review',
        'Caldova weekly RBAC review',
        'Caldova weekly cost review',
        'Caldova weekly capacity review',
        'Caldova weekly CVE review'
    )
    $configuredTaskNames = @($tasks | ForEach-Object { $_.name })
    foreach ($taskName in $expectedTasks) {
        if ($taskName -notin $configuredTaskNames) {
            $failures.Add("Preconfigured Agent is missing weekly task '$taskName'.")
        }
    }
    if ($tasks.Count -ne 5) {
        $failures.Add("Preconfigured Agent must have exactly five scheduled tasks; found $($tasks.Count).")
    }

    $configureTaskOutput = & azmcp sreagent scheduledtasks list `
        --agent $state.configuredAgentName `
        --subscription $state.subscriptionId `
        --resource-group $state.resourceGroupName
    if ($LASTEXITCODE -ne 0) {
        throw "azmcp Configure Agent scheduled-task list exited with code $LASTEXITCODE."
    }
    $configureTaskPayload = $configureTaskOutput | ConvertFrom-Json
    $configureTasks = @($configureTaskPayload.results.tasks ?? $configureTaskPayload.results ?? $configureTaskPayload.tasks)
    if ($configureTasks.Count -ne 0) {
        $failures.Add("Configure Agent must start without scheduled tasks; found $($configureTasks.Count).")
    }
} catch {
    $failures.Add("SRE Agent scheduled-task verification failed: $($_.Exception.Message)")
}

try {
    $token = (Invoke-CaldovaAz -Arguments @(
        'account', 'get-access-token',
        '--resource', 'https://azuresre.dev',
        '--query', 'accessToken',
        '--output', 'tsv'
    ) | Out-String).Trim()
    $headers = @{ Authorization = (@('Bearer', $token) -join ' ') }
    $preconfiguredEndpoint = (Invoke-CaldovaAz -Arguments @(
        'resource', 'show',
        '--resource-group', $state.resourceGroupName,
        '--resource-type', 'Microsoft.App/agents',
        '--name', $state.preconfiguredAgentName,
        '--api-version', '2025-05-01-preview',
        '--query', 'properties.agentEndpoint',
        '--output', 'tsv'
    ) | Out-String).TrimEnd()
    $configureEndpoint = (Invoke-CaldovaAz -Arguments @(
        'resource', 'show',
        '--resource-group', $state.resourceGroupName,
        '--resource-type', 'Microsoft.App/agents',
        '--name', $state.configuredAgentName,
        '--api-version', '2025-05-01-preview',
        '--query', 'properties.agentEndpoint',
        '--output', 'tsv'
    ) | Out-String).TrimEnd()

    $domains = Invoke-RestMethod -Uri "$preconfiguredEndpoint/api/v2/github/domains" -Headers $headers -Method Get
    $repositories = Invoke-RestMethod -Uri "$preconfiguredEndpoint/api/v2/repos" -Headers $headers -Method Get
    $domainValues = @($domains.values ?? $domains.value ?? $domains)
    $repositoryValues = @($repositories.value ?? $repositories.values ?? $repositories)
    if (-not ($domainValues | Where-Object { $_.name -in @('github.com', 'github_com') -or $_.domain -eq 'github.com' })) {
        $failures.Add('Preconfigured Agent does not have a verified github.com domain.')
    }
    if ($repositoryValues.Count -eq 0) {
        $failures.Add('Preconfigured Agent does not have an isolated source repository.')
    } else {
        $repositoryName = $repositoryValues[0].name
        $repositoryTest = Invoke-RestMethod -Uri "$preconfiguredEndpoint/api/v2/repos/$([Uri]::EscapeDataString($repositoryName))/test" -Headers $headers -Method Post
        $isSuccessful = if ($repositoryTest.PSObject.Properties.Name -contains 'isSuccessful') { $repositoryTest.isSuccessful } else { $repositoryTest.success }
        if ($isSuccessful -eq $false) {
            $testDetail = if ($repositoryTest.PSObject.Properties.Name -contains 'errorMessage') { $repositoryTest.errorMessage } else { $repositoryTest.message }
            $failures.Add("Preconfigured Agent repository test failed: $testDetail")
        }
    }

    $configureDomains = Invoke-RestMethod -Uri "$configureEndpoint/api/v2/github/domains" -Headers $headers -Method Get
    $configureRepositories = Invoke-RestMethod -Uri "$configureEndpoint/api/v2/repos" -Headers $headers -Method Get
    if (@($configureDomains.values ?? $configureDomains.value ?? $configureDomains).Count -ne 0 -or
        @($configureRepositories.value ?? $configureRepositories.values ?? $configureRepositories).Count -ne 0) {
        $failures.Add('Configure Agent must remain disconnected from GitHub until learner OAuth.')
    }
} catch {
    $failures.Add("SRE Agent GitHub verification failed: $($_.Exception.Message)")
}

try {
    $baseUri = $state.publicEndpoint.TrimEnd('/')
    foreach ($path in @('/health', '/ready', '/api/summary', '/api/courses', '/api/quiz/OPS-201-M1')) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri "$baseUri$path" -Method Get -TimeoutSec 30 -UseBasicParsing
        $stopwatch.Stop()
        if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
            $failures.Add("Public endpoint '$path' returned HTTP $($response.StatusCode).")
        } else {
            Write-Host ("Verified HTTP {0} {1} ms={2}" -f $response.StatusCode, $path, $stopwatch.ElapsedMilliseconds)
        }
    }
} catch {
    $failures.Add("Public Application Gateway path failed: $($_.Exception.Message)")
}

try {
    $apiName = Invoke-CaldovaAz -Arguments @(
        'containerapp', 'list',
        '--resource-group', $state.resourceGroupName,
        '--query', "[?starts_with(name, 'ca-caldova-api-')].name | [0]",
        '--output', 'tsv'
    )
    $apiName = ($apiName | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($apiName)) {
        $failures.Add('Caldova API container app could not be resolved for database verification.')
    } else {
        $activeImage = (Invoke-CaldovaAz -Arguments @(
            'containerapp', 'show',
            '--resource-group', $state.resourceGroupName,
            '--name', $apiName,
            '--query', 'properties.template.containers[0].image',
            '--output', 'tsv'
        ) | Out-String).Trim()
        if ($state.schemaVersion -ge 2 -and $activeImage -ne $state.apiHealthyImage) {
            $failures.Add("Caldova API is not pinned to the healthy workshop image. Run scripts/reset.ps1 -LearnerNumber $LearnerNumber -Scenario api-latency.")
        }
        $databaseCheck = Invoke-CaldovaAz -Arguments @(
            'containerapp', 'exec',
            '--resource-group', $state.resourceGroupName,
            '--name', $apiName,
            '--command', 'node /app/scripts/db-check.js'
        )
        if (($databaseCheck | Out-String) -notmatch '"status"\s*:\s*"ok"') {
            $failures.Add("Private PostgreSQL verification did not return an ok status. Output: $(($databaseCheck | Out-String).Trim())")
        }
        $indexCheck = Invoke-CaldovaAz -Arguments @(
            'containerapp', 'exec',
            '--resource-group', $state.resourceGroupName,
            '--name', $apiName,
            '--command', 'node /app/scripts/question-bank-index.js status'
        )
        if (($indexCheck | Out-String) -notmatch '"index"\s*:\s*"idx_question_bank_assessment_active".*"present"\s*:\s*true') {
            $failures.Add('The question-bank lookup is not at the healthy baseline.')
        }
    }
} catch {
    $failures.Add("Private PostgreSQL verification through the API container failed: $($_.Exception.Message)")
}

try {
    $volumeCheck = Invoke-CaldovaAz -Arguments @(
        'vm', 'run-command', 'invoke',
        '--resource-group', $state.resourceGroupName,
        '--name', $state.reportingWorkerName,
        '--command-id', 'RunShellScript',
        '--scripts', 'set -eu; mountpoint -q /var/lib/caldova; test -d /var/lib/caldova/exports; test ! -e /var/lib/caldova/.caldova-reporting-output-missing.filler; echo CALDOVA_EXPORT_VOLUME_OK',
        '--query', 'value[0].message',
        '--output', 'tsv'
    )
    if (($volumeCheck | Out-String) -notmatch 'CALDOVA_EXPORT_VOLUME_OK') {
        $failures.Add('The dedicated reporting export volume is not mounted at the healthy baseline.')
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
    $heartbeat = Invoke-CaldovaAz -Arguments @(
        'monitor', 'log-analytics', 'query',
        '--workspace', $workspaceCustomerId,
        '--analytics-query', $heartbeatQuery,
        '--output', 'json'
    ) -ReturnJson
    if (@($heartbeat).Count -eq 0) {
        $failures.Add("No successful Caldova reporting heartbeat was found in the last 15 minutes for '$($state.reportingWorkerName)'.")
    } else {
        Write-Host "Verified recent Caldova reporting heartbeat."
    }
} catch {
    try {
        $heartbeatFallback = Invoke-CaldovaAz -Arguments @(
            'vm', 'run-command', 'invoke',
            '--resource-group', $state.resourceGroupName,
            '--name', $state.reportingWorkerName,
            '--command-id', 'RunShellScript',
            '--scripts', "journalctl -u caldova-reporting.service --since '15 minutes ago' --no-pager | grep 'category=CaldovaReportingHeartbeat status=ok' | tail -n 1",
            '--query', 'value[0].message',
            '--output', 'tsv'
        )
        if (($heartbeatFallback | Out-String) -notmatch 'category=CaldovaReportingHeartbeat status=ok') {
            throw 'The reporting worker journal does not contain a recent successful heartbeat.'
        }
        Write-Warning "Log Analytics data-plane access is unavailable to the current operator; verified the recent heartbeat from the reporting worker journal instead."
    } catch {
        $failures.Add("Caldova reporting heartbeat verification failed: $($_.Exception.Message)")
    }
}

if ($failures.Count -gt 0) {
    $detail = ($failures | ForEach-Object { "- $_" }) -join [Environment]::NewLine
    throw "Caldova is not ready for user${LearnerNumber}:`n$detail"
}

Write-Host "Caldova is ready for user$LearnerNumber."
Write-Host "Preconfigured agent: $($state.preconfiguredAgentPortalUrl)"
Write-Host "Configure-path agent: $($state.configuredAgentPortalUrl)"
