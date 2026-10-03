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


// TODO (Lab 1.1): define the tags every resource must carry: workload, environment, owner (the learner ID), learner, and managedBy ('bicep')


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
    // TODO (Lab 1.1): PaaS-first guardrail - add the parameter notAllowedResourceTypes: [ ... ] listing virtual machines, VM scale sets and AKS clusters (same shape as inheritedTagNames above)
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
// Outputs (consumed by the scripts in /scripts)
// -----------------------------------------------------------------------------
output resourceGroupName string = resourceGroup().name
