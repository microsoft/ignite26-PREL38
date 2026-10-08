param location string
param resourceToken string
param tags object = {}
param subnetId string
param logAnalyticsWorkspaceId string
param adminSshPublicKey string
param adminUsername string = 'caldova'
param postgresHost string
param postgresDatabase string
param postgresAdministratorLogin string
param keyVaultName string

var cloudInitTemplate = loadTextContent('../../src/reporting-worker/cloud-init.yaml')
var cloudInit = replace(
  replace(
    replace(
      replace(cloudInitTemplate, '@@POSTGRES_HOST@@', postgresHost),
      '@@POSTGRES_DATABASE@@',
      postgresDatabase
    ),
    '@@POSTGRES_USER@@',
    postgresAdministratorLogin
  ),
  '@@KEY_VAULT_NAME@@',
  keyVaultName
)

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-caldova-worker-${resourceToken}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

resource exportDisk 'Microsoft.Compute/disks@2024-03-02' = {
  name: 'disk-caldova-exports-${resourceToken}'
  location: location
  tags: union(tags, {
    workload: 'caldova-reporting'
    purpose: 'exports'
  })
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: 8
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: 'vm-caldova-worker-${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
      dataDisks: [
        {
          lun: 0
          name: exportDisk.name
          createOption: 'Attach'
          managedDisk: {
            id: exportDisk.id
            storageAccountType: 'Standard_LRS'
          }
          diskSizeGB: 8
        }
      ]
    }
    osProfile: {
      computerName: 'caldova-worker'
      adminUsername: adminUsername
      customData: base64(cloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource monitorAgent 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: vm
  name: 'AzureMonitorLinuxAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {}
  }
}

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-caldova-worker-${resourceToken}'
  location: location
  tags: tags
  properties: {
    dataSources: {
      syslog: [
        {
          name: 'caldova-syslog'
          facilityNames: [
            'daemon'
            'local0'
            'local1'
          ]
          logLevels: [
            'Info'
            'Notice'
            'Warning'
            'Error'
            'Critical'
            'Alert'
            'Emergency'
          ]
          streams: [
            'Microsoft-Syslog'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'workspace'
          workspaceResourceId: logAnalyticsWorkspaceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Syslog'
        ]
        destinations: [
          'workspace'
        ]
      }
    ]
  }
}

resource association 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'configurationAccessEndpoint'
  scope: vm
  properties: {
    dataCollectionRuleId: dataCollectionRule.id
  }
}

output vmName string = vm.name
output vmId string = vm.id
output vmPrincipalId string = vm.identity.principalId
output exportDiskName string = exportDisk.name
