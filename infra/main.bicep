targetScope = 'subscription'

@description('Azure region for the learner environment.')
param location string

@minValue(1)
@maxValue(999)
@description('Skillable learner number used in userN resource names.')
param learnerNumber int

@minLength(4)
@maxLength(32)
@description('Non-secret token that makes learner resource names unique.')
param deploymentToken string

@minLength(1)
@description('Caldova portal container image.')
param portalImage string

@minLength(1)
@description('Healthy Caldova API container image used for the initial revision and reset.')
param apiImage string

@minLength(1)
@description('Prebuilt Caldova API image with elevated quiz and assessment response latency.')
param apiLatencyImage string

@minValue(100)
@maxValue(10000)
@description('p95 quiz/API response-time threshold in milliseconds.')
param quizLatencyThresholdMs int = 900

@secure()
@minLength(16)
@description('PostgreSQL administrator password supplied at deployment time.')
param postgresAdminPassword string

@minLength(1)
@description('SSH public key for the Linux reporting-worker VM.')
param vmAdminSshPublicKey string

@description('PostgreSQL region. Override only when the primary location does not support the selected SKU.')
param postgresLocation string = location

var userLabel = 'user${learnerNumber}'
var normalizedToken = toLower(replace(replace(deploymentToken, '-', ''), '_', ''))
var resourceToken = take('${normalizedToken}${uniqueString(subscription().id, deploymentToken, string(learnerNumber))}', 10)
var resourceGroupName = 'rg-caldova-${userLabel}-${resourceToken}'
var tags = {
  solution: 'caldova'
  session: 'PREL38'
  learner: userLabel
  deploymentToken: deploymentToken
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: resourceGroup
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

module identities 'modules/identities.bicep' = {
  name: 'identities'
  scope: resourceGroup
  params: {
    location: location
    userLabel: userLabel
    resourceToken: resourceToken
    tags: tags
  }
}

module registry 'modules/registry.bicep' = {
  name: 'registry'
  scope: resourceGroup
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    appIdentityPrincipalId: identities.outputs.appIdentityPrincipalId
  }
}

module network 'modules/network.bicep' = {
  name: 'network'
  scope: resourceGroup
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

module postgres 'modules/postgres.bicep' = {
  name: 'postgres'
  scope: resourceGroup
  params: {
    location: postgresLocation
    resourceToken: resourceToken
    tags: tags
    delegatedSubnetId: network.outputs.postgresSubnetId
    privateDnsZoneId: network.outputs.postgresPrivateDnsZoneId
    administratorPassword: postgresAdminPassword
  }
}

module reportingWorker 'modules/reporting-worker.bicep' = {
  name: 'reporting-worker'
  scope: resourceGroup
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    subnetId: network.outputs.vmSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    adminSshPublicKey: vmAdminSshPublicKey
    postgresHost: postgres.outputs.fqdn
    postgresDatabase: postgres.outputs.databaseName
    postgresAdministratorLogin: postgres.outputs.administratorLogin
    keyVaultName: 'kv-caldova-${resourceToken}'
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'key-vault'
  scope: resourceGroup
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    appIdentityPrincipalId: identities.outputs.appIdentityPrincipalId
    reportingWorkerPrincipalId: reportingWorker.outputs.vmPrincipalId
    postgresAdminPassword: postgresAdminPassword
  }
}

module containerApps 'modules/container-apps.bicep' = {
  name: 'container-apps'
  scope: resourceGroup
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    infrastructureSubnetId: network.outputs.containerAppsSubnetId
    logAnalyticsCustomerId: monitoring.outputs.logAnalyticsCustomerId
    logAnalyticsSharedKey: monitoring.outputs.logAnalyticsSharedKey
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    appIdentityId: identities.outputs.appIdentityId
    registryServer: registry.outputs.loginServer
    portalImage: portalImage
    apiImage: apiImage
    apiLatencyImage: apiLatencyImage
    postgresHost: postgres.outputs.fqdn
    postgresDatabase: postgres.outputs.databaseName
    postgresAdministratorLogin: postgres.outputs.administratorLogin
    postgresPasswordSecretUri: keyVault.outputs.postgresCredentialUri
  }
}

module containerAppsDns 'modules/container-apps-dns.bicep' = {
  name: 'container-apps-dns'
  scope: resourceGroup
  params: {
    resourceToken: resourceToken
    tags: tags
    defaultDomain: containerApps.outputs.environmentDefaultDomain
    environmentStaticIp: containerApps.outputs.environmentStaticIp
    vnetId: network.outputs.vnetId
  }
}

module applicationGateway 'modules/application-gateway.bicep' = {
  name: 'application-gateway'
  scope: resourceGroup
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    subnetId: network.outputs.applicationGatewaySubnetId
    portalFqdn: containerApps.outputs.portalFqdn
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
  dependsOn: [
    containerAppsDns
  ]
}

module alerts 'modules/alerts.bicep' = {
  name: 'alerts'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    quizLatencyThresholdMs: quizLatencyThresholdMs
  }
}

module sreAgents 'modules/sre-agents.bicep' = {
  name: 'sre-agents'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    learnerNumber: learnerNumber
    preconfiguredIdentityId: identities.outputs.preconfiguredAgentIdentityId
    configuredIdentityId: identities.outputs.configuredAgentIdentityId
    appInsightsAppId: monitoring.outputs.appInsightsAppId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    appInsightsId: monitoring.outputs.appInsightsId
    managedResourceGroupId: resourceGroup.id
    portalContainerAppName: containerApps.outputs.portalName
    apiContainerAppName: containerApps.outputs.apiName
    postgresServerName: postgres.outputs.serverName
  }
}

output resourceGroupName string = resourceGroup.name
output resourceGroupId string = resourceGroup.id
output publicEndpoint string = applicationGateway.outputs.publicEndpoint
output portalFqdn string = containerApps.outputs.portalFqdn
output apiFqdn string = containerApps.outputs.apiFqdn
output apiHealthyImage string = containerApps.outputs.apiHealthyImage
output apiLatencyImage string = containerApps.outputs.apiLatencyImage
output registryName string = registry.outputs.registryName
output registryLoginServer string = registry.outputs.loginServer
output logAnalyticsWorkspaceName string = monitoring.outputs.logAnalyticsWorkspaceName
output applicationInsightsName string = monitoring.outputs.appInsightsName
output postgresServerName string = postgres.outputs.serverName
output reportingWorkerName string = reportingWorker.outputs.vmName
output preconfiguredAgentName string = sreAgents.outputs.preconfiguredAgentName
output configuredAgentName string = sreAgents.outputs.configuredAgentName
output preconfiguredAgentPortalUrl string = sreAgents.outputs.preconfiguredAgentPortalUrl
output configuredAgentPortalUrl string = sreAgents.outputs.configuredAgentPortalUrl
