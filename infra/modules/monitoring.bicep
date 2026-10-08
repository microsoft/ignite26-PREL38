param location string
param resourceToken string
param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-caldova-${resourceToken}'
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-caldova-${resourceToken}'
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    IngestionMode: 'LogAnalytics'
  }
}

output logAnalyticsWorkspaceId string = workspace.id
output logAnalyticsWorkspaceName string = workspace.name
output logAnalyticsCustomerId string = workspace.properties.customerId
@secure()
output logAnalyticsSharedKey string = workspace.listKeys().primarySharedKey
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appInsightsAppId string = appInsights.properties.AppId
@secure()
output appInsightsConnectionString string = appInsights.properties.ConnectionString
