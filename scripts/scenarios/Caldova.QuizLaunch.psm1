Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\Caldova.Lifecycle.psm1') -Force

$script:FilterName = 'caldova-azure-monitor-response'
$script:AgentApiVersion = '2025-05-01-preview'
$script:AlertsApiVersion = '2019-03-01'
$script:RuleName = 'caldova-quiz-launch-scenario-1'
$script:RulePriority = 220
$script:RuleDescription = 'Caldova learner scenario 1'
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
        '--tag', 'solution=caldova',
        '--output', 'json'
    ) -ReturnJson) | Where-Object {
        $_.name -like "$NamePrefix*" -and
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
        @($_.delegations) | Where-Object { $_.serviceName -eq 'Microsoft.App/environments' -or $_.properties.serviceName -eq 'Microsoft.App/environments' }
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
    $command = 'node -e "Promise.all([fetch(''http://127.0.0.1:8080/health''), fetch(process.env.CALDOVA_API_BASE_URL + ''/quiz/OPS-201-M1'')]).then(rs => { if (rs.some(r => !r.ok)) process.exit(2); console.log(''CALDOVA_DIRECT_OK'') }).catch(e => { console.error(e.message); process.exit(3) })"'
    $output = Invoke-CaldovaAz -Arguments @(
        'containerapp', 'exec',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $portal.name,
        '--command', $command
    )
    if (($output | Out-String) -notmatch 'CALDOVA_DIRECT_OK') {
        throw 'The portal or private quiz service did not return a successful response inside the application environment. Restore the application baseline before starting.'
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
        $probe = Invoke-CaldovaWebProbe -Uri "$Uri?scenarioPoll=$([DateTime]::UtcNow.Ticks)"
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
        [Parameter(Mandatory)][bool]$Enabled
    )
    $spec = ConvertFrom-CaldovaFilter -Resource $Resource
    $spec.isEnabled = $Enabled
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($spec | ConvertTo-Json -Depth 20 -Compress)))
    $body = @{ properties = @{ value = $encoded } } | ConvertTo-Json -Depth 5 -Compress
    $url = "https://management.azure.com/subscriptions/$($Context.State.subscriptionId)/resourceGroups/$($Context.State.resourceGroupName)/providers/Microsoft.App/agents/$AgentName/incidentFilters/$($script:FilterName)?api-version=$($script:AgentApiVersion)"
    Invoke-CaldovaAz -Arguments @('rest', '--method', 'put', '--url', $url, '--body', $body, '--output', 'none') | Out-Null
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
        throw "Azure Monitor alert '$($Context.AlertName)' is disabled. Enable the one-minute learner-visible alert before starting."
    }
    $frequency = if ($alert.PSObject.Properties.Name -contains 'evaluationFrequency') { [string]$alert.evaluationFrequency } else { [string]$alert.properties.evaluationFrequency }
    if ($frequency -notin @('PT1M', '0:01:00', '00:01:00')) {
        throw "Azure Monitor alert '$($Context.AlertName)' must evaluate every minute; current value is '$frequency'. Redeploy the workshop baseline."
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
    Set-CaldovaFilterEnabled -Context $Context -AgentName $Context.SelectedAgentName -Resource $selected -Enabled $true
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
    $deadline = [DateTime]::UtcNow.AddMinutes(8)
    do {
        $url = "https://management.azure.com/subscriptions/$($Context.State.subscriptionId)/providers/Microsoft.AlertsManagement/alerts?api-version=$($script:AlertsApiVersion)&timeRange=1h"
        $result = Invoke-CaldovaAz -Arguments @('rest', '--method', 'get', '--url', $url, '--output', 'json') -ReturnJson
        $match = @($result.value) | Where-Object {
            $_.properties.essentials.alertRule -match [regex]::Escape($Context.AlertName) -and
            $_.properties.essentials.monitorCondition -eq 'Fired' -and
            [DateTime]$_.properties.essentials.startDateTime -ge $NotBeforeUtc
        } | Select-Object -First 1
        if ($null -ne $match) { return $match }
        Start-Sleep -Seconds 15
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Azure Monitor did not report fresh alert '$($Context.AlertName)' within 8 minutes. Confirm the one-minute rule and generated learner traffic. The exercise remains active; use Reset after investigation."
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
    $path = Get-CaldovaAppPath -Context $Context
    $existing = @($path.Nsg.securityRules) | Where-Object { $_.name -eq $script:RuleName }
    if ($existing.Count -gt 0) {
        $rule = $existing[0]
        if (-not (Test-CaldovaScenarioOneRuleFingerprint -Rule $rule -ExpectedSourcePrefix $path.SourcePrefix)) {
            throw "Rule '$($script:RuleName)' already exists but is not the learner exercise rule. Refusing to overwrite it."
        }
        return
    }
    Invoke-CaldovaAz -Arguments @(
        'network', 'nsg', 'rule', 'create',
        '--resource-group', $Context.State.resourceGroupName,
        '--nsg-name', $path.Nsg.name,
        '--name', $script:RuleName,
        '--priority', [string]$script:RulePriority,
        '--direction', 'Inbound',
        '--access', 'Deny',
        '--protocol', 'Tcp',
        '--source-address-prefixes', $path.SourcePrefix,
        '--source-port-ranges', '*',
        '--destination-address-prefixes', '*',
        '--destination-port-ranges', '443',
        '--description', $script:RuleDescription,
        '--output', 'none'
    ) | Out-Null
}

function Get-CaldovaRuleValues {
    param(
        [Parameter(Mandatory)]$Rule,
        [Parameter(Mandatory)][string]$SingleName,
        [Parameter(Mandatory)][string]$PluralName
    )

    if ($Rule.PSObject.Properties.Name -contains $PluralName -and $null -ne $Rule.$PluralName) {
        return @($Rule.$PluralName)
    }
    if ($Rule.PSObject.Properties.Name -contains $SingleName -and $null -ne $Rule.$SingleName) {
        return @($Rule.$SingleName)
    }
    return @()
}

function Test-CaldovaScenarioOneRuleFingerprint {
    param(
        [Parameter(Mandatory)]$Rule,
        [Parameter(Mandatory)][string]$ExpectedSourcePrefix
    )

    $sources = @(Get-CaldovaRuleValues -Rule $Rule -SingleName 'sourceAddressPrefix' -PluralName 'sourceAddressPrefixes')
    $sourcePorts = @(Get-CaldovaRuleValues -Rule $Rule -SingleName 'sourcePortRange' -PluralName 'sourcePortRanges')
    $destinations = @(Get-CaldovaRuleValues -Rule $Rule -SingleName 'destinationAddressPrefix' -PluralName 'destinationAddressPrefixes')
    $destinationPorts = @(Get-CaldovaRuleValues -Rule $Rule -SingleName 'destinationPortRange' -PluralName 'destinationPortRanges')
    return (
        $Rule.name -ceq $script:RuleName -and
        [int]$Rule.priority -eq $script:RulePriority -and
        $Rule.direction -ceq 'Inbound' -and
        $Rule.access -ceq 'Deny' -and
        $Rule.protocol -ceq 'Tcp' -and
        $sources.Count -eq 1 -and $sources[0] -ceq $ExpectedSourcePrefix -and
        $sourcePorts.Count -eq 1 -and $sourcePorts[0] -ceq '*' -and
        $destinations.Count -eq 1 -and $destinations[0] -ceq '*' -and
        $destinationPorts.Count -eq 1 -and $destinationPorts[0] -ceq '443' -and
        $Rule.description -ceq $script:RuleDescription
    )
}

function Restore-CaldovaScenarioOne {
    param([Parameter(Mandatory)]$Context)
    $snapshot = Get-CaldovaScenarioSnapshot -Context $Context
    Remove-CaldovaScenarioOneRule -Context $Context -NsgName $snapshot.nsgName -ExpectedSourcePrefix $snapshot.sourcePrefix
}

function Remove-CaldovaScenarioOneRule {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$NsgName,
        [Parameter(Mandatory)][string]$ExpectedSourcePrefix
    )
    $nsg = Invoke-CaldovaAz -Arguments @(
        'network', 'nsg', 'show',
        '--resource-group', $Context.State.resourceGroupName,
        '--name', $NsgName,
        '--output', 'json'
    ) -ReturnJson
    $matchingRules = @($nsg.securityRules | Where-Object { $_.name -eq $script:RuleName })
    if ($matchingRules.Count -eq 0) { return }
    if ($matchingRules.Count -ne 1 -or
        -not (Test-CaldovaScenarioOneRuleFingerprint -Rule $matchingRules[0] -ExpectedSourcePrefix $ExpectedSourcePrefix)) {
        throw "Rule '$($script:RuleName)' exists but does not exactly match the planted scenario fingerprint. Refusing to delete it. Compare its priority, direction, access, protocol, prefixes, ports, and description with the facilitator baseline."
    }
    Invoke-CaldovaAz -Arguments @(
      'network', 'nsg', 'rule', 'delete',
      '--resource-group', $Context.State.resourceGroupName,
      '--nsg-name', $NsgName,
      '--name', $script:RuleName,
      '--output', 'none'
    ) | Out-Null
}

function Get-CaldovaGatewayProbe {
    param([Parameter(Mandatory)]$Context)
    $gateway = Get-CaldovaGateway -Context $Context
    $probeIds = @($gateway.backendHttpSettingsCollection.probe.id) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
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
                $path = Get-CaldovaAppPath -Context $context
                Save-CaldovaScenarioSnapshot -Context $context -Snapshot @{
                    kind = 'nsg-rule'
                    nsgName = $path.Nsg.name
                    ruleName = $script:RuleName
                    ruleExisted = $false
                    sourcePrefix = $path.SourcePrefix
                    priority = $script:RulePriority
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
            Write-Host '::phase::alert::88::Waiting for the one-minute Azure Monitor rule'
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
            Assert-CaldovaRecovery -Context $context
        }
        'Reset' {
            Write-Host '::phase::baseline::45::Restoring the exact saved baseline'
            $snapshotPath = Get-CaldovaScenarioSnapshotPath -Context $context
            if (Test-Path -LiteralPath $snapshotPath) {
                if ($ScenarioNumber -eq 1) { Restore-CaldovaScenarioOne -Context $context }
                elseif ($ScenarioNumber -eq 2) { Restore-CaldovaScenarioTwo -Context $context }
                else { Restore-CaldovaScenarioThree -Context $context }
            } elseif ($ScenarioNumber -eq 1) {
                # Reset owns only the exact planted rule and never touches NRMS rules.
                $path = Get-CaldovaAppPath -Context $context
                Remove-CaldovaScenarioOneRule -Context $context -NsgName $path.Nsg.name -ExpectedSourcePrefix $path.SourcePrefix
            }
            $recovery = Assert-CaldovaRecovery -Context $context
            Write-Host '::phase::ownership::78::Restoring baseline response-plan ownership'
            Restore-CaldovaOwnership -Context $context
            Remove-CaldovaScenarioSnapshot -Context $context
            [pscustomobject]@{ reset = $true; publicStatus = $recovery.publicStatus; backendHealthy = $recovery.backendHealthy }
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
