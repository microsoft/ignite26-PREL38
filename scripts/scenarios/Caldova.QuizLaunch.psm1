Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\Caldova.Lifecycle.psm1')

$script:FilterName = 'caldova-azure-monitor-response'
$script:AgentApiVersion = '2025-05-01-preview'
$script:AlertsApiVersion = '2019-03-01'
$script:ScenarioOneRouteTableName = 'rt-caldova-quiz-launch-scenario-1'
$script:ScenarioOneRouteNamePrefix = 'drop-portal-'
$script:BrokenProbePath = '/caldova-scenario-2-unavailable'

function Get-CaldovaQuizLaunchContext {
    param(
        [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
        [Parameter(Mandatory)][ValidateSet('preconfigured', 'configure')][string]$TargetAgent,
        [Parameter(Mandatory)][ValidateRange(1, 3)][int]$ScenarioNumber
    )

    $state = Get-CaldovaState -LearnerNumber $LearnerNumber
    if ($state.schemaVersion -lt 2) {
        throw 'Caldova state is older than the scenario contract. Re-run provision.ps1 before continuing.'
    }
    $selectedAgentName = if ($TargetAgent -eq 'preconfigured') { $state.preconfiguredAgentName } else { $state.configuredAgentName }
    $otherAgentName = if ($TargetAgent -eq 'preconfigured') { $state.configuredAgentName } else { $state.preconfiguredAgentName }
    $selectedPortalUrl = if ($TargetAgent -eq 'preconfigured') { $state.preconfiguredAgentPortalUrl } else { $state.configuredAgentPortalUrl }
    [pscustomobject]@{
        State = $state
        LearnerNumber = $LearnerNumber
        TargetAgent = $TargetAgent
        ScenarioNumber = $ScenarioNumber
        ScenarioId = "quiz-launch-scenario-$ScenarioNumber"
        AlertName = 'Caldova-quiz-launch-failing'
        SelectedAgentName = $selectedAgentName
        OtherAgentName = $otherAgentName
        SelectedPortalUrl = $selectedPortalUrl
        PublicQuizUri = "$($state.publicEndpoint.TrimEnd('/'))/api/quiz/OPS-201-M1"
    }
}

function Get-CaldovaTaggedResource {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$ResourceType,
        [Parameter(Mandatory)][string]$NamePrefix
    )

    $resources = @(Invoke-CaldovaAz -Arguments @(
        'resource', 'list',
        '--resource-group', $Context.State.resourceGroupName,
        '--resource-type', $ResourceType,
        '--output', 'json'
    ) -ReturnJson) | Where-Object {
        $_.name -like "$NamePrefix*" -and
        $_.tags.solution -eq 'caldova' -and
        ($_.tags.learner -eq "user$($Context.LearnerNumber)" -or $null -eq $_.tags.learner)
    }
    if ($resources.Count -ne 1) {
        throw "Expected exactly one learner-scoped $ResourceType resource with prefix '$NamePrefix' in '$($Context.State.resourceGroupName)', but found $($resources.Count). Check deployment tags and remove ambiguous resources."
    }
    return $resources[0]
}

function Get-CaldovaGateway {
    param([Parameter(Mandatory)]$Context)
    $resource = Get-CaldovaTaggedResource -Context $Context -ResourceType 'Microsoft.Network/applicationGateways' -NamePrefix 'agw-caldova-'
    return Invoke-CaldovaAz -Arguments @('network', 'application-gateway', 'show', '--ids', $resource.id, '--output', 'json') -ReturnJson
}

function Get-CaldovaPortalApp {
    param([Parameter(Mandatory)]$Context)
    $resource = Get-CaldovaTaggedResource -Context $Context -ResourceType 'Microsoft.App/containerApps' -NamePrefix 'ca-caldova-portal-'
    return Invoke-CaldovaAz -Arguments @('containerapp', 'show', '--ids', $resource.id, '--output', 'json') -ReturnJson
}

function Get-CaldovaApiApp {
    param([Parameter(Mandatory)]$Context)
    $resource = Get-CaldovaTaggedResource -Context $Context -ResourceType 'Microsoft.App/containerApps' -NamePrefix 'ca-caldova-api-'
    return Invoke-CaldovaAz -Arguments @('containerapp', 'show', '--ids', $resource.id, '--output', 'json') -ReturnJson
}

function Get-CaldovaAppPath {
    param([Parameter(Mandatory)]$Context)

    $gateway = Get-CaldovaGateway -Context $Context
    $gatewaySubnetId = $gateway.gatewayIPConfigurations[0].subnet.id
    if ([string]::IsNullOrWhiteSpace($gatewaySubnetId)) {
        throw "Application entry point '$($gateway.name)' has no subnet reference."
    }
    $sourceSubnet = Invoke-CaldovaAz -Arguments @('network', 'vnet', 'subnet', 'show', '--ids', $gatewaySubnetId, '--output', 'json') -ReturnJson
    $vnets = @(Invoke-CaldovaAz -Arguments @(
        'network', 'vnet', 'list',
        '--resource-group', $Context.State.resourceGroupName,
        '--output', 'json'
    ) -ReturnJson) | Where-Object { $_.name -like 'vnet-caldova-*' }
    $appSubnets = @($vnets.subnets) | Where-Object {
        @($_.delegations) | Where-Object {
            $serviceName = if ($_.PSObject.Properties.Name -contains 'serviceName') {
                [string]$_.serviceName
            } elseif ($_.PSObject.Properties.Name -contains 'properties' -and $_.properties.PSObject.Properties.Name -contains 'serviceName') {
                [string]$_.properties.serviceName
            } else {
                ''
            }
            $serviceName -eq 'Microsoft.App/environments'
        }
    }
    if ($appSubnets.Count -ne 1 -or [string]::IsNullOrWhiteSpace($appSubnets[0].networkSecurityGroup.id)) {
        throw "Could not resolve one learner application subnet with an attached security policy. Check the deployed virtual network."
    }
    $nsg = Invoke-CaldovaAz -Arguments @('network', 'nsg', 'show', '--ids', $appSubnets[0].networkSecurityGroup.id, '--output', 'json') -ReturnJson
    $sourcePrefix = if ($sourceSubnet.addressPrefix) { $sourceSubnet.addressPrefix } else { $sourceSubnet.addressPrefixes[0] }
    return [pscustomobject]@{ Gateway = $gateway; Nsg = $nsg; SourcePrefix = $sourcePrefix }
}

function Invoke-CaldovaWebProbe {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [int]$TimeoutSec = 20
    )

    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WebRequest -Uri $Uri -TimeoutSec $TimeoutSec -UseBasicParsing -SkipHttpErrorCheck
        return [pscustomobject]@{ uri = $Uri; status = [int]$response.StatusCode; elapsedMs = $watch.ElapsedMilliseconds }
    } catch {
        return [pscustomobject]@{ uri = $Uri; status = 0; elapsedMs = $watch.ElapsedMilliseconds; error = $_.Exception.Message }
    } finally {
        $watch.Stop()
    }
}

function Assert-CaldovaDirectApplicationHealthy {
    param([Parameter(Mandatory)]$Context)
    $portal = Get-CaldovaPortalApp -Context $Context
    $apiBaseUrl = [string]($portal.properties.template.containers[0].env |
        Where-Object { $_.name -eq 'CALDOVA_API_BASE_URL' } |
        Select-Object -ExpandProperty value -First 1)
    if ([string]::IsNullOrWhiteSpace($apiBaseUrl)) {
        throw "Portal '$($portal.name)' has no CALDOVA_API_BASE_URL environment value."
    }
    $apiOutput = $null
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            $apiOutput = Invoke-CaldovaAz -Arguments @(
                'containerapp', 'exec',
                '--resource-group', $Context.State.resourceGroupName,
                '--name', $portal.name,
                '--command', "wget -qO- $($apiBaseUrl.TrimEnd('/'))/quiz/OPS-201-M1"
            )
            break
        }
        catch {
            if ($attempt -eq 4 -or $_.Exception.Message -notmatch '429 Too Many Requests') {
                throw
            }
            Start-Sleep -Seconds (10 * $attempt)
        }
    }
    if (($apiOutput | Out-String) -notmatch '"id":"OPS-201-M1"') {
        throw 'The private quiz service did not return a successful response inside the application environment. Restore the application baseline before starting.'
    }
    return [pscustomobject]@{ healthy = $true; status = 200; source = $portal.name }
}

function Assert-CaldovaHealthyPrecondition {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][bool]$RequireDirect
    )

    $public = Invoke-CaldovaWebProbe -Uri $Context.PublicQuizUri
    if ($public.status -ne 200) {
        throw "The learner-visible quiz path is not healthy before the exercise (HTTP $($public.status)). Run Reset or restore the baseline before starting; no scenario change was made."
    }
    $direct = $null
    if ($RequireDirect) {
        $direct = Assert-CaldovaDirectApplicationHealthy -Context $Context
    }
    return [pscustomobject]@{ public = $public; direct = $direct }
}

function Wait-CaldovaHttpState {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][ValidateSet('Healthy', 'Impacted')][string]$State,
        [int]$TimeoutSeconds = 240
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $probe = Invoke-CaldovaWebProbe -Uri "${Uri}?scenarioPoll=$([DateTime]::UtcNow.Ticks)"
        $matches = if ($State -eq 'Healthy') { $probe.status -eq 200 } else { $probe.status -eq 0 -or $probe.status -ge 500 }
        if ($matches) { return $probe }
        Start-Sleep -Seconds 10
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "The learner-visible quiz path did not become $($State.ToLowerInvariant()) within $TimeoutSeconds seconds. Last HTTP status: $($probe.status). Inspect the public entry point before retrying."
}

function Get-CaldovaFilterResource {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$AgentName,
        [switch]$AllowMissing
    )
    $url = "https://management.azure.com/subscriptions/$($Context.State.subscriptionId)/resourceGroups/$($Context.State.resourceGroupName)/providers/Microsoft.App/agents/$AgentName/incidentFilters/$($script:FilterName)?api-version=$($script:AgentApiVersion)"
    try {
        return Invoke-CaldovaAz -Arguments @('rest', '--method', 'get', '--url', $url, '--output', 'json') -ReturnJson
    } catch {
        if ($AllowMissing -and $_.Exception.Message -match '(?i)(404|not found|could not be found)') { return $null }
        throw
    }
}

function ConvertFrom-CaldovaFilter {
    param([Parameter(Mandatory)]$Resource)
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Resource.properties.value))
    return $json | ConvertFrom-Json
}

function Set-CaldovaFilterEnabled {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$AgentName,
        [Parameter(Mandatory)]$Resource,
        [Parameter(Mandatory)][bool]$Enabled,
        [switch]$DisableMerge
    )
    $spec = ConvertFrom-CaldovaFilter -Resource $Resource
    $enabledMatches = [bool]$spec.isEnabled -eq $Enabled
    $mergeMatches = -not $DisableMerge -or
        ($spec.PSObject.Properties.Name -contains 'mergeEnabled' -and [bool]$spec.mergeEnabled -eq $false)
    if ($enabledMatches -and $mergeMatches) {
        return
    }
    $spec.isEnabled = $Enabled
    if ($DisableMerge) {
        $spec.mergeEnabled = $false
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($spec | ConvertTo-Json -Depth 20 -Compress)))
    $body = @{ properties = @{ value = $encoded } } | ConvertTo-Json -Depth 5 -Compress
    $url = "https://management.azure.com/subscriptions/$($Context.State.subscriptionId)/resourceGroups/$($Context.State.resourceGroupName)/providers/Microsoft.App/agents/$AgentName/incidentFilters/$($script:FilterName)?api-version=$($script:AgentApiVersion)"
    $bodyPath = Join-Path ([IO.Path]::GetTempPath()) "caldova-filter-$([guid]::NewGuid().ToString('N')).json"
    try {
        Set-Content -LiteralPath $bodyPath -Value $body -Encoding utf8NoBOM
        Invoke-CaldovaAz -Arguments @('rest', '--method', 'put', '--url', $url, '--body', "@$bodyPath", '--output', 'none') | Out-Null
    } finally {
        Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue
    }
}

function Assert-CaldovaQuizLaunchReady {
    param([Parameter(Mandatory)]$Context)

    Invoke-CaldovaAz -Arguments @('account', 'set', '--subscription', $Context.State.subscriptionId) | Out-Null
    $selected = Get-CaldovaFilterResource -Context $Context -AgentName $Context.SelectedAgentName -AllowMissing
    if ($null -eq $selected) {
        throw "The selected agent '$($Context.SelectedAgentName)' is missing response plan '$($script:FilterName)'. Apply the checked-in response plan and run Check configuration again."
    }
    $spec = ConvertFrom-CaldovaFilter -Resource $selected
    if ($spec.incidentPlatform -ne 'AzMonitor' -or $spec.titleContains -notmatch '(?i)Caldova' -or [string]::IsNullOrWhiteSpace($spec.handlingAgent)) {
        throw "Response plan '$($script:FilterName)' is incomplete for Azure Monitor. Set the Caldova title match and handling agent, then check again."
    }
    $alert = Invoke-CaldovaAz -Arguments @(
        'monitor', 'scheduled-query', 'show',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $Context.AlertName,
        '--output', 'json'
    ) -ReturnJson
    $enabled = if ($alert.PSObject.Properties.Name -contains 'enabled') { [bool]$alert.enabled } else { [bool]$alert.properties.enabled }
    if (-not $enabled) {
        throw "Azure Monitor alert '$($Context.AlertName)' is disabled. Enable the five-minute learner-visible alert before starting."
    }
    $frequency = if ($alert.PSObject.Properties.Name -contains 'evaluationFrequency') { [string]$alert.evaluationFrequency } else { [string]$alert.properties.evaluationFrequency }
    if ($frequency -notin @('PT5M', '0:05:00', '00:05:00')) {
        throw "Azure Monitor alert '$($Context.AlertName)' must evaluate every five minutes; current value is '$frequency'. Redeploy the workshop baseline."
    }
    [pscustomobject]@{
        ready = $true
        agentName = $Context.SelectedAgentName
        investigationUrl = $Context.SelectedPortalUrl
        responsePlan = $script:FilterName
        alertName = $Context.AlertName
    }
}

function Get-CaldovaOwnershipPath {
    param([Parameter(Mandatory)]$Context)
    $directory = Split-Path (Get-CaldovaStatePath -LearnerNumber $Context.LearnerNumber) -Parent
    return Join-Path $directory "ownership-user$($Context.LearnerNumber).json"
}

function Set-CaldovaSelectedOwnership {
    param([Parameter(Mandatory)]$Context)

    $selected = Get-CaldovaFilterResource -Context $Context -AgentName $Context.SelectedAgentName
    $other = Get-CaldovaFilterResource -Context $Context -AgentName $Context.OtherAgentName -AllowMissing
    $path = Get-CaldovaOwnershipPath -Context $Context
    if (-not (Test-Path -LiteralPath $path)) {
        @{
            schemaVersion = 1
            capturedAtUtc = [DateTime]::UtcNow.ToString('o')
            filters = @(
                @{ agentName = $Context.SelectedAgentName; exists = $true; enabled = [bool](ConvertFrom-CaldovaFilter $selected).isEnabled },
                @{ agentName = $Context.OtherAgentName; exists = $null -ne $other; enabled = if ($null -ne $other) { [bool](ConvertFrom-CaldovaFilter $other).isEnabled } else { $false } }
            )
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    }
    Set-CaldovaFilterEnabled -Context $Context -AgentName $Context.SelectedAgentName -Resource $selected -Enabled $true -DisableMerge
    if ($null -ne $other) { Set-CaldovaFilterEnabled -Context $Context -AgentName $Context.OtherAgentName -Resource $other -Enabled $false }
    $enabled = @(
        ConvertFrom-CaldovaFilter (Get-CaldovaFilterResource -Context $Context -AgentName $Context.SelectedAgentName)
        if ($null -ne $other) { ConvertFrom-CaldovaFilter (Get-CaldovaFilterResource -Context $Context -AgentName $Context.OtherAgentName) }
    ) | Where-Object { $_.titleContains -match '(?i)Caldova' -and $_.isEnabled }
    if ($enabled.Count -ne 1) {
        throw "Response-plan ownership validation found $($enabled.Count) enabled Caldova owners. Run Reset before retrying; exactly one selected agent must own the alert."
    }
}

function Restore-CaldovaOwnership {
    param([Parameter(Mandatory)]$Context)
    $path = Get-CaldovaOwnershipPath -Context $Context
    if (-not (Test-Path -LiteralPath $path)) { return }
    $snapshot = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    foreach ($entry in $snapshot.filters) {
        if (-not $entry.exists) { continue }
        $resource = Get-CaldovaFilterResource -Context $Context -AgentName $entry.agentName -AllowMissing
        if ($null -ne $resource) {
            Set-CaldovaFilterEnabled -Context $Context -AgentName $entry.agentName -Resource $resource -Enabled ([bool]$entry.enabled)
        }
    }
    Remove-Item -LiteralPath $path -Force
}

function Get-CaldovaScenarioSnapshotPath {
    param([Parameter(Mandatory)]$Context)
    $directory = Split-Path (Get-CaldovaStatePath -LearnerNumber $Context.LearnerNumber) -Parent
    return Join-Path $directory "$($Context.ScenarioId)-baseline-user$($Context.LearnerNumber).json"
}

function Save-CaldovaScenarioSnapshot {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][hashtable]$Snapshot
    )
    $path = Get-CaldovaScenarioSnapshotPath -Context $Context
    if (-not (Test-Path -LiteralPath $path)) {
        $Snapshot.schemaVersion = 1
        $Snapshot.scenarioId = $Context.ScenarioId
        $Snapshot.capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        $Snapshot | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-CaldovaScenarioSnapshot {
    param([Parameter(Mandatory)]$Context)
    $path = Get-CaldovaScenarioSnapshotPath -Context $Context
    if (-not (Test-Path -LiteralPath $path)) {
        throw "The saved baseline for '$($Context.ScenarioId)' is missing. Do not guess recovery values; run the facilitator baseline recovery procedure."
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Remove-CaldovaScenarioSnapshot {
    param([Parameter(Mandatory)]$Context)
    Remove-Item -LiteralPath (Get-CaldovaScenarioSnapshotPath -Context $Context) -Force -ErrorAction SilentlyContinue
}

function Start-CaldovaFailureTraffic {
    param([Parameter(Mandatory)]$Context)
    $count = 0
    foreach ($attempt in 1..12) {
        Invoke-CaldovaWebProbe -Uri "$($Context.PublicQuizUri)?scenarioTraffic=$attempt" -TimeoutSec 10 | Out-Null
        $count++
        Start-Sleep -Seconds 3
    }
    return $count
}

function Wait-CaldovaQuizLaunchAlert {
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
        $url = "https://management.azure.com/subscriptions/$($Context.State.subscriptionId)/providers/Microsoft.AlertsManagement/alerts?api-version=$($script:AlertsApiVersion)"
        $result = Invoke-CaldovaAz -Arguments @('rest', '--method', 'get', '--url', $url, '--output', 'json') -ReturnJson
        $match = @($result.value) | Where-Object {
            $essentials = $_.properties.essentials
            $null -ne $essentials -and
            $essentials.PSObject.Properties.Name -contains 'alertRule' -and
            $essentials.PSObject.Properties.Name -contains 'targetResource' -and
            $essentials.PSObject.Properties.Name -contains 'monitorCondition' -and
            $essentials.PSObject.Properties.Name -contains 'startDateTime' -and
            $essentials.alertRule -match [regex]::Escape($Context.AlertName) -and
            $essentials.targetResource -eq $workspaceId -and
            $essentials.monitorCondition -eq 'Fired' -and
            [DateTime]$essentials.startDateTime -ge $NotBeforeUtc
        } | Select-Object -First 1
        if ($null -ne $match) { return $match }
        Start-Sleep -Seconds 15
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Azure Monitor did not report fresh alert '$($Context.AlertName)' within 8 minutes. Confirm the five-minute rule and generated learner traffic. The exercise remains active; use Reset after investigation."
}

function Test-CaldovaBackendHealthy {
    param([Parameter(Mandatory)]$Context)
    $gateway = Get-CaldovaGateway -Context $Context
    $health = Invoke-CaldovaAz -Arguments @(
        'network', 'application-gateway', 'show-backend-health',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $gateway.name,
        '--output', 'json'
    ) -ReturnJson
    $states = @($health.backendAddressPools.backendHttpSettingsCollection.servers.health)
    return $states.Count -gt 0 -and @($states | Where-Object { $_ -ne 'Healthy' }).Count -eq 0
}

function Assert-CaldovaRecovery {
    param([Parameter(Mandatory)]$Context)
    $public = Wait-CaldovaHttpState -Uri $Context.PublicQuizUri -State Healthy
    if (-not (Test-CaldovaBackendHealthy -Context $Context)) {
        throw 'The learner-visible path recovered, but the application entry point still reports an unhealthy backend. Continue the investigation before marking recovery.'
    }
    return [pscustomobject]@{ recovered = $true; publicStatus = $public.status; backendHealthy = $true }
}

function Set-CaldovaScenarioOneFault {
    param([Parameter(Mandatory)]$Context)
    $path = Get-CaldovaScenarioOnePath -Context $Context
    Invoke-CaldovaAz -Arguments @(
        'network', 'route-table', 'create',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $script:ScenarioOneRouteTableName,
        '--tags', 'solution=caldova', 'session=PREL38', 'scenario=quiz-launch-scenario-1',
        '--output', 'none'
    ) | Out-Null
    for ($index = 0; $index -lt $path.BackendAddresses.Count; $index++) {
        Invoke-CaldovaAz -Arguments @(
            'network', 'route-table', 'route', 'create',
            '--resource-group', $Context.State.resourceGroupName,
            '--route-table-name', $script:ScenarioOneRouteTableName,
            '--name', "$($script:ScenarioOneRouteNamePrefix)$index",
            '--address-prefix', "$($path.BackendAddresses[$index])/32",
            '--next-hop-type', 'None',
            '--output', 'none'
        ) | Out-Null
    }
    Invoke-CaldovaAz -Arguments @(
        'network', 'vnet', 'subnet', 'update',
        '--ids', $path.Subnet.id,
        '--route-table', $script:ScenarioOneRouteTableName,
        '--output', 'none'
    ) | Out-Null
}

function Get-CaldovaScenarioOnePath {
    param([Parameter(Mandatory)]$Context)
    $gateway = Get-CaldovaGateway -Context $Context
    $subnet = Invoke-CaldovaAz -Arguments @(
        'network', 'vnet', 'subnet', 'show',
        '--ids', $gateway.gatewayIPConfigurations[0].subnet.id,
        '--output', 'json'
    ) -ReturnJson
    $fqdns = @($gateway.backendAddressPools.backendAddresses.fqdn |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique)
    if ($fqdns.Count -ne 1) {
        throw "Expected exactly one application entry-point backend FQDN, but found $($fqdns.Count). Restore the workshop baseline."
    }
    $portal = Get-CaldovaPortalApp -Context $Context
    $environmentId = [string]$portal.properties.managedEnvironmentId
    $staticIp = (Invoke-CaldovaAz -Arguments @(
        'containerapp', 'env', 'show',
        '--ids', $environmentId,
        '--query', 'properties.staticIp',
        '--output', 'tsv'
    ) | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($staticIp) -or $staticIp -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        throw "The application environment for '$($fqdns[0])' has no usable static IPv4 address."
    }
    [pscustomobject]@{ Gateway = $gateway; Subnet = $subnet; BackendFqdn = $fqdns[0]; BackendAddresses = @($staticIp) }
}

function Restore-CaldovaScenarioOne {
    param([Parameter(Mandatory)]$Context)
    $snapshot = Get-CaldovaScenarioSnapshot -Context $Context
    Remove-CaldovaScenarioOneRoute -Context $Context -SubnetId $snapshot.subnetId -OriginalRouteTableId $snapshot.originalRouteTableId
}

function Remove-CaldovaScenarioOneRoute {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$SubnetId,
        [AllowNull()][string]$OriginalRouteTableId
    )
    if ([string]::IsNullOrWhiteSpace($OriginalRouteTableId)) {
        Invoke-CaldovaAz -Arguments @(
            'network', 'vnet', 'subnet', 'update',
            '--ids', $SubnetId,
            '--remove', 'routeTable',
            '--output', 'none'
        ) | Out-Null
    } else {
        Invoke-CaldovaAz -Arguments @(
            'network', 'vnet', 'subnet', 'update',
            '--ids', $SubnetId,
            '--route-table', $OriginalRouteTableId,
            '--output', 'none'
        ) | Out-Null
    }
    try {
        $routeTable = Invoke-CaldovaAz -Arguments @(
            'network', 'route-table', 'show',
            '--resource-group', $Context.State.resourceGroupName,
            '--name', $script:ScenarioOneRouteTableName,
            '--output', 'json'
        ) -ReturnJson
    } catch {
        if ($_.Exception.Message -match '(?i)(ResourceNotFound|not found)') {
            return
        }
        throw
    }
    if ($routeTable.tags.solution -ne 'caldova' -or $routeTable.tags.scenario -ne 'quiz-launch-scenario-1') {
        throw "Route table '$($script:ScenarioOneRouteTableName)' does not match the planted scenario fingerprint. Refusing to delete it."
    }
    Invoke-CaldovaAz -Arguments @(
        'network', 'route-table', 'delete',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $script:ScenarioOneRouteTableName,
        '--output', 'none'
    ) | Out-Null
}

function Get-CaldovaGatewayProbe {
    param([Parameter(Mandatory)]$Context)
    $gateway = Get-CaldovaGateway -Context $Context
    $probeIds = @(@($gateway.backendHttpSettingsCollection.probe.id) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique)
    if ($probeIds.Count -ne 1) {
        throw "Expected exactly one active health check on '$($gateway.name)', but found $($probeIds.Count). Restore the workshop baseline before continuing."
    }
    $probeName = ($probeIds[0] -split '/')[-1]
    $probe = Invoke-CaldovaAz -Arguments @(
        'network', 'application-gateway', 'probe', 'show',
        '--resource-group', $Context.State.resourceGroupName,
        '--gateway-name', $gateway.name,
        '--name', $probeName,
        '--output', 'json'
    ) -ReturnJson
    return [pscustomobject]@{ Gateway = $gateway; Probe = $probe }
}

function Set-CaldovaProbePath {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$GatewayName,
        [Parameter(Mandatory)][string]$ProbeName,
        [Parameter(Mandatory)][string]$Path
    )
    Invoke-CaldovaAz -Arguments @(
        'network', 'application-gateway', 'probe', 'update',
        '--resource-group', $Context.State.resourceGroupName,
        '--gateway-name', $GatewayName,
        '--name', $ProbeName,
        '--path', $Path,
        '--output', 'none'
    ) | Out-Null
    $actual = (Invoke-CaldovaAz -Arguments @(
        'network', 'application-gateway', 'probe', 'show',
        '--resource-group', $Context.State.resourceGroupName,
        '--gateway-name', $GatewayName,
        '--name', $ProbeName,
        '--query', 'path',
        '--output', 'tsv'
    ) | Out-String).Trim()
    if ($actual -ne $Path) { throw "The saved entry-point health path did not persist. Expected '$Path', read back '$actual'." }
}

function Restore-CaldovaScenarioTwo {
    param([Parameter(Mandatory)]$Context)
    $snapshot = Get-CaldovaScenarioSnapshot -Context $Context
    Set-CaldovaProbePath -Context $Context -GatewayName $snapshot.gatewayName -ProbeName $snapshot.probeName -Path $snapshot.path
}

function Restore-CaldovaScenarioThree {
    param([Parameter(Mandatory)]$Context)
    $snapshot = Get-CaldovaScenarioSnapshot -Context $Context
    Invoke-CaldovaAz -Arguments @(
        'containerapp', 'update',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $snapshot.appName,
        '--image', $snapshot.image,
        '--min-replicas', [string]$snapshot.minReplicas,
        '--max-replicas', [string]$snapshot.maxReplicas,
        '--output', 'none'
    ) | Out-Null
    Invoke-CaldovaAz -Arguments @(
        'containerapp', 'revision', 'set-mode',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $snapshot.appName,
        '--mode', $snapshot.activeRevisionsMode,
        '--output', 'none'
    ) | Out-Null
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    do {
        $app = Invoke-CaldovaAz -Arguments @('containerapp', 'show', '--resource-group', $Context.State.resourceGroupName, '--name', $snapshot.appName, '--output', 'json') -ReturnJson
        if ($app.properties.latestReadyRevisionName -and $app.properties.template.containers[0].image -eq $snapshot.image) { return }
        Start-Sleep -Seconds 10
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "The quiz service did not return to its pinned healthy state within 5 minutes. Inspect application health before retrying."
}

function Invoke-CaldovaQuizLaunchOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Check', 'Break', 'Verify', 'Fix', 'Reset')][string]$Operation,
        [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
        [Parameter(Mandatory)][ValidateSet('preconfigured', 'configure')][string]$TargetAgent,
        [Parameter(Mandatory)][ValidateRange(1, 3)][int]$ScenarioNumber
    )

    $context = Get-CaldovaQuizLaunchContext -LearnerNumber $LearnerNumber -TargetAgent $TargetAgent -ScenarioNumber $ScenarioNumber
    switch ($Operation) {
        'Check' {
            Write-Host '::phase::readiness::35::Checking learner deployment and selected response plan'
            $ready = Assert-CaldovaQuizLaunchReady -Context $context
            Write-Host '::phase::precondition::80::Confirming the learner-visible baseline'
            Assert-CaldovaHealthyPrecondition -Context $context -RequireDirect ($ScenarioNumber -in 1, 2) | Out-Null
            $ready
        }
        'Break' {
            Write-Host '::phase::readiness::12::Rechecking the selected agent and response plan'
            Assert-CaldovaQuizLaunchReady -Context $context | Out-Null
            $snapshotPath = Get-CaldovaScenarioSnapshotPath -Context $context
            if (Test-Path -LiteralPath $snapshotPath) {
                $existingImpact = Invoke-CaldovaWebProbe -Uri $context.PublicQuizUri
                if ($existingImpact.status -eq 0 -or $existingImpact.status -ge 500) {
                    Write-Host '::phase::impact::58::The selected exercise is already active'
                    Set-CaldovaSelectedOwnership -Context $context
                    $existingDirect = $null
                    if ($ScenarioNumber -in 1, 2) {
                        $existingDirect = Assert-CaldovaDirectApplicationHealthy -Context $context
                    }
                    [pscustomobject]@{
                        changed = $false
                        phase = 'investigate'
                        scenarioId = $context.ScenarioId
                        impact = @{ publicStatus = $existingImpact.status; directStatus = if ($null -ne $existingDirect) { $existingDirect.status } else { $null } }
                        trafficRequests = 0
                        alertId = $null
                        investigationUrl = $context.SelectedPortalUrl
                    }
                    break
                }
            }
            Assert-CaldovaHealthyPrecondition -Context $context -RequireDirect ($ScenarioNumber -in 1, 2) | Out-Null
            Write-Host '::phase::ownership::24::Assigning the live alert to the selected agent'
            Set-CaldovaSelectedOwnership -Context $context
            Write-Host '::phase::snapshot::34::Saving the exact healthy baseline'
            if ($ScenarioNumber -eq 1) {
                $path = Get-CaldovaScenarioOnePath -Context $context
                Save-CaldovaScenarioSnapshot -Context $context -Snapshot @{
                    kind = 'gateway-route'
                    subnetId = $path.Subnet.id
                    originalRouteTableId = if ($path.Subnet.PSObject.Properties.Name -contains 'routeTable' -and $null -ne $path.Subnet.routeTable) { [string]$path.Subnet.routeTable.id } else { $null }
                    routeTableName = $script:ScenarioOneRouteTableName
                    backendFqdn = $path.BackendFqdn
                    backendAddresses = $path.BackendAddresses
                } | Out-Null
                Write-Host '::phase::impact::46::Activating the selected exercise'
                Set-CaldovaScenarioOneFault -Context $context
            } elseif ($ScenarioNumber -eq 2) {
                $entry = Get-CaldovaGatewayProbe -Context $context
                Save-CaldovaScenarioSnapshot -Context $context -Snapshot @{
                    kind = 'entry-health-path'
                    gatewayName = $entry.Gateway.name
                    probeName = $entry.Probe.name
                    path = $entry.Probe.path
                    probe = $entry.Probe
                } | Out-Null
                Write-Host '::phase::impact::46::Activating the selected exercise'
                Set-CaldovaProbePath -Context $context -GatewayName $entry.Gateway.name -ProbeName $entry.Probe.name -Path $script:BrokenProbePath
            } else {
                $app = Get-CaldovaApiApp -Context $context
                $revisions = @(Invoke-CaldovaAz -Arguments @('containerapp', 'revision', 'list', '--resource-group', $context.State.resourceGroupName, '--name', $app.name, '--output', 'json') -ReturnJson)
                $active = @($revisions | Where-Object { $_.properties.active }) | Select-Object -First 1
                if ($null -eq $active) { throw "The quiz service has no active healthy state to snapshot. Restore the baseline before starting." }
                Save-CaldovaScenarioSnapshot -Context $context -Snapshot @{
                    kind = 'application-state'
                    appName = $app.name
                    image = $app.properties.template.containers[0].image
                    minReplicas = [int]$app.properties.template.scale.minReplicas
                    maxReplicas = [int]$app.properties.template.scale.maxReplicas
                    activeRevisionsMode = [string]$app.properties.configuration.activeRevisionsMode
                    activeRevisionName = $active.name
                    latestReadyRevisionName = $app.properties.latestReadyRevisionName
                } | Out-Null
                Write-Host '::phase::impact::46::Activating the selected exercise'
                Invoke-CaldovaAz -Arguments @('containerapp', 'revision', 'set-mode', '--resource-group', $context.State.resourceGroupName, '--name', $app.name, '--mode', 'multiple', '--output', 'none') | Out-Null
                Invoke-CaldovaAz -Arguments @('containerapp', 'revision', 'deactivate', '--resource-group', $context.State.resourceGroupName, '--name', $app.name, '--revision', $active.name, '--output', 'none') | Out-Null
                $activeAfter = (Invoke-CaldovaAz -Arguments @('containerapp', 'revision', 'show', '--resource-group', $context.State.resourceGroupName, '--name', $app.name, '--revision', $active.name, '--query', 'properties.active', '--output', 'tsv') | Out-String).Trim()
                if ($activeAfter -ne 'false') {
                    throw "The selected quiz service state did not deactivate. Run Reset before retrying."
                }
            }
            Write-Host '::phase::verify-impact::58::Verifying learner-visible impact'
            $impact = Wait-CaldovaHttpState -Uri $context.PublicQuizUri -State Impacted
            $direct = $null
            if ($ScenarioNumber -in 1, 2) {
                $direct = Assert-CaldovaDirectApplicationHealthy -Context $context
            }
            Write-Host '::phase::traffic::72::Generating controlled learner traffic'
            $notBefore = [DateTime]::UtcNow.AddSeconds(-30)
            $traffic = Start-CaldovaFailureTraffic -Context $context
            Write-Host '::phase::alert::88::Waiting for the five-minute Azure Monitor rule'
            $alert = Wait-CaldovaQuizLaunchAlert -Context $context -NotBeforeUtc $notBefore
            [pscustomobject]@{
                changed = $true
                phase = 'investigate'
                scenarioId = $context.ScenarioId
                impact = @{ publicStatus = $impact.status; directStatus = if ($null -ne $direct) { $direct.status } else { $null } }
                trafficRequests = $traffic
                alertId = $alert.id
                investigationUrl = $context.SelectedPortalUrl
            }
        }
        'Verify' {
            Write-Host '::phase::recovery::65::Checking learner-visible recovery'
            Assert-CaldovaRecovery -Context $context
        }
        'Fix' {
            Write-Host '::phase::restore::55::Restoring the saved live baseline'
            if ($ScenarioNumber -eq 1) { Restore-CaldovaScenarioOne -Context $context }
            elseif ($ScenarioNumber -eq 2) { Restore-CaldovaScenarioTwo -Context $context }
            else { Restore-CaldovaScenarioThree -Context $context }
            Write-Host '::phase::verify::85::Verifying learner-visible recovery'
            $recovery = Assert-CaldovaRecovery -Context $context
            $closedAlerts = Close-CaldovaRecoveredAlerts -Context $context -AlertName $context.AlertName
            [pscustomobject]@{ recovered = $recovery.recovered; publicStatus = $recovery.publicStatus; backendHealthy = $recovery.backendHealthy; closedAlerts = $closedAlerts }
        }
        'Reset' {
            Write-Host '::phase::baseline::45::Restoring the exact saved baseline'
            $snapshotPath = Get-CaldovaScenarioSnapshotPath -Context $context
            if (Test-Path -LiteralPath $snapshotPath) {
                if ($ScenarioNumber -eq 1) { Restore-CaldovaScenarioOne -Context $context }
                elseif ($ScenarioNumber -eq 2) { Restore-CaldovaScenarioTwo -Context $context }
                else { Restore-CaldovaScenarioThree -Context $context }
            } elseif ($ScenarioNumber -eq 1) {
                $path = Get-CaldovaScenarioOnePath -Context $context
                if ($path.Subnet.PSObject.Properties.Name -contains 'routeTable' -and
                    $null -ne $path.Subnet.routeTable -and
                    ($path.Subnet.routeTable.id -split '/')[-1] -eq $script:ScenarioOneRouteTableName) {
                    Remove-CaldovaScenarioOneRoute -Context $context -SubnetId $path.Subnet.id -OriginalRouteTableId $null
                }
            }
            $recovery = Assert-CaldovaRecovery -Context $context
            $closedAlerts = Close-CaldovaRecoveredAlerts -Context $context -AlertName $context.AlertName
            Write-Host '::phase::ownership::78::Restoring baseline response-plan ownership'
            Restore-CaldovaOwnership -Context $context
            Remove-CaldovaScenarioSnapshot -Context $context
            [pscustomobject]@{ reset = $true; publicStatus = $recovery.publicStatus; backendHealthy = $recovery.backendHealthy; closedAlerts = $closedAlerts }
        }
    }
}

Export-ModuleMember -Function @(
    'Invoke-CaldovaQuizLaunchOperation',
    'Get-CaldovaQuizLaunchContext',
    'Get-CaldovaApiApp',
    'Get-CaldovaTaggedResource',
    'Invoke-CaldovaWebProbe',
    'Wait-CaldovaHttpState',
    'Assert-CaldovaQuizLaunchReady',
    'Set-CaldovaSelectedOwnership',
    'Restore-CaldovaOwnership',
    'Get-CaldovaScenarioSnapshotPath',
    'Save-CaldovaScenarioSnapshot',
    'Get-CaldovaScenarioSnapshot',
    'Remove-CaldovaScenarioSnapshot',
    'Start-CaldovaFailureTraffic',
    'Wait-CaldovaQuizLaunchAlert',
    'Test-CaldovaScenarioOneRuleFingerprint'
)
