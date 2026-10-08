param location string
param tags object = {}

@minValue(1)
@maxValue(999)
param learnerNumber int

param preconfiguredIdentityId string
param configuredIdentityId string
param appInsightsAppId string
@secure()
param appInsightsConnectionString string
param appInsightsId string
param managedResourceGroupId string
param portalContainerAppName string
param apiContainerAppName string
param postgresServerName string

var preconfiguredAgentName = 'sre-caldova-prerun-user${learnerNumber}'
var configuredAgentName = 'sre-caldova-config-user${learnerNumber}'
var identityIds = [
  preconfiguredIdentityId
  configuredIdentityId
]
var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'
var vmContributorRoleId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var sreAgentAdminRoleId = 'e79298df-d852-4c6d-84f9-5d13249d1e55'

resource preconfiguredIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: last(split(preconfiguredIdentityId, '/'))
}

resource configuredIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: last(split(configuredIdentityId, '/'))
}

var identityPrincipalIds = [
  preconfiguredIdentity.properties.principalId
  configuredIdentity.properties.principalId
]

#disable-next-line BCP081
resource preconfiguredAgent 'Microsoft.App/agents@2025-05-01-preview' = {
  name: preconfiguredAgentName
  location: location
  tags: union(tags, {
    path: 'preconfigured'
    'hidden-link: /app-insights-resource-id': appInsightsId
  })
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${preconfiguredIdentityId}': {}
    }
  }
  properties: {
    knowledgeGraphConfiguration: {
      managedResources: [
        managedResourceGroupId
      ]
      identity: preconfiguredIdentityId
    }
    actionConfiguration: {
      mode: 'autonomous'
      identity: preconfiguredIdentityId
      accessLevel: 'High'
    }
    defaultModel: {
      name: 'Automatic'
      provider: 'Anthropic'
    }
    upgradeChannel: 'Preview'
    experimentalSettings: {
      EnableWorkspaceTools: true
    }
    incidentManagementConfiguration: {
      type: 'AzMonitor'
      connectionName: 'azmonitor'
    }
    mcpServers: []
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: appInsightsAppId
        connectionString: appInsightsConnectionString
      }
    }
  }
}

#disable-next-line BCP081
resource configuredAgent 'Microsoft.App/agents@2025-05-01-preview' = {
  name: configuredAgentName
  location: location
  tags: union(tags, {
    path: 'configure'
    'hidden-link: /app-insights-resource-id': appInsightsId
  })
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${configuredIdentityId}': {}
    }
  }
  properties: {
    knowledgeGraphConfiguration: {
      managedResources: [
        managedResourceGroupId
      ]
      identity: configuredIdentityId
    }
    actionConfiguration: {
      mode: 'supervised'
      identity: configuredIdentityId
      accessLevel: 'Medium'
    }
    defaultModel: {
      name: 'Automatic'
      provider: 'Anthropic'
    }
    upgradeChannel: 'Preview'
    experimentalSettings: {
      EnableWorkspaceTools: true
    }
    incidentManagementConfiguration: {
      type: 'AzMonitor'
      connectionName: 'azmonitor'
    }
    mcpServers: []
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: appInsightsAppId
        connectionString: appInsightsConnectionString
      }
    }
  }
}

resource preconfiguredAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(preconfiguredAgent.id, deployer().objectId, sreAgentAdminRoleId)
  scope: preconfiguredAgent
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sreAgentAdminRoleId)
    principalId: deployer().objectId
  }
}

resource configuredAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(configuredAgent.id, deployer().objectId, sreAgentAdminRoleId)
  scope: configuredAgent
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sreAgentAdminRoleId)
    principalId: deployer().objectId
  }
}

resource readerAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (identityId, index) in identityIds: {
  name: guid(resourceGroup().id, identityId, readerRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: identityPrincipalIds[index]
    principalType: 'ServicePrincipal'
  }
}]

resource monitoringReaderAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (identityId, index) in identityIds: {
  name: guid(resourceGroup().id, identityId, monitoringReaderRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRoleId)
    principalId: identityPrincipalIds[index]
    principalType: 'ServicePrincipal'
  }
}]

resource networkContributorAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (identityId, index) in identityIds: {
  name: guid(resourceGroup().id, identityId, networkContributorRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalId: identityPrincipalIds[index]
    principalType: 'ServicePrincipal'
  }
}]

resource vmContributorAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (identityId, index) in identityIds: {
  name: guid(resourceGroup().id, identityId, vmContributorRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmContributorRoleId)
    principalId: identityPrincipalIds[index]
    principalType: 'ServicePrincipal'
  }
}]

resource portalApp 'Microsoft.App/containerApps@2024-03-01' existing = {
  name: portalContainerAppName
}

resource apiApp 'Microsoft.App/containerApps@2024-03-01' existing = {
  name: apiContainerAppName
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: postgresServerName
}

resource portalContributorAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (identityId, index) in identityIds: {
  name: guid(portalApp.id, identityId, contributorRoleId)
  scope: portalApp
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: identityPrincipalIds[index]
    principalType: 'ServicePrincipal'
  }
}]

resource apiContributorAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (identityId, index) in identityIds: {
  name: guid(apiApp.id, identityId, contributorRoleId)
  scope: apiApp
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: identityPrincipalIds[index]
    principalType: 'ServicePrincipal'
  }
}]

resource postgresContributorAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (identityId, index) in identityIds: {
  name: guid(postgres.id, identityId, contributorRoleId)
  scope: postgres
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: identityPrincipalIds[index]
    principalType: 'ServicePrincipal'
  }
}]

output preconfiguredAgentName string = preconfiguredAgent.name
output configuredAgentName string = configuredAgent.name
output preconfiguredAgentId string = preconfiguredAgent.id
output configuredAgentId string = configuredAgent.id
output preconfiguredAgentPortalUrl string = 'https://sre.azure.com/agents${preconfiguredAgent.id}'
output configuredAgentPortalUrl string = 'https://sre.azure.com/agents${configuredAgent.id}'
