Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\Caldova.Lifecycle.psm1')
Import-Module (Join-Path $PSScriptRoot 'Caldova.QuizLaunch.psm1') -Force

$script:ScenarioId = 'course-recommendations-unavailable'
$script:SettingName = 'CALDOVA_RECOMMENDATIONS_MODE'
$script:AvailableValue = 'available'
$script:UnavailableValue = 'unavailable'
$script:AlertName = 'Course-recommendations-unavailable'
$script:AlertsApiVersion = '2019-03-01'

function Get-CaldovaRecommendationsContext {
    param(
        [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
        [Parameter(Mandatory)][ValidateSet('preconfigured', 'configure')][string]$TargetAgent
    )

    $state = Get-CaldovaState -LearnerNumber $LearnerNumber
    if ($state.schemaVersion -lt 2) {
        throw 'Caldova state is older than the guided-scenario contract. Re-run provision.ps1 before continuing.'
    }
    return [pscustomobject]@{
        State = $state
        LearnerNumber = $LearnerNumber
        TargetAgent = $TargetAgent
        ScenarioId = $script:ScenarioId
        SelectedAgentName = if ($TargetAgent -eq 'preconfigured') { $state.preconfiguredAgentName } else { $state.configuredAgentName }
        SelectedPortalUrl = if ($TargetAgent -eq 'preconfigured') { $state.preconfiguredAgentPortalUrl } else { $state.configuredAgentPortalUrl }
        BaseUri = $state.publicEndpoint.TrimEnd('/')
        FeatureUri = "$($state.publicEndpoint.TrimEnd('/'))/api/recommendations/health"
    }
}

function Get-CaldovaRecommendationsSetting {
    param([Parameter(Mandatory)]$Context)

    $app = Get-CaldovaApiApp -Context $Context
    $entry = @($app.properties.template.containers[0].env) |
        Where-Object { $_.name -eq $script:SettingName } |
        Select-Object -First 1
    return [pscustomobject]@{
        appName = $app.name
        revisionMode = [string]$app.properties.configuration.activeRevisionsMode
        latestRevisionName = [string]$app.properties.latestRevisionName
        latestReadyRevisionName = [string]$app.properties.latestReadyRevisionName
        present = $null -ne $entry
        value = if ($null -eq $entry) { $null } else { [string]$entry.value }
    }
}

function Wait-CaldovaRecommendationsRevision {
    param(
        [Parameter(Mandatory)]$Context,
        [ValidateRange(30, 600)][int]$TimeoutSeconds = 300
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $setting = Get-CaldovaRecommendationsSetting -Context $Context
        if (-not [string]::IsNullOrWhiteSpace($setting.latestRevisionName) -and
            $setting.latestRevisionName -eq $setting.latestReadyRevisionName) {
            return $setting
        }
        Start-Sleep -Seconds 10
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'The Caldova API revision did not become ready within five minutes. Inspect the Container App revision before retrying.'
}

function Set-CaldovaRecommendationsMode {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][ValidateSet('available', 'unavailable')][string]$Mode
    )

    $current = Get-CaldovaRecommendationsSetting -Context $Context
    if ($current.value -eq $Mode) {
        return [pscustomobject]@{ changed = $false; setting = $current }
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-CaldovaAz -Arguments @(
                'containerapp', 'update',
                '--resource-group', $Context.State.resourceGroupName,
                '--name', $current.appName,
                '--set-env-vars', "$script:SettingName=$Mode",
                '--output', 'none'
            ) | Out-Null
            break
        } catch {
            if ($attempt -eq 3 -or $_.Exception.Message -notmatch '(?i)(429|Too Many Requests|temporar|timeout)') { throw }
            Start-Sleep -Seconds (10 * $attempt)
        }
    }
    $updated = Wait-CaldovaRecommendationsRevision -Context $Context
    if ($updated.value -ne $Mode) {
        throw "The course recommendations configuration did not reach the requested '$Mode' state."
    }
    return [pscustomobject]@{ changed = $true; setting = $updated }
}

function Get-CaldovaRecommendationsProbe {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$EvidenceMarker
    )

    $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
    $target = if ([string]::IsNullOrWhiteSpace($EvidenceMarker)) { $Uri } else { "$Uri${separator}guidedEvidence=$([Uri]::EscapeDataString($EvidenceMarker))" }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WebRequest -Uri $target -TimeoutSec 20 -UseBasicParsing -SkipHttpErrorCheck
        $body = $null
        try { $body = $response.Content | ConvertFrom-Json } catch { }
        return [pscustomobject]@{
            uri = $target
            status = [int]$response.StatusCode
            elapsedMs = $watch.ElapsedMilliseconds
            featureStatus = if ($null -eq $body) { 'unknown' } else { [string]$body.status }
            feature = if ($null -eq $body) { $null } else { [string]$body.feature }
            message = if ($null -eq $body) { $null } else { [string]$body.message }
        }
    } catch {
        return [pscustomobject]@{ uri = $target; status = 0; elapsedMs = $watch.ElapsedMilliseconds; featureStatus = 'unknown'; error = $_.Exception.Message }
    } finally {
        $watch.Stop()
    }
}

function Assert-CaldovaRecommendationsCoreHealthy {
    param([Parameter(Mandatory)]$Context)

    $paths = @('/health', '/ready', '/api/courses', '/api/quiz/OPS-201-M1', '/api/exports/recent')
    $results = foreach ($path in $paths) {
        $probe = Invoke-CaldovaWebProbe -Uri "$($Context.BaseUri)$path"
        if ($probe.status -ne 200) {
            throw "Core Caldova path '$path' returned HTTP $($probe.status). The guided feature must remain isolated; restore the core workload before continuing."
        }
        $probe
    }

    $gateway = Get-CaldovaTaggedResource -Context $Context -ResourceType 'Microsoft.Network/applicationGateways' -NamePrefix 'agw-caldova-'
    $backend = Invoke-CaldovaAz -Arguments @(
        'network', 'application-gateway', 'show-backend-health',
        '--ids', $gateway.id,
        '--output', 'json'
    ) -ReturnJson
    $states = @($backend.backendAddressPools.backendHttpSettingsCollection.servers.health)
    if ($states.Count -eq 0 -or @($states | Where-Object { $_ -ne 'Healthy' }).Count -gt 0) {
        throw "Application Gateway backend health is not uniformly Healthy: $($states -join ', ')."
    }
    return [pscustomobject]@{ paths = $results; gatewayBackend = 'Healthy' }
}

function Wait-CaldovaRecommendationsState {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][ValidateSet('available', 'degraded')][string]$State,
        [ValidateRange(30, 300)][int]$TimeoutSeconds = 180
    )

    $expectedStatus = if ($State -eq 'available') { 200 } else { 503 }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $probe = Get-CaldovaRecommendationsProbe -Uri $Context.FeatureUri -EvidenceMarker "state-$State-$([DateTime]::UtcNow.Ticks)"
        if ($probe.status -eq $expectedStatus -and $probe.featureStatus -eq $State) { return $probe }
        Start-Sleep -Seconds 5
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Course recommendations did not become '$State' within $TimeoutSeconds seconds. Last HTTP status was $($probe.status) with feature state '$($probe.featureStatus)'."
}

function Send-CaldovaRecommendationsTraffic {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][ValidateSet('available', 'degraded')][string]$ExpectedState,
        [ValidateRange(1, 30)][int]$Requests = 12
    )

    $marker = "course-recommendations-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"
    $expectedStatus = if ($ExpectedState -eq 'available') { 200 } else { 503 }
    $results = foreach ($attempt in 1..$Requests) {
        Get-CaldovaRecommendationsProbe -Uri $Context.FeatureUri -EvidenceMarker "$marker-$attempt"
    }
    $unexpected = @($results | Where-Object { $_.status -ne $expectedStatus -or $_.featureStatus -ne $ExpectedState })
    if ($unexpected.Count -gt 0) {
        throw "Deterministic course recommendations traffic returned $($unexpected.Count) unexpected result(s); expected HTTP $expectedStatus and state '$ExpectedState'."
    }
    return [pscustomobject]@{
        marker = $marker
        requests = $Requests
        status = $expectedStatus
        featureStatus = $ExpectedState
        startedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function Test-CaldovaRecommendationsAlertConfigured {
    param([Parameter(Mandatory)]$Context)

    $alerts = @(Invoke-CaldovaAz -Arguments @(
        'monitor', 'scheduled-query', 'list',
        '--resource-group', $Context.State.resourceGroupName,
        '--output', 'json'
    ) -ReturnJson)
    $alert = @($alerts | Where-Object { $_.name -eq $script:AlertName } | Select-Object -First 1)
    if ($alert.Count -eq 0) { return $false }
    $enabled = if ($alert[0].PSObject.Properties.Name -contains 'enabled') {
        $alert[0].enabled
    } else {
        $alert[0].properties.enabled
    }
    return [System.Convert]::ToBoolean($enabled)
}

function Wait-CaldovaRecommendationsAlert {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][DateTime]$NotBeforeUtc
    )

    $resourceGroupSegment = "/resourceGroups/$($Context.State.resourceGroupName)/"
    $deadline = [DateTime]::UtcNow.AddMinutes(20)
    do {
        $url = "/subscriptions/$($Context.State.subscriptionId)/providers/Microsoft.AlertsManagement/alerts"
        $result = $null
        for ($attempt = 1; $attempt -le 4; $attempt++) {
            try {
                $result = Invoke-CaldovaAz -Arguments @(
                    'rest', '--method', 'get', '--url', $url,
                    '--url-parameters', "api-version=$script:AlertsApiVersion",
                    '--output', 'json'
                ) -ReturnJson
                break
            } catch {
                if ($attempt -eq 4 -or $_.Exception.Message -notmatch '(?i)(429|Too Many Requests|quota exceeded)') { throw }
                Start-Sleep -Seconds (10 * $attempt)
            }
        }
        $match = @($result.value) | Where-Object {
            $essentials = $_.properties.essentials
            $null -ne $essentials -and
            $essentials.PSObject.Properties.Name -contains 'alertRule' -and
            $essentials.PSObject.Properties.Name -contains 'targetResource' -and
            $essentials.PSObject.Properties.Name -contains 'monitorCondition' -and
            $essentials.PSObject.Properties.Name -contains 'startDateTime' -and
            ($essentials.alertRule -split '/')[-1] -eq $script:AlertName -and
            $essentials.targetResource -like "*$resourceGroupSegment*" -and
            $essentials.monitorCondition -eq 'Fired' -and
            [DateTime]$essentials.startDateTime -ge $NotBeforeUtc
        } | Sort-Object { [DateTime]$_.properties.essentials.startDateTime } -Descending |
            Select-Object -First 1
        if ($null -ne $match) { return $match }
        Start-Sleep -Seconds 15
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Configured alert '$script:AlertName' did not fire within eight minutes. Verify the App Insights request query, alert scope, response plan title match, and generated 503 evidence."
}

function Get-CaldovaRecommendationsActiveAlert {
    param([Parameter(Mandatory)]$Context)

    $resourceGroupSegment = "/resourceGroups/$($Context.State.resourceGroupName)/"
    $url = "/subscriptions/$($Context.State.subscriptionId)/providers/Microsoft.AlertsManagement/alerts"
    $result = Invoke-CaldovaAz -Arguments @(
        'rest', '--method', 'get', '--url', $url,
        '--url-parameters', "api-version=$script:AlertsApiVersion",
        '--output', 'json'
    ) -ReturnJson
    return @($result.value) | Where-Object {
        $essentials = $_.properties.essentials
        $null -ne $essentials -and
        $essentials.PSObject.Properties.Name -contains 'alertRule' -and
        $essentials.PSObject.Properties.Name -contains 'targetResource' -and
        $essentials.PSObject.Properties.Name -contains 'monitorCondition' -and
        $essentials.PSObject.Properties.Name -contains 'startDateTime' -and
        ($essentials.alertRule -split '/')[-1] -eq $script:AlertName -and
        $essentials.targetResource -like "*$resourceGroupSegment*" -and
        $essentials.monitorCondition -eq 'Fired'
    } | Sort-Object { [DateTime]$_.properties.essentials.startDateTime } -Descending |
        Select-Object -First 1
}

function Wait-CaldovaRecommendationsAlertResolution {
    param([Parameter(Mandatory)]$Context)

    $deadline = [DateTime]::UtcNow.AddMinutes(8)
    do {
        Get-CaldovaRecommendationsProbe -Uri $Context.FeatureUri -EvidenceMarker "recovery-$([DateTime]::UtcNow.Ticks)" | Out-Null
        if ($null -eq (Get-CaldovaRecommendationsActiveAlert -Context $Context)) { return }
        Start-Sleep -Seconds 30
    } while ([DateTime]::UtcNow -lt $deadline)
    $active = Get-CaldovaRecommendationsActiveAlert -Context $Context
    $alertId = if ($null -eq $active) { 'unknown' } else { ($active.id -split '/')[-1] }
    throw "Guided alert '$alertId' remained Fired after course recommendations recovered. Verify the custom-event query and auto-resolution before closing it."
}

function Initialize-CaldovaRecommendationsPreparedState {
    param([Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber)

    $context = Get-CaldovaRecommendationsContext -LearnerNumber $LearnerNumber -TargetAgent preconfigured
    Invoke-CaldovaAz -Arguments @('account', 'set', '--subscription', $context.State.subscriptionId) | Out-Null
    Assert-CaldovaRecommendationsCoreHealthy -Context $context | Out-Null
    $change = Set-CaldovaRecommendationsMode -Context $context -Mode $script:UnavailableValue
    $probe = Wait-CaldovaRecommendationsState -Context $context -State degraded
    $traffic = Send-CaldovaRecommendationsTraffic -Context $context -ExpectedState degraded -Requests 6
    return [pscustomobject]@{ changed = $change.changed; probe = $probe; traffic = $traffic; alertExpected = $false }
}

function Invoke-CaldovaRecommendationsOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Check', 'Break', 'Verify', 'Fix', 'Reset')][string]$Operation,
        [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
        [Parameter(Mandatory)][ValidateSet('preconfigured', 'configure')][string]$TargetAgent
    )

    $context = Get-CaldovaRecommendationsContext -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent
    $snapshotPath = Get-CaldovaScenarioSnapshotPath -Context $context
    Invoke-CaldovaAz -Arguments @('account', 'set', '--subscription', $context.State.subscriptionId) | Out-Null

    if ($Operation -eq 'Check') {
        Write-Host '::phase::readiness::35::Checking core health and the isolated guided feature'
        $core = Assert-CaldovaRecommendationsCoreHealthy -Context $context
        $alertConfigured = Test-CaldovaRecommendationsAlertConfigured -Context $context
        $feature = Get-CaldovaRecommendationsProbe -Uri $context.FeatureUri -EvidenceMarker "check-$([DateTime]::UtcNow.Ticks)"
        if ($feature.status -notin @(200, 503) -or $feature.featureStatus -notin @('available', 'degraded')) {
            throw "Course recommendations returned an unexpected HTTP/state combination: HTTP $($feature.status), state '$($feature.featureStatus)'."
        }
        return [pscustomobject]@{
            ready = $true
            agentName = $context.SelectedAgentName
            investigationUrl = $context.SelectedPortalUrl
            feature = $feature
            core = $core
            alertConfigured = $alertConfigured
            alertExpected = $alertConfigured
        }
    }

    if ($Operation -eq 'Break') {
        Write-Host '::phase::snapshot::25::Recording the current guided-feature revision setting'
        $setting = Get-CaldovaRecommendationsSetting -Context $context
        if (-not (Test-Path -LiteralPath $snapshotPath)) {
            Save-CaldovaScenarioSnapshot -Context $context -Snapshot @{
                kind = 'container-app-environment-setting'
                appName = $setting.appName
                settingName = $script:SettingName
                present = $setting.present
                value = $setting.value
                revisionName = $setting.latestReadyRevisionName
            } | Out-Null
        }
        Assert-CaldovaRecommendationsCoreHealthy -Context $context | Out-Null
        $alertConfigured = Test-CaldovaRecommendationsAlertConfigured -Context $context
        $notBefore = [DateTime]::UtcNow.AddSeconds(-30)
        Write-Host '::phase::impact::55::Activating the isolated recommendations symptom'
        $changed = Set-CaldovaRecommendationsMode -Context $context -Mode $script:UnavailableValue
        $impact = Wait-CaldovaRecommendationsState -Context $context -State degraded
        Write-Host '::phase::evidence::82::Generating App Insights request evidence for manual investigation'
        $traffic = Send-CaldovaRecommendationsTraffic -Context $context -ExpectedState degraded
        $alert = if ($alertConfigured) {
            Write-Host '::phase::detection::90::Waiting for the learner-configured alert'
            Wait-CaldovaRecommendationsAlert -Context $context -NotBeforeUtc $notBefore
        } else {
            $null
        }
        return [pscustomobject]@{
            changed = $changed.changed
            scenarioId = $script:ScenarioId
            impact = $impact
            traffic = $traffic
            alertExpected = $alertConfigured
            alertId = if ($null -eq $alert) { $null } else { $alert.id }
            investigationUrl = $context.SelectedPortalUrl
        }
    }

    if ($Operation -eq 'Verify') {
        Write-Host '::phase::recovery::65::Checking the isolated feature and core learning paths'
        $core = Assert-CaldovaRecommendationsCoreHealthy -Context $context
        $feature = Get-CaldovaRecommendationsProbe -Uri $context.FeatureUri -EvidenceMarker "verify-$([DateTime]::UtcNow.Ticks)"
        return [pscustomobject]@{
            recovered = $feature.status -eq 200 -and $feature.featureStatus -eq 'available'
            feature = $feature
            core = $core
            alertExpected = Test-CaldovaRecommendationsAlertConfigured -Context $context
        }
    }

    Write-Host '::phase::restore::55::Restoring course recommendations availability'
    $changed = Set-CaldovaRecommendationsMode -Context $context -Mode $script:AvailableValue
    $feature = Wait-CaldovaRecommendationsState -Context $context -State available
    $traffic = Send-CaldovaRecommendationsTraffic -Context $context -ExpectedState available -Requests 5
    $core = Assert-CaldovaRecommendationsCoreHealthy -Context $context
    $closedAlerts = 0
    if (Test-CaldovaRecommendationsAlertConfigured -Context $context) {
        Wait-CaldovaRecommendationsAlertResolution -Context $context
        $closedAlerts = Close-CaldovaRecoveredAlerts -Context $context -AlertName $script:AlertName
    }
    if ($Operation -eq 'Reset') {
        Remove-CaldovaScenarioSnapshot -Context $context
        return [pscustomobject]@{ reset = $true; recovered = $true; changed = $changed.changed; feature = $feature; traffic = $traffic; core = $core; closedAlerts = $closedAlerts }
    }
    return [pscustomobject]@{ recovered = $true; changed = $changed.changed; feature = $feature; traffic = $traffic; core = $core; closedAlerts = $closedAlerts }
}

Export-ModuleMember -Function @(
    'Initialize-CaldovaRecommendationsPreparedState',
    'Invoke-CaldovaRecommendationsOperation'
)
