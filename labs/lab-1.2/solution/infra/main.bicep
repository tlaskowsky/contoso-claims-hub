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


var tags = {
  workload: workloadName
  environment: environmentName
  owner: learnerId
  learner: learnerId
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
    notAllowedResourceTypes: [
      'Microsoft.Compute/virtualMachines'
      'Microsoft.Compute/virtualMachineScaleSets'
      'Microsoft.ContainerService/managedClusters'
    ]
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



// Pre-provisioned network (put to work in LAB 2.4)
module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    tags: tags
    vnetName: names.vnet
  }
}


// -----------------------------------------------------------------------------
// LAB 1.2 - Key Vault and App Configuration
// -----------------------------------------------------------------------------
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    tags: tags
    name: names.kv
    publicNetworkAccess: true
    policyAdminApiKey: policyAdminApiKey
    roleAssignments: [
      { principalId: idApi.outputs.principalId, principalType: 'ServicePrincipal', roleDefinitionId: roles.keyVaultSecretsUser }
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
      { principalId: adminPrincipalId, principalType: 'User', roleDefinitionId: roles.appConfigDataOwner }
    ]
  }
}










// -----------------------------------------------------------------------------
// Outputs (consumed by the scripts in /scripts)
// -----------------------------------------------------------------------------
output resourceGroupName string = resourceGroup().name
output keyVaultName string = names.kv
output appConfigName string = names.appcs
