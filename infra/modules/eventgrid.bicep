// =============================================================================
// Event Grid system topic on the documents storage account   [LAB 2.1]
// The subscription can only be created after the validation Function code is
// published (Event Grid validates that the target function exists).
// =============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param systemTopicName string
param storageAccountId string
param functionAppId string
param documentsContainerName string
param deploySubscription bool

resource topic 'Microsoft.EventGrid/systemTopics@2022-06-15' = {
  name: systemTopicName
  location: location
  tags: tags
  properties: {
    source: storageAccountId
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

resource sub 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2022-06-15' = if (deploySubscription) {
  parent: topic
  name: 'validate-claim-documents'
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionAppId}/functions/validateDocument'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    // LAB-BLANK(2.1): deliver only BlobCreated events (includedEventTypes) for blobs in the documents container (subjectBeginsWith '/blobServices/default/containers/<container>/')
    filter: { // @blank 2.1
      includedEventTypes: [ // @blank 2.1
        'Microsoft.Storage.BlobCreated' // @blank 2.1
      ] // @blank 2.1
      subjectBeginsWith: '/blobServices/default/containers/${documentsContainerName}/' // @blank 2.1
    } // @blank 2.1
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 10
      eventTimeToLiveInMinutes: 60
    }
  }
}

output systemTopicName string = topic.name
