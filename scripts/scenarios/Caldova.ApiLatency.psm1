Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\Caldova.Lifecycle.psm1') -Force

$script:FilterName = 'caldova-azure-monitor-response'
$script:AlertName = 'Caldova-quiz-response-time-elevated'
$script:AgentApiVersion = '2025-05-01-preview'
$script:AlertsApiVersion = '2019-03-01'

function Get-CaldovaApiLatencyContext {
    param(
        [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
        [Parameter(Mandatory)][ValidateSet('preconfigured', 'configure')][string]$TargetAgent
    )

    $state = Get-CaldovaState -LearnerNumber $LearnerNumber
    if ($state.schemaVersion -lt 2 -or
        [string]::IsNullOrWhiteSpace($state.apiHealthyImage) -or
        [string]::IsNullOrWhiteSpace($state.apiLatencyImage)) {
        throw "Caldova state does not contain both workshop API images. Re-run provision.ps1 with -ApiImage and -ApiLatencyImage before starting the scenario."
    }

    $selectedAgentName = if ($TargetAgent -eq 'preconfigured') { $state.preconfiguredAgentName } else { $state.configuredAgentName }
    $otherAgentName = if ($TargetAgent -eq 'preconfigured') { $state.configuredAgentName } else { $state.preconfiguredAgentName }
    $selectedPortalUrl = if ($TargetAgent -eq 'preconfigured') { $state.preconfiguredAgentPortalUrl } else { $state.configuredAgentPortalUrl }
    $apiName = "ca-caldova-api-$($state.resourceGroupName.Split('-')[-1])"

    return [pscustomobject]@{
        State = $state
        LearnerNumber = $LearnerNumber
        TargetAgent = $TargetAgent
        SelectedAgentName = $selectedAgentName
        OtherAgentName = $otherAgentName
        SelectedPortalUrl = $selectedPortalUrl
        ApiName = $apiName
        BaseUri = $state.publicEndpoint.TrimEnd('/')
    }
}

function Get-CaldovaIncidentFilterResource {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$AgentName,
        [switch]$AllowMissing
    )

    $url = "https://management.azure.com/subscriptions/$($Context.State.subscriptionId)/resourceGroups/$($Context.State.resourceGroupName)/providers/Microsoft.App/agents/$AgentName/incidentFilters/$($script:FilterName)?api-version=$($script:AgentApiVersion)"
    try {
        return Invoke-CaldovaAz -Arguments @('rest', '--method', 'get', '--url', $url, '--output', 'json') -ReturnJson
    } catch {
        if ($AllowMissing -and $_.Exception.Message -match '(?i)(404|not found|could not be found)') {
            return $null
        }
        throw
    }
}

function ConvertFrom-CaldovaIncidentFilter {
    param([Parameter(Mandatory)]$Resource)

    $encoded = $Resource.properties.value
    if ([string]::IsNullOrWhiteSpace($encoded)) {
        throw "Incident filter '$($Resource.name)' has no encoded response-plan value."
    }
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
    return $json | ConvertFrom-Json
}

function Set-CaldovaIncidentFilterEnabled {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$AgentName,
        [Parameter(Mandatory)]$Resource,
        [Parameter(Mandatory)][bool]$Enabled
    )

    $spec = ConvertFrom-CaldovaIncidentFilter -Resource $Resource
    $spec.isEnabled = $Enabled
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($spec | ConvertTo-Json -Depth 20 -Compress)))
    $body = @{ properties = @{ value = $encoded } } | ConvertTo-Json -Depth 5 -Compress
    $url = "https://management.azure.com/subscriptions/$($Context.State.subscriptionId)/resourceGroups/$($Context.State.resourceGroupName)/providers/Microsoft.App/agents/$AgentName/incidentFilters/$($script:FilterName)?api-version=$($script:AgentApiVersion)"
    Invoke-CaldovaAz -Arguments @('rest', '--method', 'put', '--url', $url, '--body', $body, '--output', 'none') | Out-Null
}

function Assert-CaldovaSelectedAgentReady {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][int]$ImpactedThresholdMs
    )

    Invoke-CaldovaAz -Arguments @('account', 'set', '--subscription', $Context.State.subscriptionId) | Out-Null
    $selected = Get-CaldovaIncidentFilterResource -Context $Context -AgentName $Context.SelectedAgentName -AllowMissing
    if ($null -eq $selected) {
        $pathName = if ($Context.TargetAgent -eq 'configure') { 'Configure' } else { 'Preconfigured' }
        throw "$pathName agent '$($Context.SelectedAgentName)' is missing response plan '$($script:FilterName)'. Create and apply that incident filter with srectl, then run Check configuration again. No scenario change was made."
    }

    $spec = ConvertFrom-CaldovaIncidentFilter -Resource $selected
    if ($spec.incidentPlatform -ne 'AzMonitor') {
        throw "Response plan '$($script:FilterName)' on '$($Context.SelectedAgentName)' uses '$($spec.incidentPlatform)' instead of AzMonitor. Update the plan and check again."
    }
    if ($spec.titleContains -notmatch '(?i)Caldova') {
        throw "Response plan '$($script:FilterName)' does not match Caldova alert titles. Set titleContains to 'Caldova' and check again."
    }
    if ([string]::IsNullOrWhiteSpace($spec.handlingAgent)) {
        throw "Response plan '$($script:FilterName)' has no handlingAgent. Select the Caldova incident responder and check again."
    }

    $alert = Invoke-CaldovaAz -Arguments @(
        'monitor', 'scheduled-query', 'show',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $script:AlertName,
        '--output', 'json'
    ) -ReturnJson
    if ($alert.enabled -eq $false -or $alert.properties.enabled -eq $false) {
        throw "Azure Monitor alert '$($script:AlertName)' is disabled. Enable it before starting the scenario."
    }
    $criteria = if ($null -ne $alert.criteria) { $alert.criteria } else { $alert.properties.criteria }
    $configuredThreshold = [int]$criteria.allOf[0].threshold
    if ($configuredThreshold -ne $ImpactedThresholdMs) {
        throw "Azure Monitor alert '$($script:AlertName)' uses threshold $configuredThreshold ms, but the selected scenario requires $ImpactedThresholdMs ms. Redeploy the alert with the catalog threshold before starting."
    }

    return [pscustomobject]@{
        ready = $true
        agentName = $Context.SelectedAgentName
        investigationUrl = $Context.SelectedPortalUrl
        responsePlan = $script:FilterName
        alertName = $script:AlertName
    }
}

function Get-CaldovaOwnershipPath {
    param([Parameter(Mandatory)][int]$LearnerNumber)
    return Join-Path (Split-Path (Get-CaldovaStatePath -LearnerNumber $LearnerNumber) -Parent) "ownership-user$LearnerNumber.json"
}

function Set-CaldovaSelectedOwnership {
    param([Parameter(Mandatory)]$Context)

    $selected = Get-CaldovaIncidentFilterResource -Context $Context -AgentName $Context.SelectedAgentName
    $other = Get-CaldovaIncidentFilterResource -Context $Context -AgentName $Context.OtherAgentName -AllowMissing
    $ownershipPath = Get-CaldovaOwnershipPath -LearnerNumber $Context.LearnerNumber
    if (-not (Test-Path -LiteralPath $ownershipPath)) {
        @{
            schemaVersion = 1
            capturedAtUtc = [DateTime]::UtcNow.ToString('o')
            selectedAgent = $Context.SelectedAgentName
            filters = @(
                @{
                    agentName = $Context.SelectedAgentName
                    exists = $true
                    enabled = [bool](ConvertFrom-CaldovaIncidentFilter -Resource $selected).isEnabled
                },
                @{
                    agentName = $Context.OtherAgentName
                    exists = $null -ne $other
                    enabled = if ($null -ne $other) { [bool](ConvertFrom-CaldovaIncidentFilter -Resource $other).isEnabled } else { $false }
                }
            )
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ownershipPath -Encoding utf8NoBOM
    }

    Set-CaldovaIncidentFilterEnabled -Context $Context -AgentName $Context.SelectedAgentName -Resource $selected -Enabled $true
    if ($null -ne $other) {
        Set-CaldovaIncidentFilterEnabled -Context $Context -AgentName $Context.OtherAgentName -Resource $other -Enabled $false
    }

    $selectedAfter = ConvertFrom-CaldovaIncidentFilter -Resource (Get-CaldovaIncidentFilterResource -Context $Context -AgentName $Context.SelectedAgentName)
    $otherAfterResource = Get-CaldovaIncidentFilterResource -Context $Context -AgentName $Context.OtherAgentName -AllowMissing
    $matchingEnabled = @($selectedAfter, $(if ($null -ne $otherAfterResource) { ConvertFrom-CaldovaIncidentFilter -Resource $otherAfterResource })) |
        Where-Object { $null -ne $_ -and $_.titleContains -match '(?i)Caldova' -and $_.isEnabled }
    if ($matchingEnabled.Count -ne 1) {
        throw "Response-plan ownership validation found $($matchingEnabled.Count) enabled Caldova filters. Reset the scenario before retrying; exactly one selected agent must own the live alert."
    }
}

function Restore-CaldovaBaselineOwnership {
    param([Parameter(Mandatory)]$Context)

    $ownershipPath = Get-CaldovaOwnershipPath -LearnerNumber $Context.LearnerNumber
    if (Test-Path -LiteralPath $ownershipPath) {
        $snapshot = Get-Content -LiteralPath $ownershipPath -Raw | ConvertFrom-Json
        foreach ($entry in $snapshot.filters) {
            if (-not $entry.exists) { continue }
            $resource = Get-CaldovaIncidentFilterResource -Context $Context -AgentName $entry.agentName -AllowMissing
            if ($null -ne $resource) {
                Set-CaldovaIncidentFilterEnabled -Context $Context -AgentName $entry.agentName -Resource $resource -Enabled ([bool]$entry.enabled)
            }
        }
        Remove-Item -LiteralPath $ownershipPath -Force
        return
    }

    # The provisioned baseline is intentionally owned by the preconfigured path.
    $preconfigured = Get-CaldovaIncidentFilterResource -Context $Context -AgentName $Context.State.preconfiguredAgentName -AllowMissing
    $configure = Get-CaldovaIncidentFilterResource -Context $Context -AgentName $Context.State.configuredAgentName -AllowMissing
    if ($null -ne $preconfigured) { Set-CaldovaIncidentFilterEnabled -Context $Context -AgentName $Context.State.preconfiguredAgentName -Resource $preconfigured -Enabled $true }
    if ($null -ne $configure) { Set-CaldovaIncidentFilterEnabled -Context $Context -AgentName $Context.State.configuredAgentName -Resource $configure -Enabled $false }
}

function Set-CaldovaApiImage {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$Image
    )

    $current = (Invoke-CaldovaAz -Arguments @(
        'containerapp', 'show',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $Context.ApiName,
        '--query', 'properties.template.containers[0].image',
        '--output', 'tsv'
    ) | Out-String).Trim()
    if ($current -ne $Image) {
        Invoke-CaldovaAz -Arguments @(
            'containerapp', 'update',
            '--resource-group', $Context.State.resourceGroupName,
            '--name', $Context.ApiName,
            '--image', $Image,
            '--output', 'none'
        ) | Out-Null
    }

    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    do {
        $app = Invoke-CaldovaAz -Arguments @(
            'containerapp', 'show',
            '--resource-group', $Context.State.resourceGroupName,
            '--name', $Context.ApiName,
            '--output', 'json'
        ) -ReturnJson
        $ready = $app.properties.latestReadyRevisionName
        $active = $app.properties.latestRevisionName
        $activeImage = $app.properties.template.containers[0].image
        if ($ready -eq $active -and $activeImage -eq $Image) { return }
        Start-Sleep -Seconds 10
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Container App '$($Context.ApiName)' did not reach a ready revision for image '$Image' within 5 minutes. Inspect revision health before retrying."
}

function Measure-CaldovaQuizLatency {
    param(
        [Parameter(Mandatory)]$Context,
        [int]$Samples = 5
    )

    $values = [System.Collections.Generic.List[long]]::new()
    foreach ($sample in 1..$Samples) {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        try {
            $response = Invoke-WebRequest -Uri "$($Context.BaseUri)/api/quiz/OPS-201-M1?sample=$sample" -TimeoutSec 20 -UseBasicParsing
        } finally {
            $watch.Stop()
        }
        if ($response.StatusCode -ne 200) {
            throw "Learner-visible quiz request returned HTTP $($response.StatusCode), so latency recovery cannot be verified."
        }
        $values.Add($watch.ElapsedMilliseconds)
    }
    $ordered = @($values | Sort-Object)
    return [pscustomobject]@{
        samples = $Samples
        minimumMs = $ordered[0]
        medianMs = $ordered[[Math]::Floor($ordered.Count / 2)]
        maximumMs = $ordered[-1]
    }
}

function Start-CaldovaControlledTraffic {
    param([Parameter(Mandatory)]$Context)

    $deadline = [DateTime]::UtcNow.AddSeconds(75)
    $requests = 0
    do {
        $response = Invoke-WebRequest -Uri "$($Context.BaseUri)/api/quiz/OPS-201-M1?traffic=$requests" -TimeoutSec 20 -UseBasicParsing
        if ($response.StatusCode -ne 200) {
            throw "Controlled learner traffic returned HTTP $($response.StatusCode). The latency alert requires successful slow requests; inspect the active revision."
        }
        $requests++
    } while ([DateTime]::UtcNow -lt $deadline)
    return $requests
}

function Wait-CaldovaLatencyAlert {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][DateTime]$NotBeforeUtc
    )

    $workspaceId = (Invoke-CaldovaAz -Arguments @(
        'monitor', 'log-analytics', 'workspace', 'show',
        '--resource-group', $Context.State.resourceGroupName,
        '--workspace-name', $Context.State.logAnalyticsWorkspaceName,
        '--query', 'id',
        '--output', 'tsv'
    ) | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($workspaceId)) {
        throw "Log Analytics workspace '$($Context.State.logAnalyticsWorkspaceName)' could not be resolved for alert polling."
    }

    $deadline = [DateTime]::UtcNow.AddMinutes(8)
    do {
        $target = [Uri]::EscapeDataString($workspaceId)
        $url = "https://management.azure.com/subscriptions/$($Context.State.subscriptionId)/providers/Microsoft.AlertsManagement/alerts?api-version=$($script:AlertsApiVersion)&targetResource=$target&timeRange=1h"
        $result = Invoke-CaldovaAz -Arguments @('rest', '--method', 'get', '--url', $url, '--output', 'json') -ReturnJson
        $match = @($result.value) | Where-Object {
            $_.properties.essentials.alertRule -match [regex]::Escape($script:AlertName) -and
            $_.properties.essentials.monitorCondition -eq 'Fired' -and
            [DateTime]$_.properties.essentials.startDateTime -ge $NotBeforeUtc
        } | Select-Object -First 1
        if ($null -ne $match) { return $match }
        Start-Sleep -Seconds 15
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Azure Monitor did not report fired alert '$($script:AlertName)' within 8 minutes. Confirm AppRequests ingestion, the one-minute rule, and controlled traffic before retrying. The scenario remains active; use Reset after investigation."
}

function Invoke-CaldovaApiLatencyOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Check', 'Break', 'Verify', 'Fix', 'Reset')][string]$Operation,
        [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
        [Parameter(Mandatory)][ValidateSet('preconfigured', 'configure')][string]$TargetAgent,
        [Parameter(Mandatory)][ValidateRange(100, 10000)][int]$ImpactedThresholdMs,
        [Parameter(Mandatory)][ValidateRange(100, 10000)][int]$RecoveredThresholdMs
    )

    $context = Get-CaldovaApiLatencyContext -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent
    switch ($Operation) {
        'Check' {
            Write-Host '::phase::readiness::35::Checking learner deployment and selected response plan'
            Assert-CaldovaSelectedAgentReady -Context $context -ImpactedThresholdMs $ImpactedThresholdMs
        }
        'Break' {
            Write-Host '::phase::readiness::12::Rechecking the selected agent and response plan'
            Assert-CaldovaSelectedAgentReady -Context $context -ImpactedThresholdMs $ImpactedThresholdMs | Out-Null
            Write-Host '::phase::ownership::24::Assigning the live alert to the selected agent'
            Set-CaldovaSelectedOwnership -Context $context
            Write-Host '::phase::impact::42::Activating elevated response times'
            Set-CaldovaApiImage -Context $context -Image $context.State.apiLatencyImage
            Write-Host '::phase::verify-impact::58::Verifying learner-visible impact'
            $latency = Measure-CaldovaQuizLatency -Context $context
            if ($latency.medianMs -lt $ImpactedThresholdMs) {
                throw "Latency image is active but learner-visible median response time was only $($latency.medianMs) ms. Confirm the published bad image was built from src/api/Dockerfile.latency."
            }
            Write-Host '::phase::traffic::72::Generating controlled learner traffic'
            $alertNotBeforeUtc = [DateTime]::UtcNow.AddMinutes(-1)
            $trafficCount = Start-CaldovaControlledTraffic -Context $context
            Write-Host '::phase::alert::88::Waiting for the one-minute Azure Monitor rule'
            $alert = Wait-CaldovaLatencyAlert -Context $context -NotBeforeUtc $alertNotBeforeUtc
            [pscustomobject]@{
                changed = $true
                phase = 'investigate'
                latency = $latency
                trafficRequests = $trafficCount
                alertId = $alert.id
                investigationUrl = $context.SelectedPortalUrl
            }
        }
        'Verify' {
            Write-Host '::phase::measure::65::Measuring current learner-visible response time'
            $latency = Measure-CaldovaQuizLatency -Context $context
            [pscustomobject]@{
                recovered = $latency.medianMs -lt $RecoveredThresholdMs
                latency = $latency
            }
        }
        'Fix' {
            Write-Host '::phase::restore::55::Restoring normal response time'
            Set-CaldovaApiImage -Context $context -Image $context.State.apiHealthyImage
            Write-Host '::phase::verify::85::Verifying normal learner-visible response time'
            $latency = Measure-CaldovaQuizLatency -Context $context
            if ($latency.medianMs -ge $RecoveredThresholdMs) {
                throw "Healthy image is ready, but learner-visible median response time is still $($latency.medianMs) ms. Continue the investigation before marking recovery."
            }
            [pscustomobject]@{ recovered = $true; latency = $latency }
        }
        'Reset' {
            Write-Host '::phase::baseline::45::Restoring the healthy API baseline'
            Set-CaldovaApiImage -Context $context -Image $context.State.apiHealthyImage
            $latency = Measure-CaldovaQuizLatency -Context $context
            if ($latency.medianMs -ge $RecoveredThresholdMs) {
                throw "Reset pinned the healthy image, but median response time remains $($latency.medianMs) ms. Baseline was not restored."
            }
            Write-Host '::phase::ownership::78::Restoring baseline response-plan ownership'
            Restore-CaldovaBaselineOwnership -Context $context
            [pscustomobject]@{ reset = $true; latency = $latency }
        }
    }
}

Export-ModuleMember -Function @(
    'Invoke-CaldovaApiLatencyOperation',
    'Measure-CaldovaQuizLatency',
    'Start-CaldovaControlledTraffic',
    'Wait-CaldovaLatencyAlert'
)
