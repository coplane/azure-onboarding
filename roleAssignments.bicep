// Role assignments on this resource group, each for a platform identity.
// No user-defined type here: it would compile the template to ARM's languageVersion 2.0, which the
// portal's custom deployment page can't read (it shows "undefined resources" and fails on create).
@description('Each: principalId, identity (the identity\'s name, known before deployment, so what-if can show each assignment), roleId, description, and an optional condition.')
param assignments array

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for a in assignments: {
    name: guid(resourceGroup().id, a.identity, a.roleId)
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', a.roleId)
      principalId: a.principalId
      principalType: 'ServicePrincipal'
      description: a.description
      conditionVersion: a.?condition == null ? null : '2.0'
      condition: a.?condition
    }
  }
]
