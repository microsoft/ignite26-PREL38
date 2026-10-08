param location string
param userLabel string
param resourceToken string
param tags object = {}

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-caldova-app-${resourceToken}'
  location: location
  tags: tags
}

resource preconfiguredAgentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-caldova-prerun-${userLabel}'
  location: location
  tags: tags
}

resource configuredAgentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-caldova-config-${userLabel}'
  location: location
  tags: tags
}

output appIdentityId string = appIdentity.id
output appIdentityPrincipalId string = appIdentity.properties.principalId
output preconfiguredAgentIdentityId string = preconfiguredAgentIdentity.id
output configuredAgentIdentityId string = configuredAgentIdentity.id
