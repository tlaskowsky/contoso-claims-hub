// =============================================================================
// Cosmos DB for NoSQL - account, database, claims container   [LAB 1.3 / 3.2]
// Key-based auth disabled; access via Cosmos DB data-plane RBAC only.
// =============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param name string
param publicNetworkAccess bool
param enableFreeTier bool
@description('LAB 3.2: autoscale maximum RU/s for the claims container. 0 = manual 400 RU/s (before Lab 3.2).')
param autoscaleMaxThroughput int = 0
@description('Principal IDs granted Cosmos DB Built-in Data Contributor.')
param dataContributorPrincipalIds array

var databaseName = 'claimshub'
var containerName = 'claims'

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: name
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: enableFreeTier
    disableLocalAuth: true
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    minimalTlsVersion: 'Tls12'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: account
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      // LAB-BLANK(1.3): choose the partition key - every claim is read and written by its claimId (paths ['/claimId'], kind 'Hash', version 2)
      partitionKey: { // @blank 1.3
        paths: [ // @blank 1.3
          '/claimId' // @blank 1.3
        ] // @blank 1.3
        kind: 'Hash' // @blank 1.3
        version: 2 // @blank 1.3
      } // @blank 1.3
    }
    // LAB 3.2: manual throughput first; autoscale once the container has been migrated
    options: autoscaleMaxThroughput > 0 ? {
      autoscaleSettings: {
        maxThroughput: autoscaleMaxThroughput
      }
    } : {
      throughput: 400
    }
  }
}

// Built-in data-plane role: Cosmos DB Built-in Data Contributor
resource dataRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = [for principalId in dataContributorPrincipalIds: {
  parent: account
  name: guid(account.id, principalId, 'data-contributor')
  properties: {
    roleDefinitionId: '${account.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    principalId: principalId
    scope: account.id
  }
}]

output id string = account.id
output endpoint string = account.properties.documentEndpoint
output databaseName string = databaseName
output containerName string = containerName
