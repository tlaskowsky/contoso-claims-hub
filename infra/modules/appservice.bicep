// =============================================================================
// App Service (Linux, Node 22) - Claims Intake API   [LAB 1.3 / 2.4 / 3.2]
// =============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param planName string
param appName string
param skuName string
param identityId string
param identityClientId string
@description('Empty string = no VNet integration.')
param subnetId string
param appSettings object
@description('Create the CPU autoscale rule (Standard tier or higher).')
param enableAutoscale bool = true
@description('Maximum instances when autoscaling.')
param autoscaleMaxInstances int = 2

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: skuName
  }
  properties: {
    reserved: true
  }
}

var baseSettings = {
  AZURE_CLIENT_ID: identityClientId
  SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
}

resource site 'Microsoft.Web/sites@2024-04-01' = {
  name: appName
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    keyVaultReferenceIdentity: identityId
    virtualNetworkSubnetId: empty(subnetId) ? null : subnetId
    siteConfig: {
      linuxFxVersion: 'NODE|22-lts'
      appCommandLine: 'node dist/server.js'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      vnetRouteAllEnabled: !empty(subnetId)
      healthCheckPath: '/health'
      appSettings: [for s in items(union(baseSettings, appSettings)): {
        name: s.key
        value: s.value
      }]
    }
  }
}

// LAB 3.2: CPU-based autoscale (requires Standard tier or higher)
resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = if (enableAutoscale) {
  name: 'autoscale-${planName}'
  location: location
  tags: tags
  properties: {
    enabled: true
    targetResourceUri: plan.id
    profiles: [
      {
        name: 'cpu-based'
        capacity: {
          minimum: '1'
          maximum: string(autoscaleMaxInstances)
          default: '1'
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: plan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: plan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
        ]
      }
    ]
  }
}

output name string = site.name
output url string = 'https://${site.properties.defaultHostName}'
