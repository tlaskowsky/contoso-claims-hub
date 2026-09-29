// =============================================================================
// Key Vault (RBAC authorization) + one application secret   [LAB 1.2]
// =============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param name string
param publicNetworkAccess bool
@secure()
param policyAdminApiKey string
param roleAssignments array = []

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    networkAcls: {
      defaultAction: publicNetworkAccess ? 'Allow' : 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// Credential for the (simulated) policy administration system.
resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'PolicyAdminApiKey'
  properties: {
    value: policyAdminApiKey
    contentType: 'text/plain'
  }
}

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for r in roleAssignments: {
  name: guid(kv.id, r.principalId, r.roleDefinitionId)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', r.roleDefinitionId)
    principalId: r.principalId
    principalType: r.principalType
  }
}]

output id string = kv.id
output uri string = kv.properties.vaultUri
