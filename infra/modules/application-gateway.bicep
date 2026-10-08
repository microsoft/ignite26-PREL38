param location string
param resourceToken string
param tags object = {}
param subnetId string
param portalFqdn string
param logAnalyticsWorkspaceId string

var gatewayName = 'agw-caldova-${resourceToken}'

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-caldova-${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'caldova-${resourceToken}'
    }
  }
}

resource gateway 'Microsoft.Network/applicationGateways@2024-05-01' = {
  name: gatewayName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 1
    }
    gatewayIPConfigurations: [
      {
        name: 'gateway-ip'
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'public'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'http'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'portal'
        properties: {
          backendAddresses: [
            {
              fqdn: portalFqdn
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: 'portal-health'
        properties: {
          protocol: 'Https'
          path: '/health'
          interval: 30
          timeout: 20
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'portal-https'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 30
          pickHostNameFromBackendAddress: true
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', gatewayName, 'portal-health')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'public-http'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', gatewayName, 'public')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', gatewayName, 'http')
          }
          protocol: 'Http'
          requireServerNameIndication: false
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'portal'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', gatewayName, 'public-http')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', gatewayName, 'portal')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', gatewayName, 'portal-https')
          }
        }
      }
    ]
    enableHttp2: true
  }
}

resource gatewayDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'caldova-quiz-request-evidence'
  scope: gateway
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
      }
    ]
    metrics: []
  }
}

output gatewayName string = gateway.name
output gatewayId string = gateway.id
output publicIpAddress string = publicIp.properties.ipAddress
output publicFqdn string = publicIp.properties.dnsSettings.fqdn
output publicEndpoint string = 'http://${publicIp.properties.dnsSettings.fqdn}'
