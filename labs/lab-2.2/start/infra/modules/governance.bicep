// =============================================================================
// Governance - Azure Policy assignments at resource group scope   [LAB 1.1]
// =============================================================================
targetScope = 'resourceGroup'

param location string

@description('Tag names that resources inherit from the resource group when missing.')
param inheritedTagNames array

@description('Resource types denied in this resource group (PaaS-first guardrail).')
param notAllowedResourceTypes array

// Built-in policy definitions
var inheritTagPolicyId = tenantResourceId('Microsoft.Authorization/policyDefinitions', 'ea3f2387-9b95-492a-a190-fcdc54f7b070') // Inherit a tag from the resource group if missing (Modify)
var notAllowedTypesPolicyId = tenantResourceId('Microsoft.Authorization/policyDefinitions', '6c112d4e-5bc7-47ae-a041-ea2d9dccd749') // Not allowed resource types (Deny)
var contributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')

resource inheritTag 'Microsoft.Authorization/policyAssignments@2023-04-01' = [for tagName in inheritedTagNames: {
  name: 'inherit-tag-${tagName}'
  location: location
  identity: {
    type: 'SystemAssigned' // Modify effect requires a managed identity
  }
  properties: {
    displayName: 'Inherit tag "${tagName}" from the resource group if missing'
    policyDefinitionId: inheritTagPolicyId
    parameters: {
      tagName: {
        value: tagName
      }
    }
  }
}]

// Role assignment that lets each policy's managed identity apply the Modify effect
resource inheritTagRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (tagName, i) in inheritedTagNames: {
  name: guid(resourceGroup().id, 'inherit-tag', tagName)
  properties: {
    roleDefinitionId: contributorRoleId
    principalId: inheritTag[i].identity.principalId
    principalType: 'ServicePrincipal'
  }
}]

resource denyTypes 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'deny-non-paas-types'
  properties: {
    displayName: 'Not allowed resource types (PaaS-first guardrail)'
    policyDefinitionId: notAllowedTypesPolicyId
    parameters: {
      listOfResourceTypesNotAllowed: {
        value: notAllowedResourceTypes
      }
    }
  }
}
