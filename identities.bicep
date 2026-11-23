// The platform identities whose roles CoPlane can't grant itself. CoPlane's Terraform finds
// them by name and federates each: the controllers with their Kubernetes service accounts,
// the two push identities with the CI jobs allowed to push to the registry.
// A plain object, not a typed one, so the template stays in ARM's classic format that the portal
// can read (see roleAssignments.bicep).
@description('The identities\' names: cluster, ingress, certificates, operator, appPush and bundlePush.')
param names object
param location string

resource cluster 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.cluster
  location: location
}

resource ingress 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.ingress
  location: location
}

resource certificates 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.certificates
  location: location
}

resource operator 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.operator
  location: location
}

resource appPush 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.appPush
  location: location
}

resource bundlePush 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.bundlePush
  location: location
}

output principalIds object = {
  cluster: cluster.properties.principalId
  ingress: ingress.properties.principalId
  certificates: certificates.properties.principalId
  operator: operator.properties.principalId
  appPush: appPush.properties.principalId
  bundlePush: bundlePush.properties.principalId
}
