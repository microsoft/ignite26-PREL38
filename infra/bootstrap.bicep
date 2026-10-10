targetScope = 'subscription'

param location string

@minValue(1)
@maxValue(999)
param learnerNumber int

@minLength(4)
@maxLength(32)
param deploymentToken string

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

module registry 'modules/registry.bicep' = {
  name: 'registry'
  scope: resourceGroup
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

output resourceGroupName string = resourceGroup.name
output registryName string = registry.outputs.registryName
output registryLoginServer string = registry.outputs.loginServer
