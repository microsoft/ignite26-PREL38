[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$Location,
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [Parameter(Mandatory)][string]$DeploymentToken,
    [Parameter(Mandatory)][string]$PortalImage,
    [Parameter(Mandatory)][string]$ApiImage,
    [Parameter(Mandatory)][string]$ApiLatencyImage,
    [Parameter(Mandatory)][string]$ImageRegistrySubscriptionId,
    [Parameter(Mandatory)][string]$ImageRegistryResourceGroupName,
    [Parameter(Mandatory)][string]$ImageRegistryName,
    [ValidateRange(100, 10000)][int]$QuizLatencyThresholdMs = 900
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Caldova.Lifecycle.psm1') -Force

function Get-SingleCaldovaResource {
    param(
        [Parameter(Mandatory)][string]$ResourceType,
        [Parameter(Mandatory)][string]$NamePrefix
    )

    $resources = @(
        Invoke-CaldovaAz -Arguments @(
            'resource', 'list',
            '--resource-group', $ResourceGroupName,
            '--resource-type', $ResourceType,
            '--query', "[?starts_with(name, '$NamePrefix')].{id:id,name:name}",
            '--output', 'json'
        ) -ReturnJson
    )
    if ($resources.Count -ne 1) {
        throw "Expected exactly one '$ResourceType' resource beginning with '$NamePrefix' in '$ResourceGroupName'; found $($resources.Count). The Skillable ARM deployment is incomplete or ambiguous."
    }
    return $resources[0]
}

Assert-CaldovaLearnerInput -LearnerNumber $LearnerNumber -DeploymentToken $DeploymentToken
Assert-CaldovaCommand -Name 'az'

Invoke-CaldovaAz -Arguments @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
$resourceGroup = Invoke-CaldovaAz -Arguments @(
    'group', 'show',
    '--name', $ResourceGroupName,
    '--output', 'json'
) -ReturnJson

$expectedTags = @{
    solution = 'caldova'
    session = 'PREL38'
    learner = "user$LearnerNumber"
    deploymentToken = $DeploymentToken
}
foreach ($tag in $expectedTags.GetEnumerator()) {
    if ($resourceGroup.tags.($tag.Key) -ne $tag.Value) {
        throw "Resource group '$ResourceGroupName' does not have expected tag '$($tag.Key)=$($tag.Value)'. Refusing to initialize learner state for the wrong deployment."
    }
}

$portal = Get-SingleCaldovaResource -ResourceType 'Microsoft.App/containerApps' -NamePrefix 'ca-caldova-portal-'
$api = Get-SingleCaldovaResource -ResourceType 'Microsoft.App/containerApps' -NamePrefix 'ca-caldova-api-'
$publicIp = Get-SingleCaldovaResource -ResourceType 'Microsoft.Network/publicIPAddresses' -NamePrefix 'pip-caldova-'
$workspace = Get-SingleCaldovaResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -NamePrefix 'log-caldova-'
$appInsights = Get-SingleCaldovaResource -ResourceType 'Microsoft.Insights/components' -NamePrefix 'appi-caldova-'
$postgres = Get-SingleCaldovaResource -ResourceType 'Microsoft.DBforPostgreSQL/flexibleServers' -NamePrefix 'psql-caldova-'
$reportingWorker = Get-SingleCaldovaResource -ResourceType 'Microsoft.Compute/virtualMachines' -NamePrefix 'vm-caldova-report-'
$appIdentity = Get-SingleCaldovaResource -ResourceType 'Microsoft.ManagedIdentity/userAssignedIdentities' -NamePrefix 'id-caldova-app-'

$portalDetails = Invoke-CaldovaAz -Arguments @(
    'resource', 'show', '--ids', $portal.id,
    '--api-version', '2024-03-01',
    '--output', 'json'
) -ReturnJson
$apiDetails = Invoke-CaldovaAz -Arguments @(
    'resource', 'show', '--ids', $api.id,
    '--api-version', '2024-03-01',
    '--output', 'json'
) -ReturnJson
$publicIpDetails = Invoke-CaldovaAz -Arguments @(
    'resource', 'show', '--ids', $publicIp.id,
    '--api-version', '2024-05-01',
    '--output', 'json'
) -ReturnJson
$appIdentityDetails = Invoke-CaldovaAz -Arguments @(
    'resource', 'show', '--ids', $appIdentity.id,
    '--api-version', '2023-01-31',
    '--output', 'json'
) -ReturnJson

$portalFqdn = $portalDetails.properties.configuration.ingress.fqdn
$apiFqdn = $apiDetails.properties.configuration.ingress.fqdn
$publicFqdn = $publicIpDetails.properties.dnsSettings.fqdn
$appIdentityPrincipalId = $appIdentityDetails.properties.principalId
foreach ($requiredValue in @{
    portalFqdn = $portalFqdn
    apiFqdn = $apiFqdn
    publicFqdn = $publicFqdn
    appIdentityPrincipalId = $appIdentityPrincipalId
}.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace($requiredValue.Value)) {
        throw "The deployed resource did not expose '$($requiredValue.Key)'. Wait for the Skillable ARM deployment to finish successfully before initializing state."
    }
}

$registryId = "/subscriptions/$ImageRegistrySubscriptionId/resourceGroups/$ImageRegistryResourceGroupName/providers/Microsoft.ContainerRegistry/registries/$ImageRegistryName"
$registry = Invoke-CaldovaAz -Arguments @(
    'resource', 'show', '--ids', $registryId,
    '--api-version', '2023-07-01',
    '--output', 'json'
) -ReturnJson
$registryLoginServer = $registry.properties.loginServer
if ([string]::IsNullOrWhiteSpace($registryLoginServer)) {
    throw "Event-managed registry '$registryId' did not expose a login server."
}
foreach ($image in @($PortalImage, $ApiImage, $ApiLatencyImage)) {
    if (-not $image.StartsWith("$registryLoginServer/", [StringComparison]::OrdinalIgnoreCase) -or $image -notmatch '@sha256:[0-9a-fA-F]{64}$') {
        throw "Image '$image' must be digest-pinned in the event-managed registry '$registryLoginServer'."
    }
}
if ($ApiImage -eq $ApiLatencyImage) {
    throw 'ApiImage and ApiLatencyImage must identify different immutable images.'
}

$preconfiguredAgentName = "sre-caldova-prerun-user$LearnerNumber"
$configuredAgentName = "sre-caldova-config-user$LearnerNumber"
$preconfiguredAgentId = "$($resourceGroup.id)/providers/Microsoft.App/agents/$preconfiguredAgentName"
$configuredAgentId = "$($resourceGroup.id)/providers/Microsoft.App/agents/$configuredAgentName"
foreach ($agentId in @($preconfiguredAgentId, $configuredAgentId)) {
    Invoke-CaldovaAz -Arguments @(
        'resource', 'show', '--ids', $agentId,
        '--api-version', '2025-05-01-preview',
        '--output', 'none'
    ) | Out-Null
}

$state = @{
    schemaVersion = 2
    subscriptionId = $SubscriptionId
    location = $Location
    learnerNumber = $LearnerNumber
    deploymentToken = $DeploymentToken
    deploymentName = 'skillable-arm'
    resourceGroupName = $ResourceGroupName
    resourceGroupId = $resourceGroup.id
    publicEndpoint = "http://$publicFqdn"
    portalFqdn = $portalFqdn
    apiFqdn = $apiFqdn
    apiHealthyImage = $ApiImage
    apiLatencyImage = $ApiLatencyImage
    registryName = $ImageRegistryName
    registryLoginServer = $registryLoginServer
    imageRegistryResourceId = $registryId
    appIdentityPrincipalId = $appIdentityPrincipalId
    quizLatencyThresholdMs = $QuizLatencyThresholdMs
    logAnalyticsWorkspaceName = $workspace.name
    applicationInsightsName = $appInsights.name
    postgresServerName = $postgres.name
    reportingWorkerName = $reportingWorker.name
    preconfiguredAgentName = $preconfiguredAgentName
    configuredAgentName = $configuredAgentName
    preconfiguredAgentPortalUrl = "https://sre.azure.com/agents$preconfiguredAgentId"
    configuredAgentPortalUrl = "https://sre.azure.com/agents$configuredAgentId"
}
$statePath = Save-CaldovaState -LearnerNumber $LearnerNumber -State $state

Write-Host "Skillable deployment state initialized for user$LearnerNumber."
Write-Host "Resource group: $ResourceGroupName"
Write-Host "Public endpoint: $($state.publicEndpoint)"
Write-Host "State: $statePath"
