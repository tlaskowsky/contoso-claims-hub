// =============================================================================
// Contoso Claims Hub - FINAL SOLUTION (end-of-course state)
// Subscription-scope entry point. Lab mapping is marked on each section.
// =============================================================================
targetScope = 'subscription'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
@description('Short workload name used in all resource names.')
param workloadName string = 'claimshub'

@description('Environment name. Drives resource names and tags.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environmentName string

@description('Azure region for all regional resources.')
param location string

@description('Value for the "owner" tag.')
param owner string

@description('Object ID of the deploying user: az ad signed-in-user show --query id -o tsv. Granted data-plane access for administration and verification.')
param adminPrincipalId string

@description('Email for alert notifications. Empty = alerts fire without notification.')
param alertEmail string = ''

@description('Change to get new globally-unique names (e.g. while a deleted Key Vault is still soft-deleted).')
param nameSeed string = ''

@description('LAB 2.4: disable public network access on data-plane services and use Private Endpoints.')
param lockDownDataPlane bool = true

@description('LAB 2.1: create the Event Grid subscription. Set true only after the validation Function code is published.')
param deployEventSubscription bool = false

@description('Cosmos DB free tier - only one account per subscription can use it.')
param cosmosEnableFreeTier bool = true

@description('LAB 3.2: autoscale max RU/s for the claims container.')
param cosmosAutoscaleMaxThroughput int = 1000

@description('App Service plan SKU. Must be Standard (S1) or higher for autoscale.')
param appServicePlanSku string = 'P0v3'

@description('App Configuration tier.')
@allowed([
  'developer'
  'standard'
])
param appConfigSku string = 'developer'

@secure()
@description('Value for the PolicyAdminApiKey secret (simulated external system credential).')
param policyAdminApiKey string = newGuid()

// -----------------------------------------------------------------------------
// Naming, tags, role IDs
// -----------------------------------------------------------------------------
var w = workloadName
var e = environmentName
var suffix = take(uniqueString(subscription().subscriptionId, workloadName, environmentName, nameSeed), 5)

var names = {
  rg: 'rg-${w}-${e}'
  vnet: 'vnet-${w}-${e}'
  log: 'log-${w}-${e}'
  appi: 'appi-${w}-${e}'
  kv: 'kv-${w}-${e}-${suffix}'
  appcs: 'appcs-${w}-${e}-${suffix}'
  cosmos: 'cosmos-${w}-${e}-${suffix}'
  stDocs: 'stdocs${e}${suffix}'
  stFunc: 'stfunc${e}${suffix}'
  sb: 'sbns-${w}-${e}-${suffix}'
  apiPlan: 'asp-${w}-api-${e}'
  api: 'app-${w}-api-${e}-${suffix}'
  valPlan: 'asp-${w}-val-${e}'
  funcVal: 'func-${w}-val-${e}-${suffix}'
  procPlan: 'asp-${w}-proc-${e}'
  funcProc: 'func-${w}-proc-${e}-${suffix}'
  evgt: 'evgt-${w}-docs-${e}'
  idApi: 'id-${w}-api-${e}'
  idVal: 'id-${w}-val-${e}'
  idProc: 'id-${w}-proc-${e}'
}

var documentsContainer = 'claim-documents'
var processingQueue = 'claims-processing'

var tags = {
  workload: workloadName
  environment: environmentName
  owner: owner
  managedBy: 'bicep'
}

// Built-in role definition IDs
var roles = {
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  keyVaultSecretsOfficer: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
  appConfigDataReader: '516239f1-63e1-4d78-a4de-a74fb236a071'
  appConfigDataOwner: '5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b'
  blobDataOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  blobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  blobDataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  queueDataContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  tableDataContributor: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  serviceBusDataSender: '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
  serviceBusDataReceiver: '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
  serviceBusDataOwner: '090c5cfd-751d-490a-894a-3ce6f1109419'
  monitoringMetricsPublisher: '3913510d-42f4-4e42-8a64-420c390055eb'
}

// -----------------------------------------------------------------------------
// LAB 1.1 - Resource group, governance, identities
// -----------------------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: names.rg
  location: location
  tags: tags
}

module governance 'modules/governance.bicep' = {
  name: 'governance'
  scope: rg
  params: {
    location: location
    inheritedTagNames: [
      'workload'
      'environment'
      'owner'
    ]
    notAllowedResourceTypes: [
      'Microsoft.Compute/virtualMachines'
      'Microsoft.Compute/virtualMachineScaleSets'
      'Microsoft.ContainerService/managedClusters'
    ]
  }
}

module idApi 'modules/identity.bicep' = {
  name: 'identity-api'
  scope: rg
  params: {
    name: names.idApi
    location: location
    tags: tags
  }
}

module idVal 'modules/identity.bicep' = {
  name: 'identity-validation'
  scope: rg
  params: {
    name: names.idVal
    location: location
    tags: tags
  }
}

module idProc 'modules/identity.bicep' = {
  name: 'identity-processing'
  scope: rg
  params: {
    name: names.idProc
    location: location
    tags: tags
  }
}

// -----------------------------------------------------------------------------
// Pre-provisioned network (used in LAB 2.4)
// -----------------------------------------------------------------------------
module network 'modules/network.bicep' = {
  name: 'network'
  scope: rg
  params: {
    location: location
    tags: tags
    vnetName: names.vnet
  }
}

// -----------------------------------------------------------------------------
// LAB 3.1 - Monitoring (deployed first so every app can send telemetry)
// -----------------------------------------------------------------------------
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    workspaceName: names.log
    appInsightsName: names.appi
    roleAssignments: [
      { principalId: idApi.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.monitoringMetricsPublisher }
      { principalId: idVal.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.monitoringMetricsPublisher }
      { principalId: idProc.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.monitoringMetricsPublisher }
    ]
  }
}

// -----------------------------------------------------------------------------
// LAB 1.2 - Key Vault and App Configuration
// -----------------------------------------------------------------------------
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  scope: rg
  params: {
    location: location
    tags: tags
    name: names.kv
    publicNetworkAccess: !lockDownDataPlane
    policyAdminApiKey: policyAdminApiKey
    roleAssignments: [
      { principalId: idApi.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.keyVaultSecretsUser }
      { principalId: adminPrincipalId, principalType: 'User', roleDefinitionId: roles.keyVaultSecretsOfficer }
    ]
  }
}

module appConfig 'modules/appconfig.bicep' = {
  name: 'appconfig'
  scope: rg
  params: {
    location: location
    tags: tags
    name: names.appcs
    skuName: appConfigSku
    roleAssignments: [
      { principalId: idApi.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.appConfigDataReader }
      { principalId: idProc.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.appConfigDataReader }
      { principalId: adminPrincipalId, principalType: 'User', roleDefinitionId: roles.appConfigDataOwner }
    ]
  }
}

// -----------------------------------------------------------------------------
// LAB 1.3 - Cosmos DB
// -----------------------------------------------------------------------------
module cosmos 'modules/cosmos.bicep' = {
  name: 'cosmos'
  scope: rg
  params: {
    location: location
    tags: tags
    name: names.cosmos
    publicNetworkAccess: !lockDownDataPlane
    enableFreeTier: cosmosEnableFreeTier
    autoscaleMaxThroughput: cosmosAutoscaleMaxThroughput
    dataContributorPrincipalIds: [
      idApi.outputs.principalId
      idVal.outputs.principalId
      idProc.outputs.principalId
      adminPrincipalId
    ]
  }
}

// -----------------------------------------------------------------------------
// LAB 2.1 - Storage (documents + Functions runtime)
// -----------------------------------------------------------------------------
module storageDocs 'modules/storage.bicep' = {
  name: 'storage-documents'
  scope: rg
  params: {
    location: location
    tags: tags
    name: names.stDocs
    publicNetworkAccess: !lockDownDataPlane
    containerNames: [
      documentsContainer
    ]
    enableLifecyclePolicy: true
    roleAssignments: [
      { principalId: idApi.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.blobDataContributor }
      { principalId: idVal.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.blobDataReader }
      { principalId: adminPrincipalId, principalType: 'User', roleDefinitionId: roles.blobDataContributor }
    ]
  }
}

module storageFunc 'modules/storage.bicep' = {
  name: 'storage-functions'
  scope: rg
  params: {
    location: location
    tags: tags
    name: names.stFunc
    publicNetworkAccess: !lockDownDataPlane
    containerNames: [
      'deploy-validation'
      'deploy-processing'
    ]
    roleAssignments: [
      { principalId: idVal.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.blobDataOwner }
      { principalId: idVal.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.queueDataContributor }
      { principalId: idVal.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.tableDataContributor }
      { principalId: idProc.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.blobDataOwner }
      { principalId: idProc.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.queueDataContributor }
      { principalId: idProc.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.tableDataContributor }
    ]
  }
}

// -----------------------------------------------------------------------------
// LAB 2.2 - Service Bus
// -----------------------------------------------------------------------------
module serviceBus 'modules/servicebus.bicep' = {
  name: 'servicebus'
  scope: rg
  params: {
    location: location
    tags: tags
    name: names.sb
    queueName: processingQueue
    workspaceId: monitoring.outputs.workspaceId
    roleAssignments: [
      { principalId: idVal.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.serviceBusDataSender }
      { principalId: idProc.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.serviceBusDataReceiver }
      { principalId: adminPrincipalId, principalType: 'User', roleDefinitionId: roles.serviceBusDataOwner }
    ]
  }
}

// -----------------------------------------------------------------------------
// LAB 2.4 - Private Endpoints
// Excluded (training trade-offs): Service Bus (Standard tier has no Private
// Endpoints) and App Configuration (ARM must be able to write key-values).
// -----------------------------------------------------------------------------
var privateEndpointDefs = [
  { resource: names.cosmos, type: 'Microsoft.DocumentDB/databaseAccounts', groupId: 'Sql', zone: 'privatelink.documents.azure.com' }
  { resource: names.stDocs, type: 'Microsoft.Storage/storageAccounts', groupId: 'blob', zone: 'privatelink.blob.${environment().suffixes.storage}' }
  { resource: names.stFunc, type: 'Microsoft.Storage/storageAccounts', groupId: 'blob', zone: 'privatelink.blob.${environment().suffixes.storage}' }
  { resource: names.stFunc, type: 'Microsoft.Storage/storageAccounts', groupId: 'queue', zone: 'privatelink.queue.${environment().suffixes.storage}' }
  { resource: names.stFunc, type: 'Microsoft.Storage/storageAccounts', groupId: 'table', zone: 'privatelink.table.${environment().suffixes.storage}' }
  { resource: names.kv, type: 'Microsoft.KeyVault/vaults', groupId: 'vault', zone: 'privatelink.vaultcore.azure.net' }
]

module privateEndpoints 'modules/privateendpoint.bicep' = [for pe in privateEndpointDefs: if (lockDownDataPlane) {
  name: 'pe-${pe.groupId}-${pe.resource}'
  scope: rg
  params: {
    name: 'pe-${pe.resource}-${toLower(pe.groupId)}'
    location: location
    tags: tags
    subnetId: network.outputs.subnetIds.privateEndpoints
    targetResourceId: resourceId(subscription().subscriptionId, names.rg, pe.type, pe.resource)
    groupId: pe.groupId
    privateDnsZoneId: resourceId(subscription().subscriptionId, names.rg, 'Microsoft.Network/privateDnsZones', pe.zone)
  }
  dependsOn: [
    cosmos
    storageDocs
    storageFunc
    keyVault
    appConfig
  ]
}]

// -----------------------------------------------------------------------------
// LAB 1.3 - Claims Intake API (App Service)   [VNet integration: LAB 2.4]
// -----------------------------------------------------------------------------
module api 'modules/appservice.bicep' = {
  name: 'app-api'
  scope: rg
  params: {
    location: location
    tags: tags
    planName: names.apiPlan
    appName: names.api
    skuName: appServicePlanSku
    identityId: idApi.outputs.id
    identityClientId: idApi.outputs.clientId
    subnetId: lockDownDataPlane ? network.outputs.subnetIds.app : ''
    appSettings: {
      COSMOS_ENDPOINT: cosmos.outputs.endpoint
      COSMOS_DATABASE: cosmos.outputs.databaseName
      COSMOS_CONTAINER: cosmos.outputs.containerName
      KEYVAULT_URI: keyVault.outputs.uri
      APPCONFIG_ENDPOINT: appConfig.outputs.endpoint
      DOCUMENTS_BLOB_ENDPOINT: storageDocs.outputs.blobEndpoint
      DOCUMENTS_CONTAINER: documentsContainer
      APPLICATIONINSIGHTS_CONNECTION_STRING: monitoring.outputs.connectionString
    }
  }
  dependsOn: [
    privateEndpoints
  ]
}

// -----------------------------------------------------------------------------
// LAB 2.1 - Validation Function app (Event Grid trigger -> Service Bus output)
// -----------------------------------------------------------------------------
module funcValidation 'modules/functionapp.bicep' = {
  name: 'func-validation'
  scope: rg
  params: {
    location: location
    tags: tags
    planName: names.valPlan
    appName: names.funcVal
    identityId: idVal.outputs.id
    identityClientId: idVal.outputs.clientId
    storageAccountName: storageFunc.outputs.name
    deploymentContainerName: 'deploy-validation'
    subnetId: lockDownDataPlane ? network.outputs.subnetIds.funcValidation : ''
    appInsightsConnectionString: monitoring.outputs.connectionString
    appSettings: {
      COSMOS_ENDPOINT: cosmos.outputs.endpoint
      COSMOS_DATABASE: cosmos.outputs.databaseName
      COSMOS_CONTAINER: cosmos.outputs.containerName
      ServiceBusConnection__fullyQualifiedNamespace: serviceBus.outputs.fullyQualifiedNamespace
      ServiceBusConnection__credential: 'managedidentity'
      ServiceBusConnection__clientId: idVal.outputs.clientId
    }
  }
  dependsOn: [
    privateEndpoints
  ]
}

// -----------------------------------------------------------------------------
// LAB 2.2 / 2.3 - Processing Function app (Service Bus trigger + Durable approval)
// -----------------------------------------------------------------------------
module funcProcessing 'modules/functionapp.bicep' = {
  name: 'func-processing'
  scope: rg
  params: {
    location: location
    tags: tags
    planName: names.procPlan
    appName: names.funcProc
    identityId: idProc.outputs.id
    identityClientId: idProc.outputs.clientId
    storageAccountName: storageFunc.outputs.name
    deploymentContainerName: 'deploy-processing'
    subnetId: lockDownDataPlane ? network.outputs.subnetIds.funcProcessing : ''
    appInsightsConnectionString: monitoring.outputs.connectionString
    appSettings: {
      COSMOS_ENDPOINT: cosmos.outputs.endpoint
      COSMOS_DATABASE: cosmos.outputs.databaseName
      COSMOS_CONTAINER: cosmos.outputs.containerName
      APPCONFIG_ENDPOINT: appConfig.outputs.endpoint
      ServiceBusConnection__fullyQualifiedNamespace: serviceBus.outputs.fullyQualifiedNamespace
      ServiceBusConnection__credential: 'managedidentity'
      ServiceBusConnection__clientId: idProc.outputs.clientId
    }
  }
  dependsOn: [
    privateEndpoints
  ]
}

// -----------------------------------------------------------------------------
// LAB 2.1 - Event Grid
// -----------------------------------------------------------------------------
module eventGrid 'modules/eventgrid.bicep' = {
  name: 'eventgrid'
  scope: rg
  params: {
    location: location
    tags: tags
    systemTopicName: names.evgt
    storageAccountId: storageDocs.outputs.id
    functionAppId: funcValidation.outputs.id
    documentsContainerName: documentsContainer
    deploySubscription: deployEventSubscription
  }
}

// -----------------------------------------------------------------------------
// LAB 3.1 - Alerts
// -----------------------------------------------------------------------------
module alerts 'modules/alerts.bicep' = {
  name: 'alerts'
  scope: rg
  params: {
    location: location
    tags: tags
    alertEmail: alertEmail
    appInsightsId: monitoring.outputs.appInsightsId
    serviceBusNamespaceId: serviceBus.outputs.id
    queueName: processingQueue
    validationFunctionAppName: funcValidation.outputs.name
  }
}

// -----------------------------------------------------------------------------
// Outputs (consumed by the scripts in /scripts)
// -----------------------------------------------------------------------------
output resourceGroupName string = rg.name
output apiAppName string = api.outputs.name
output apiUrl string = api.outputs.url
output validationFunctionAppName string = funcValidation.outputs.name
output processingFunctionAppName string = funcProcessing.outputs.name
output serviceBusNamespaceName string = serviceBus.outputs.name
output processingQueueName string = processingQueue
output cosmosAccountName string = names.cosmos
output keyVaultName string = names.kv
output appConfigName string = names.appcs
output documentsStorageAccountName string = names.stDocs
output logAnalyticsWorkspaceName string = names.log
output appInsightsName string = names.appi
