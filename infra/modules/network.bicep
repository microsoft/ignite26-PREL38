param location string
param resourceToken string
param tags object = {}

resource appNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-caldova-app-${resourceToken}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowApplicationGatewayToContainerApps'
        properties: {
          // Keep learner-owned rules below the NRMS-reserved 101-109 range and
          // leave a bounded exercise slot at priority 220.
          priority: 300
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.38.2.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

resource vmNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-caldova-worker-${resourceToken}'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-caldova-${resourceToken}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.38.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-containerapps'
        properties: {
          addressPrefix: '10.38.0.0/23'
          networkSecurityGroup: {
            id: appNsg.id
          }
          delegations: [
            {
              name: 'container-apps'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'snet-appgateway'
        properties: {
          addressPrefix: '10.38.2.0/24'
        }
      }
      {
        name: 'snet-worker'
        properties: {
          addressPrefix: '10.38.3.0/24'
          networkSecurityGroup: {
            id: vmNsg.id
          }
        }
      }
      {
        name: 'snet-postgres'
        properties: {
          addressPrefix: '10.38.4.0/24'
          delegations: [
            {
              name: 'postgres-flexible-server'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

resource postgresPrivateDns 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'private.postgres.database.azure.com'
  location: 'global'
  tags: tags
}

resource postgresPrivateDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: postgresPrivateDns
  name: 'link-caldova-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

output vnetId string = vnet.id
output containerAppsSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-containerapps')
output applicationGatewaySubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-appgateway')
output vmSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-worker')
output postgresSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-postgres')
output postgresPrivateDnsZoneId string = postgresPrivateDns.id
output appNsgName string = appNsg.name
output vmNsgName string = vmNsg.name
