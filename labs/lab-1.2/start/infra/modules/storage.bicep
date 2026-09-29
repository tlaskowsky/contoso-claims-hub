// =============================================================================
// Storage account (shared-key access disabled; Entra ID only)
// Used twice: claim documents [LAB 2.1] and Functions runtime [LAB 2.1 / 2.3]
// =============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param name string
param publicNetworkAccess bool
param containerNames array
@description('Move blobs to Cool after 30 days (claim documents only).')
param enableLifecyclePolicy bool = false
param roleAssignments array = []

resource st 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    networkAcls: {
      defaultAction: publicNetworkAccess ? 'Allow' : 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: st
  name: 'default'
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for c in containerNames: {
  parent: blobService
  name: c
  properties: {
    publicAccess: 'None'
  }
}]

resource lifecycle 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = if (enableLifecyclePolicy) {
  parent: st
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'cool-after-30-days'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: [
                'blockBlob'
              ]
            }
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterModificationGreaterThan: 30
                }
              }
            }
          }
        }
      ]
    }
  }
}

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for r in roleAssignments: {
  name: guid(st.id, r.principalId, r.roleDefinitionId)
  scope: st
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', r.roleDefinitionId)
    principalId: r.principalId
    principalType: r.principalType
  }
}]

output id string = st.id
output name string = st.name
output blobEndpoint string = st.properties.primaryEndpoints.blob
