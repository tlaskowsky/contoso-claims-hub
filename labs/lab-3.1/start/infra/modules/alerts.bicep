// =============================================================================
// Action group + two alerts   [LAB 3.1]
//   1. Validation Function failure rate (log search alert on App Insights)
//   2. Dead-letter accumulation on the claims-processing queue (metric alert)
// =============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param alertEmail string
param appInsightsId string
param serviceBusNamespaceId string
param queueName string
param validationFunctionAppName string

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-claimshub-ops'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'claimsops'
    enabled: true
    emailReceivers: empty(alertEmail) ? [] : [
      {
        name: 'ops-email'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

resource failureRate 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'alert-validation-failure-rate'
  location: location
  tags: tags
  properties: {
    displayName: 'Validation Function failure rate above 20%'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [
      appInsightsId
    ]
    criteria: {
      allOf: [
        {
          query: 'requests\n| where cloud_RoleName =~ "${validationFunctionAppName}"\n| summarize failurePercent = 100.0 * countif(success == false) / count()'
          timeAggregation: 'Average'
          metricMeasureColumn: 'failurePercent'
          operator: 'GreaterThan'
          threshold: 20
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

resource dlq 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-dlq-accumulation'
  location: 'global'
  tags: tags
  properties: {
    description: 'Messages are accumulating in the ${queueName} dead-letter queue.'
    severity: 2
    enabled: true
    scopes: [
      serviceBusNamespaceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'dead-lettered'
          criterionType: 'StaticThresholdCriterion'
          metricNamespace: 'Microsoft.ServiceBus/namespaces'
          metricName: 'DeadletteredMessages'
          dimensions: [
            {
              name: 'EntityName'
              operator: 'Include'
              values: [
                queueName
              ]
            }
          ]
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}
