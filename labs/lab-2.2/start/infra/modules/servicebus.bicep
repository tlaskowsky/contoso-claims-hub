// =============================================================================
// Service Bus (Standard) - claims-processing queue with DLQ   [LAB 2.2]
// Training-environment trade-off: Standard tier has no Private Endpoint support,
// so the namespace stays public. SAS keys are disabled - Entra ID only.
// =============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param name string
param queueName string
@description('Log Analytics workspace for metrics. Empty until Lab 3.1.')
param workspaceId string = ''
param roleAssignments array = []

resource ns 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    disableLocalAuth: true
    minimumTlsVersion: '1.2'
  }
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: ns
  name: queueName
  properties: {
    // TODO (Lab 2.2): dead-letter a message after 3 failed deliveries (maxDeliveryCount), and also when it expires (deadLetteringOnMessageExpiration)
    lockDuration: 'PT1M'
    defaultMessageTimeToLive: 'P7D'
  }
}

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for r in roleAssignments: {
  name: guid(ns.id, r.principalId, r.roleDefinitionId)
  scope: ns
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', r.roleDefinitionId)
    principalId: r.principalId
    principalType: r.principalType
  }
}]

// Send namespace metrics to Log Analytics (used by the DLQ KQL query) [LAB 3.1]
resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: 'to-log-analytics'
  scope: ns
  properties: {
    workspaceId: workspaceId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output id string = ns.id
output name string = ns.name
output fullyQualifiedNamespace string = '${ns.name}.servicebus.windows.net'
