// Grants CoPlane's service principal the roles it needs to run the app platform in this
// subscription, and creates the platform's resource groups and the identities that need
// roles CoPlane can't grant. Deployed once per customer subscription by a subscription Owner.
targetScope = 'subscription'

@description('Object ID of the CoPlane service principal (enterprise application) in your tenant. This is not the application (client) ID.')
param principalId string

@description('Prefix of the platform\'s resource group and identity names. CoPlane\'s Terraform finds them by it.')
@minLength(3)
@maxLength(32)
param namePrefix string = 'coplane'

@description('Region of the platform\'s resource groups and identities, and of its cluster.')
param location string = deployment().location

var roles = {
  contributor: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  rbacAdministrator: 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
  aksRbacClusterAdmin: 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'
  networkContributor: '4d97b98b-1d4f-4787-a291-c67834d212e7'
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  dnsZoneContributor: 'befefa01-2a29-4197-83a8-272ff33ce314'
  albConfigurationManager: 'fbc52c3f-28ad-4303-a892-8a056630b8f1'
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  keyVaultSecretsOfficer: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
  openAiUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  acrPush: '8311e382-0749-4cb8-b61a-304f252e45ec'
}

// The only roles CoPlane can hand out: registry pull for its cluster and Argo CD, and cluster
// admin for named engineers. Apps' data roles are granted by Azure Service Operator's own
// restricted assignment, so they aren't on this list.
var coplaneGrantableRoleIds = [
  roles.acrPull
  roles.aksRbacClusterAdmin
]

// The data roles Azure Service Operator may give each app's identity on the app's own resources.
var appDataRoleIds = [
  roles.storageBlobDataContributor
  roles.keyVaultSecretsUser
  roles.keyVaultSecretsOfficer
]

// Both writes and deletes are constrained, so the holder can neither grant nor remove any other role.
// A template string rather than a user-defined function, which would compile the template to ARM's
// languageVersion 2.0, which the portal's custom deployment page can't read.
var grantConditionTemplate = '((!(ActionMatches{\'Microsoft.Authorization/roleAssignments/write\'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {ROLE_IDS})) AND ((!(ActionMatches{\'Microsoft.Authorization/roleAssignments/delete\'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {ROLE_IDS}))'

// CoPlane's service principal

resource contributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, roles.contributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.contributor)
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'CoPlane: create and manage platform resources'
  }
}

resource rbacAdministrator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, roles.rbacAdministrator)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.rbacAdministrator)
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'CoPlane: grant registry pull and cluster admin to the platform and its engineers'
    conditionVersion: '2.0'
    condition: replace(grantConditionTemplate, 'ROLE_IDS', join(coplaneGrantableRoleIds, ', '))
  }
}

resource aksRbacClusterAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, roles.aksRbacClusterAdmin)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.aksRbacClusterAdmin)
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'CoPlane: operate the platform Kubernetes clusters'
  }
}

// The platform's resource groups, and its identities that need roles CoPlane can't grant

resource platformGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${namePrefix}'
  location: location
}

resource networkGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${namePrefix}-network'
  location: location
}

// The registry of the platform's configuration, which Argo CD applies with cluster admin. It
// has its own group so app builds, which push to the app registry in rg-<prefix>, can't
// write to it.
resource deliveryGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${namePrefix}-delivery'
  location: location
}

// Every app's databases, storage and vaults, created by Azure Service Operator.
resource appsGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${namePrefix}-apps'
  location: location
}

var identityNames = {
  cluster: '${namePrefix}-cluster'
  ingress: '${namePrefix}-alb'
  certificates: '${namePrefix}-cert-manager'
  operator: '${namePrefix}-aso'
  appPush: '${namePrefix}-app-push'
  bundlePush: '${namePrefix}-bundle-push'
}

module identities 'identities.bicep' = {
  name: 'coplane-identities'
  scope: platformGroup
  params: {
    names: identityNames
    location: location
  }
}

module state 'state.bicep' = {
  name: 'coplane-state'
  scope: platformGroup
  params: {
    name: take('tfstate${uniqueString(subscription().id, namePrefix)}', 24)
    location: location
    coplanePrincipalId: principalId
  }
}

module appsGrants 'roleAssignments.bicep' = {
  name: 'coplane-apps-grants'
  scope: appsGroup
  params: {
    assignments: [
      {
        principalId: identities.outputs.principalIds.operator
        identity: identityNames.operator
        roleId: roles.contributor
        description: 'CoPlane platform: Azure Service Operator manages app resources'
      }
      {
        principalId: identities.outputs.principalIds.operator
        identity: identityNames.operator
        roleId: roles.rbacAdministrator
        description: 'CoPlane platform: Azure Service Operator gives app identities access to their own data'
        condition: replace(grantConditionTemplate, 'ROLE_IDS', join(appDataRoleIds, ', '))
      }
    ]
  }
}

module networkGrants 'roleAssignments.bicep' = {
  name: 'coplane-network-grants'
  scope: networkGroup
  params: {
    assignments: [
      {
        principalId: identities.outputs.principalIds.cluster
        identity: identityNames.cluster
        roleId: roles.networkContributor
        description: 'CoPlane platform: the Kubernetes cluster places nodes in its subnet'
      }
      {
        principalId: identities.outputs.principalIds.ingress
        identity: identityNames.ingress
        roleId: roles.networkContributor
        description: 'CoPlane platform: the ingress controller joins the gateway to its subnet'
      }
      {
        principalId: identities.outputs.principalIds.operator
        identity: identityNames.operator
        roleId: roles.networkContributor
        description: 'CoPlane platform: Azure Service Operator joins app databases to their subnet and private DNS zone'
      }
    ]
  }
}

module platformGrants 'roleAssignments.bicep' = {
  name: 'coplane-platform-grants'
  scope: platformGroup
  params: {
    assignments: [
      {
        principalId: identities.outputs.principalIds.ingress
        identity: identityNames.ingress
        roleId: roles.albConfigurationManager
        description: 'CoPlane platform: the ingress controller configures the shared gateway'
      }
      {
        principalId: identities.outputs.principalIds.ingress
        identity: identityNames.ingress
        roleId: roles.reader
        description: 'CoPlane platform: the ingress controller reads the gateway and its firewall policy'
      }
      {
        principalId: identities.outputs.principalIds.certificates
        identity: identityNames.certificates
        roleId: roles.dnsZoneContributor
        description: 'CoPlane platform: cert-manager proves ownership of the app domain'
      }
      {
        principalId: identities.outputs.principalIds.operator
        identity: identityNames.operator
        roleId: roles.rbacAdministrator
        description: 'CoPlane platform: Azure Service Operator lets app identities call the platform model'
        condition: replace(grantConditionTemplate, 'ROLE_IDS', join([roles.openAiUser], ', '))
      }
      {
        principalId: identities.outputs.principalIds.appPush
        identity: identityNames.appPush
        roleId: roles.acrPush
        description: 'CoPlane platform: app builds push images and move release tags in the app registry'
      }
    ]
  }
}

module deliveryGrants 'roleAssignments.bicep' = {
  name: 'coplane-delivery-grants'
  scope: deliveryGroup
  params: {
    assignments: [
      {
        principalId: identities.outputs.principalIds.bundlePush
        identity: identityNames.bundlePush
        roleId: roles.acrPush
        description: 'CoPlane platform: CoPlane publishes the platform configuration to its registry'
      }
    ]
  }
}

output roleAssignmentIds array = [
  contributor.id
  rbacAdministrator.id
  aksRbacClusterAdmin.id
]

output resourceGroups object = {
  platform: platformGroup.name
  network: networkGroup.name
  delivery: deliveryGroup.name
  apps: appsGroup.name
}

output stateStorageAccount string = state.outputs.name
