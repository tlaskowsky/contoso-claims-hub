// =============================================================================
// Network - VNet, subnets, private DNS zones   [pre-provisioned; used in LAB 2.4]
// NSGs intentionally omitted (awareness-only topic).
// No zones for Service Bus (Standard tier - no Private Endpoint) or App
// Configuration (kept public so ARM can deploy key-values). Training trade-offs.
// =============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param vnetName string
param addressPrefix string = '10.10.0.0/16'

var privateDnsZoneNames = [
  'privatelink.documents.azure.com'                        // 0 Cosmos DB (NoSQL)
  'privatelink.blob.${environment().suffixes.storage}'     // 1 Storage blob
  'privatelink.queue.${environment().suffixes.storage}'    // 2 Storage queue
  'privatelink.table.${environment().suffixes.storage}'    // 3 Storage table
  'privatelink.vaultcore.azure.net'                        // 4 Key Vault
]

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-app' // App Service VNet integration (outbound)
        properties: {
          addressPrefix: '10.10.1.0/24'
          delegations: [
            {
              name: 'delegation-web'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'snet-func-validation' // Flex Consumption VNet integration
        properties: {
          addressPrefix: '10.10.2.0/24'
          delegations: [
            {
              name: 'delegation-app'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'snet-func-processing' // Flex Consumption VNet integration
        properties: {
          addressPrefix: '10.10.3.0/24'
          delegations: [
            {
              name: 'delegation-app'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'snet-pe' // Private Endpoints
        properties: {
          addressPrefix: '10.10.10.0/24'
        }
      }
    ]
  }
}

resource dnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in privateDnsZoneNames: {
  name: zone
  location: 'global'
  tags: tags
}]

resource dnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, i) in privateDnsZoneNames: {
  parent: dnsZones[i]
  name: 'link-${vnetName}'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}]

output vnetId string = vnet.id
output subnetIds object = {
  app: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-app')
  funcValidation: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-func-validation')
  funcProcessing: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-func-processing')
  privateEndpoints: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-pe')
}
output dnsZoneIds object = {
  cosmos: dnsZones[0].id
  blob: dnsZones[1].id
  queue: dnsZones[2].id
  table: dnsZones[3].id
  keyVault: dnsZones[4].id
}
