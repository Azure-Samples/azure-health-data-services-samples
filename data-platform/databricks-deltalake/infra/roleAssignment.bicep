param resourceId string
param roleId string
param principalId string
param principalType string = 'ServicePrincipal'

@description('See https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#fhir-data-contributor')
resource roleDefinition 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: roleId
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' =  {
  name: guid(resourceId, principalId, roleDefinition.id)
  properties: {
    roleDefinitionId: roleDefinition.id
    principalId: principalId
    principalType: principalType
  }
}
