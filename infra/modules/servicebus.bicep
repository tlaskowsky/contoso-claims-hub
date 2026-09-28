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
param workspaceId string
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
    // LAB-BLANK(2.2): delivery-count limit and dead-lettering
    maxDeliveryCount: 3
    lockDuration: 'PT1M'
    defaultMessageTimeToLive: 'P7D'
    deadLetteringOnMessageExpiration: true
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
resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
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
