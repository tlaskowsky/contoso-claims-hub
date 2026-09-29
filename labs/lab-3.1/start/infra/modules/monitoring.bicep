// =============================================================================
// Log Analytics + workspace-based Application Insights   [LAB 3.1]
// Local (instrumentation-key) auth is disabled: telemetry is accepted only
// from identities holding Monitoring Metrics Publisher.
// =============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param workspaceName string
param appInsightsName string
param roleAssignments array = []

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    // TODO (Lab 3.1): accept telemetry from Microsoft Entra identities only - disable instrumentation-key (local) authentication
  }
}

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for r in roleAssignments: {
  name: guid(appInsights.id, r.principalId, r.roleDefinitionId)
  scope: appInsights
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', r.roleDefinitionId)
    principalId: r.principalId
    principalType: r.principalType
  }
}]

output workspaceId string = workspace.id
output appInsightsId string = appInsights.id
output connectionString string = appInsights.properties.ConnectionString
