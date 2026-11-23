// Where CoPlane's Terraform keeps the state of this subscription's platform. The state names
// this subscription's resources and holds some of their keys, so it stays here, in the
// customer's subscription, and leaves with it. Entra ID sign-in only (no account keys),
// every write kept as a version, deletes recoverable for 30 days, and a delete lock that
// CoPlane's Contributor role can't remove.
param name string
param location string
param coplanePrincipalId string

var storageBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: account
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobs
  name: 'tfstate'
}

resource coplaneAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, coplanePrincipalId, storageBlobDataContributor)
  scope: account
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributor)
    principalId: coplanePrincipalId
    principalType: 'ServicePrincipal'
    description: 'CoPlane: read and write the platform\'s Terraform state'
  }
}

resource keep 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'keep-platform-state'
  scope: account
  properties: {
    level: 'CanNotDelete'
    notes: 'The CoPlane platform\'s Terraform state. Remove only when removing the platform.'
  }
}

output name string = account.name
