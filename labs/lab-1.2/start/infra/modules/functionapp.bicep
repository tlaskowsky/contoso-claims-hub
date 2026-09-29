// =============================================================================
// Function app on Flex Consumption (Node 22)   [LAB 2.1 / 2.3 / 2.4]
// All connections are identity-based (no connection strings).
// Note: FUNCTIONS_WORKER_RUNTIME / FUNCTIONS_EXTENSION_VERSION are NOT allowed
// on Flex Consumption - the runtime is set in functionAppConfig.
// =============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param planName string
param appName string
param identityId string
param identityClientId string
param storageAccountName string
param deploymentContainerName string
@description('Empty string = no VNet integration.')
param subnetId string
@description('Empty until Application Insights is added (Lab 3.1).')
param appInsightsConnectionString string = ''
param appSettings object = {}
@description('Memory per instance (MB): 512, 2048 or 4096.')
param instanceMemoryMB int = 512

resource st 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

var coreSettings = {
  AzureWebJobsStorage__accountName: storageAccountName
  AzureWebJobsStorage__credential: 'managedidentity'
  AzureWebJobsStorage__clientId: identityClientId
  AZURE_CLIENT_ID: identityClientId
}
// Telemetry settings only once Application Insights exists (Lab 3.1).
var telemetrySettings = empty(appInsightsConnectionString) ? {} : {
  APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
  APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${identityClientId};Authorization=AAD'
}
var baseSettings = union(coreSettings, telemetrySettings)

resource site 'Microsoft.Web/sites@2024-04-01' = {
  name: appName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    virtualNetworkSubnetId: empty(subnetId) ? null : subnetId
    siteConfig: {
      minTlsVersion: '1.2'
      appSettings: [for s in items(union(baseSettings, appSettings)): {
        name: s.key
        value: s.value
      }]
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${st.properties.primaryEndpoints.blob}${deploymentContainerName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: identityId
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 40 // platform minimum
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: {
        name: 'node'
        version: '22'
      }
    }
  }
}

output id string = site.id
output name string = site.name
