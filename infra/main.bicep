// =============================================================================
// Contoso Claims Hub - reference solution
// Resource-group-scope entry point: each learner deploys into resource groups
// the instructor pre-created for them (rg-claimshub-<learnerId>-<env>).
// =============================================================================
targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
@description('Short workload name used in all resource names.')
param workloadName string = 'claimshub'

@description('Learner ID, e.g. s01-s16 for students, i01 for the instructor.')
@minLength(3)
@maxLength(3)
param learnerId string

@description('Environment name. Drives resource names and tags.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environmentName string

@description('Azure region for all regional resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Change to get new globally-unique names (e.g. while a deleted Key Vault is still soft-deleted).')
param nameSeed string = ''

// @from 1.2 begin
@description('Object ID of the deploying user: az ad signed-in-user show --query id -o tsv. Granted data-plane access for administration and verification.')
param adminPrincipalId string

@description('App Configuration tier.')
@allowed([
  'developer'
  'standard'
])
param appConfigSku string = 'developer'

@secure()
@description('Value for the PolicyAdminApiKey secret (simulated external system credential).')
param policyAdminApiKey string = newGuid()
// @end

// @from 1.3 begin
@description('App Service plan SKU. Must be Standard (S1) or higher for autoscale.')
param appServicePlanSku string = 'S1'

@description('Cosmos DB free tier - only one account per subscription can use it.')
param cosmosEnableFreeTier bool = false
// @end

// @from 2.1 begin
@description('LAB 2.1: create the Event Grid subscription. Set true only after the validation Function code is published.')
param deployEventSubscription bool = false

@description('Memory per Function app instance on Flex Consumption (MB). 512 keeps the class well inside the regional memory quota.')
@allowed([
  512
  2048
  4096
])
param functionInstanceMemoryMB int = 512
// @end

// @from 2.4 begin
@description('LAB 2.4: disable public network access on data-plane services and use Private Endpoints.')
param lockDownDataPlane bool = true
// @end

// @from 3.1 begin
@description('Email for alert notifications. Empty = alerts fire without notification.')
param alertEmail string = ''
// @end

// @from 3.2 begin
@description('LAB 3.2: autoscale the App Service plan (requires Standard or higher; off for Basic).')
param enableAutoscale bool = true

@description('LAB 3.2: maximum App Service instances when autoscaling (kept low to protect the shared quota).')
@minValue(1)
@maxValue(3)
param autoscaleMaxInstances int = 2

@description('LAB 3.2: autoscale max RU/s for the claims container.')
param cosmosAutoscaleMaxThroughput int = 1000
// @end

// -----------------------------------------------------------------------------
// Naming, tags, role IDs
// -----------------------------------------------------------------------------
var w = workloadName
var e = environmentName
var suffix = take(uniqueString(resourceGroup().id, nameSeed), 5)
var l = learnerId

var names = {
  vnet: 'vnet-${w}-${l}-${e}'
  log: 'log-${w}-${l}-${e}'
  appi: 'appi-${w}-${l}-${e}'
  kv: 'kv-${l}-${e}-${suffix}'
  appcs: 'appcs-${w}-${l}-${e}-${suffix}'
  cosmos: 'cosmos-${w}-${l}-${e}-${suffix}'
  stDocs: 'stdocs${l}${e}${suffix}'
  stFunc: 'stfunc${l}${e}${suffix}'
  sb: 'sbns-${w}-${l}-${e}-${suffix}'
  apiPlan: 'asp-${w}-api-${l}-${e}'
  api: 'app-${w}-api-${l}-${e}-${suffix}'
  valPlan: 'asp-${w}-val-${l}-${e}'
  funcVal: 'func-${w}-val-${l}-${e}-${suffix}'
  procPlan: 'asp-${w}-proc-${l}-${e}'
  funcProc: 'func-${w}-proc-${l}-${e}-${suffix}'
  evgt: 'evgt-${w}-docs-${l}-${e}'
  idApi: 'id-${w}-api-${l}-${e}'
  idVal: 'id-${w}-val-${l}-${e}'
  idProc: 'id-${w}-proc-${l}-${e}'
}

var documentsContainer = 'claim-documents' // @from 2.1
var processingQueue = 'claims-processing' // @from 2.2

// LAB-BLANK(1.1): define the tags every resource must carry: workload, environment, owner (the learner ID), learner, and managedBy ('bicep')
var tags = { // @blank 1.1
  workload: workloadName // @blank 1.1
  environment: environmentName // @blank 1.1
  owner: learnerId // @blank 1.1
  learner: learnerId // @blank 1.1
  managedBy: 'bicep' // @blank 1.1
} // @blank 1.1

// @from 1.2 begin
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
// @end

// -----------------------------------------------------------------------------
// LAB 1.1 - Governance and identity (the resource group is pre-created)
// -----------------------------------------------------------------------------
module governance 'modules/governance.bicep' = {
  name: 'governance'
  params: {
    location: location
    inheritedTagNames: [
      'workload'
      'environment'
      'owner'
    ]
    // LAB-BLANK(1.1): PaaS-first guardrail - list the resource types to deny: virtual machines, VM scale sets and AKS clusters
    notAllowedResourceTypes: [ // @blank 1.1
      'Microsoft.Compute/virtualMachines' // @blank 1.1
      'Microsoft.Compute/virtualMachineScaleSets' // @blank 1.1
      'Microsoft.ContainerService/managedClusters' // @blank 1.1
    ] // @blank 1.1
  }
}

module idApi 'modules/identity.bicep' = {
  name: 'identity-api'
  params: {
    name: names.idApi
    location: location
    tags: tags
  }
}

// @from 2.1 begin
module idVal 'modules/identity.bicep' = {
  name: 'identity-validation'
  params: {
    name: names.idVal
    location: location
    tags: tags
  }
}
// @end

// @from 2.2 begin
module idProc 'modules/identity.bicep' = {
  name: 'identity-processing'
  params: {
    name: names.idProc
    location: location
    tags: tags
  }
}
// @end

// Pre-provisioned network (put to work in LAB 2.4)
module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    tags: tags
    vnetName: names.vnet
  }
}

// @from 3.1 begin
// -----------------------------------------------------------------------------
// LAB 3.1 - Monitoring
// -----------------------------------------------------------------------------
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    tags: tags
    workspaceName: names.log
    appInsightsName: names.appi
    // LAB-BLANK(3.1): let each app identity (api, validation, processing) send telemetry: role monitoringMetricsPublisher, principalType 'ServicePrincipal'
    roleAssignments: [ // @blank 3.1
      { principalId: idApi.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.monitoringMetricsPublisher } // @blank 3.1
      { principalId: idVal.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.monitoringMetricsPublisher } // @blank 3.1
      { principalId: idProc.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.monitoringMetricsPublisher } // @blank 3.1
    ] // @blank 3.1
  }
}
// @end

// @from 1.2 begin
// -----------------------------------------------------------------------------
// LAB 1.2 - Key Vault and App Configuration
// -----------------------------------------------------------------------------
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    tags: tags
    name: names.kv
    publicNetworkAccess: !lockDownDataPlane // @from 2.4
    // @until 2.4: publicNetworkAccess: true
    policyAdminApiKey: policyAdminApiKey
    roleAssignments: [
      // LAB-BLANK(1.2): let the API's managed identity READ secrets (role keyVaultSecretsUser, principalType 'ServicePrincipal')
      { principalId: idApi.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.keyVaultSecretsUser } // @blank 1.2
      { principalId: adminPrincipalId, principalType: 'User', roleDefinitionId: roles.keyVaultSecretsOfficer }
    ]
  }
}

module appConfig 'modules/appconfig.bicep' = {
  name: 'appconfig'
  params: {
    location: location
    tags: tags
    name: names.appcs
    skuName: appConfigSku
    roleAssignments: [
      { principalId: idApi.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.appConfigDataReader }
      { principalId: idProc.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.appConfigDataReader } // @from 2.2
      { principalId: adminPrincipalId, principalType: 'User', roleDefinitionId: roles.appConfigDataOwner }
    ]
  }
}
// @end

// @from 1.3 begin
// -----------------------------------------------------------------------------
// LAB 1.3 - Cosmos DB
// -----------------------------------------------------------------------------
module cosmos 'modules/cosmos.bicep' = {
  name: 'cosmos'
  params: {
    location: location
    tags: tags
    name: names.cosmos
    publicNetworkAccess: !lockDownDataPlane // @from 2.4
    // @until 2.4: publicNetworkAccess: true
    enableFreeTier: cosmosEnableFreeTier
    // LAB-BLANK(3.2): after migrating the container to autoscale, pass the autoscale maximum (parameter cosmosAutoscaleMaxThroughput)
    autoscaleMaxThroughput: cosmosAutoscaleMaxThroughput // @from 3.2 @blank 3.2
    dataContributorPrincipalIds: [
      idApi.outputs.principalId
      idVal.outputs.principalId // @from 2.1
      idProc.outputs.principalId // @from 2.2
      adminPrincipalId
    ]
  }
}
// @end

// @from 2.1 begin
// -----------------------------------------------------------------------------
// LAB 2.1 - Storage (documents + Functions runtime)
// -----------------------------------------------------------------------------
module storageDocs 'modules/storage.bicep' = {
  name: 'storage-documents'
  params: {
    location: location
    tags: tags
    name: names.stDocs
    publicNetworkAccess: !lockDownDataPlane // @from 2.4
    // @until 2.4: publicNetworkAccess: true
    containerNames: [
      documentsContainer
    ]
    enableLifecyclePolicy: true
    roleAssignments: [
      { principalId: idApi.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.blobDataContributor }
      // LAB-BLANK(2.1): the validation Function only needs to READ documents - pick the least-privileged blob role
      { principalId: idVal.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.blobDataReader } // @blank 2.1
      { principalId: adminPrincipalId, principalType: 'User', roleDefinitionId: roles.blobDataContributor }
    ]
  }
}

module storageFunc 'modules/storage.bicep' = {
  name: 'storage-functions'
  params: {
    location: location
    tags: tags
    name: names.stFunc
    publicNetworkAccess: !lockDownDataPlane // @from 2.4
    // @until 2.4: publicNetworkAccess: true
    containerNames: [
      'deploy-validation'
      'deploy-processing' // @from 2.2
    ]
    roleAssignments: [
      { principalId: idVal.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.blobDataOwner }
      { principalId: idVal.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.queueDataContributor }
      { principalId: idVal.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.tableDataContributor }
      { principalId: idProc.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.blobDataOwner } // @from 2.2
      { principalId: idProc.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.queueDataContributor } // @from 2.2
      { principalId: idProc.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.tableDataContributor } // @from 2.2
    ]
  }
}
// @end

// @from 2.2 begin
// -----------------------------------------------------------------------------
// LAB 2.2 - Service Bus
// -----------------------------------------------------------------------------
module serviceBus 'modules/servicebus.bicep' = {
  name: 'servicebus'
  params: {
    location: location
    tags: tags
    name: names.sb
    queueName: processingQueue
    workspaceId: monitoring.outputs.workspaceId // @from 3.1
    roleAssignments: [
      // LAB-BLANK(2.2): least privilege - the validation identity only SENDS to the queue, the processing identity only RECEIVES
      { principalId: idVal.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.serviceBusDataSender } // @blank 2.2
      { principalId: idProc.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.serviceBusDataReceiver } // @blank 2.2
      { principalId: adminPrincipalId, principalType: 'User', roleDefinitionId: roles.serviceBusDataOwner }
    ]
  }
}
// @end

// @from 2.4 begin
// -----------------------------------------------------------------------------
// LAB 2.4 - Private Endpoints
// Excluded (training trade-offs): Service Bus (Standard tier has no Private
// Endpoints) and App Configuration (ARM must be able to write key-values).
// -----------------------------------------------------------------------------
var privateEndpointDefs = [
  // LAB-BLANK(2.4): add Private Endpoints for Cosmos DB (groupId 'Sql', zone 'privatelink.documents.azure.com') and Key Vault (groupId 'vault', zone 'privatelink.vaultcore.azure.net')
  { resource: names.cosmos, type: 'Microsoft.DocumentDB/databaseAccounts', groupId: 'Sql', zone: 'privatelink.documents.azure.com' } // @blank 2.4
  { resource: names.stDocs, type: 'Microsoft.Storage/storageAccounts', groupId: 'blob', zone: 'privatelink.blob.${environment().suffixes.storage}' }
  { resource: names.stFunc, type: 'Microsoft.Storage/storageAccounts', groupId: 'blob', zone: 'privatelink.blob.${environment().suffixes.storage}' }
  { resource: names.stFunc, type: 'Microsoft.Storage/storageAccounts', groupId: 'queue', zone: 'privatelink.queue.${environment().suffixes.storage}' }
  { resource: names.stFunc, type: 'Microsoft.Storage/storageAccounts', groupId: 'table', zone: 'privatelink.table.${environment().suffixes.storage}' }
  { resource: names.kv, type: 'Microsoft.KeyVault/vaults', groupId: 'vault', zone: 'privatelink.vaultcore.azure.net' } // @blank 2.4
]

module privateEndpoints 'modules/privateendpoint.bicep' = [for pe in privateEndpointDefs: if (lockDownDataPlane) {
  name: 'pe-${pe.groupId}-${pe.resource}'
  params: {
    name: 'pe-${pe.resource}-${toLower(pe.groupId)}'
    location: location
    tags: tags
    subnetId: network.outputs.subnetIds.privateEndpoints
    targetResourceId: resourceId(pe.type, pe.resource)
    groupId: pe.groupId
    privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', pe.zone)
  }
  dependsOn: [
    cosmos
    storageDocs
    storageFunc
    keyVault
    appConfig
  ]
}]
// @end

// @from 1.3 begin
// -----------------------------------------------------------------------------
// LAB 1.3 - Claims Intake API (App Service)   [VNet integration: LAB 2.4]
// -----------------------------------------------------------------------------
module api 'modules/appservice.bicep' = {
  name: 'app-api'
  params: {
    location: location
    tags: tags
    planName: names.apiPlan
    appName: names.api
    skuName: appServicePlanSku
    enableAutoscale: enableAutoscale // @from 3.2
    // @until 3.2: enableAutoscale: false
    autoscaleMaxInstances: autoscaleMaxInstances // @from 3.2
    identityId: idApi.outputs.id
    identityClientId: idApi.outputs.clientId
    // LAB-BLANK(2.4): route the API's outbound traffic through its VNet subnet (network.outputs.subnetIds.app) when the data plane is locked down, otherwise ''
    subnetId: lockDownDataPlane ? network.outputs.subnetIds.app : '' // @from 2.4 @blank 2.4
    // @until 2.4: subnetId: ''
    appSettings: {
      // LAB-BLANK(1.3): tell the API where Cosmos DB is - COSMOS_ENDPOINT, COSMOS_DATABASE and COSMOS_CONTAINER from the cosmos module's outputs
      COSMOS_ENDPOINT: cosmos.outputs.endpoint // @blank 1.3
      COSMOS_DATABASE: cosmos.outputs.databaseName // @blank 1.3
      COSMOS_CONTAINER: cosmos.outputs.containerName // @blank 1.3
      KEYVAULT_URI: keyVault.outputs.uri
      APPCONFIG_ENDPOINT: appConfig.outputs.endpoint
      DOCUMENTS_BLOB_ENDPOINT: storageDocs.outputs.blobEndpoint // @from 2.1
      DOCUMENTS_CONTAINER: documentsContainer // @from 2.1
      APPLICATIONINSIGHTS_CONNECTION_STRING: monitoring.outputs.connectionString // @from 3.1
    }
  }
  dependsOn: [ // @from 2.4
    privateEndpoints // @from 2.4
  ] // @from 2.4
}
// @end

// @from 2.1 begin
// -----------------------------------------------------------------------------
// LAB 2.1 - Validation Function app (Event Grid trigger -> Service Bus from LAB 2.2)
// -----------------------------------------------------------------------------
module funcValidation 'modules/functionapp.bicep' = {
  name: 'func-validation'
  params: {
    location: location
    tags: tags
    planName: names.valPlan
    appName: names.funcVal
    identityId: idVal.outputs.id
    identityClientId: idVal.outputs.clientId
    storageAccountName: storageFunc.outputs.name
    deploymentContainerName: 'deploy-validation'
    instanceMemoryMB: functionInstanceMemoryMB
    subnetId: lockDownDataPlane ? network.outputs.subnetIds.funcValidation : '' // @from 2.4
    // @until 2.4: subnetId: ''
    appInsightsConnectionString: monitoring.outputs.connectionString // @from 3.1
    appSettings: {
      COSMOS_ENDPOINT: cosmos.outputs.endpoint
      COSMOS_DATABASE: cosmos.outputs.databaseName
      COSMOS_CONTAINER: cosmos.outputs.containerName
      ServiceBusConnection__fullyQualifiedNamespace: serviceBus.outputs.fullyQualifiedNamespace // @from 2.2
      ServiceBusConnection__credential: 'managedidentity' // @from 2.2
      ServiceBusConnection__clientId: idVal.outputs.clientId // @from 2.2
    }
  }
  dependsOn: [ // @from 2.4
    privateEndpoints // @from 2.4
  ] // @from 2.4
}
// @end

// @from 2.2 begin
// -----------------------------------------------------------------------------
// LAB 2.2 / 2.3 - Processing Function app (Service Bus trigger + Durable approval)
// -----------------------------------------------------------------------------
module funcProcessing 'modules/functionapp.bicep' = {
  name: 'func-processing'
  params: {
    location: location
    tags: tags
    planName: names.procPlan
    appName: names.funcProc
    identityId: idProc.outputs.id
    identityClientId: idProc.outputs.clientId
    storageAccountName: storageFunc.outputs.name
    deploymentContainerName: 'deploy-processing'
    instanceMemoryMB: functionInstanceMemoryMB
    subnetId: lockDownDataPlane ? network.outputs.subnetIds.funcProcessing : '' // @from 2.4
    // @until 2.4: subnetId: ''
    appInsightsConnectionString: monitoring.outputs.connectionString // @from 3.1
    appSettings: {
      COSMOS_ENDPOINT: cosmos.outputs.endpoint
      COSMOS_DATABASE: cosmos.outputs.databaseName
      COSMOS_CONTAINER: cosmos.outputs.containerName
      APPCONFIG_ENDPOINT: appConfig.outputs.endpoint
      ServiceBusConnection__fullyQualifiedNamespace: serviceBus.outputs.fullyQualifiedNamespace
      ServiceBusConnection__credential: 'managedidentity'
      ServiceBusConnection__clientId: idProc.outputs.clientId
      // LAB-BLANK(2.3): switch on the Durable approval workflow (APPROVAL_WORKFLOW_ENABLED: 'true') and set how long it waits for an approver (APPROVAL_TIMEOUT_HOURS: '72')
      APPROVAL_WORKFLOW_ENABLED: 'true' // @from 2.3 @blank 2.3
      APPROVAL_TIMEOUT_HOURS: '72' // @from 2.3 @blank 2.3
      // @until 2.3: APPROVAL_WORKFLOW_ENABLED: 'false'
    }
  }
  dependsOn: [ // @from 2.4
    privateEndpoints // @from 2.4
  ] // @from 2.4
}
// @end

// @from 2.1 begin
// -----------------------------------------------------------------------------
// LAB 2.1 - Event Grid
// -----------------------------------------------------------------------------
module eventGrid 'modules/eventgrid.bicep' = {
  name: 'eventgrid'
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
// @end

// @from 3.1 begin
// -----------------------------------------------------------------------------
// LAB 3.1 - Alerts
// -----------------------------------------------------------------------------
module alerts 'modules/alerts.bicep' = {
  name: 'alerts'
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
// @end

// -----------------------------------------------------------------------------
// Outputs (consumed by the scripts in /scripts)
// -----------------------------------------------------------------------------
output resourceGroupName string = resourceGroup().name
output keyVaultName string = names.kv // @from 1.2
output appConfigName string = names.appcs // @from 1.2
output cosmosAccountName string = names.cosmos // @from 1.3
output apiAppName string = api.outputs.name // @from 1.3
output apiUrl string = api.outputs.url // @from 1.3
output documentsStorageAccountName string = names.stDocs // @from 2.1
output validationFunctionAppName string = funcValidation.outputs.name // @from 2.1
output processingFunctionAppName string = funcProcessing.outputs.name // @from 2.2
output serviceBusNamespaceName string = serviceBus.outputs.name // @from 2.2
output processingQueueName string = processingQueue // @from 2.2
output logAnalyticsWorkspaceName string = names.log // @from 3.1
output appInsightsName string = names.appi // @from 3.1
