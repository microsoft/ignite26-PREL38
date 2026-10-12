targetScope = 'resourceGroup'

@minLength(5)
@description('Name of the event-managed Azure Container Registry.')
param registryName string

@description('Principal ID of the learner application identity.')
param appIdentityPrincipalId string

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource registryPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, appIdentityPrincipalId, 'AcrPull')
  scope: registry
  properties: {
    principalId: appIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    )
  }
}

output registryName string = registry.name
output loginServer string = registry.properties.loginServer
