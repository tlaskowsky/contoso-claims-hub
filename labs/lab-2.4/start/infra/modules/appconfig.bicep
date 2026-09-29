// =============================================================================
// App Configuration - settings and a feature flag   [LAB 1.2]
// Local (access key) auth disabled: Entra ID only. Key-values are written
// through ARM with "Pass-through" auth (the deployer needs App Configuration
// Data Owner).
//
// Training-environment trade-off: the store keeps PUBLIC network access.
// ARM cannot write key-values to a private-only store unless the deployment
// runs through Azure Resource Management Private Link (i.e. from inside the
// network). In production, configuration would be deployed by a pipeline
// agent inside the VNet, and public access disabled.
//
// Key-value resource names: "/" is encoded as "~2F" and ":" as "~3A".
// =============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param name string
@allowed([
  'developer'
  'standard'
])
param skuName string
@description('Must include the deployer as App Configuration Data Owner (Pass-through auth).')
param roleAssignments array = []

resource store 'Microsoft.AppConfiguration/configurationStores@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    dataPlaneProxy: {
      authenticationMode: 'Pass-through'
      privateLinkDelegation: 'Disabled'
    }
  }
}

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for r in roleAssignments: {
  name: guid(store.id, r.principalId, r.roleDefinitionId)
  scope: store
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', r.roleDefinitionId)
    principalId: r.principalId
    principalType: r.principalType
  }
}]

var featureFlagValue = {
  id: 'AutoApproveLowValue'
  description: 'Auto-approve claims under $1,000 when every automated check passes.'
  enabled: false
  conditions: {
    client_filters: []
  }
}

var keyValues = [
  {
    name: 'ClaimsHub~3AMaxClaimAmount' // ClaimsHub:MaxClaimAmount
    value: '250000'
    contentType: 'text/plain'
  }
  {
    name: 'ClaimsHub~3ALegacyPolicySystemOnline' // ClaimsHub:LegacyPolicySystemOnline
    value: 'false'
    contentType: 'text/plain'
  }
  {
    name: '.appconfig.featureflag~2FAutoApproveLowValue'
    value: string(featureFlagValue)
    contentType: 'application/vnd.microsoft.appconfig.ff+json;charset=utf-8'
  }
]

resource kvs 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [for item in keyValues: {
  parent: store
  name: item.name
  properties: {
    value: item.value
    contentType: item.contentType
  }
  dependsOn: [
    ra // deployer's Data Owner assignment must exist first (see adminPrincipalId)
  ]
}]

output id string = store.id
output endpoint string = store.properties.endpoint
