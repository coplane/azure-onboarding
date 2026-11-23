# CoPlane onboarding for Azure

This repository holds the template that gives CoPlane access to an Azure subscription, so that CoPlane can run its app platform there. The platform runs in your own subscription, and CoPlane operates it. This model is called BYOC (Bring Your Own Cloud).

This is version **v1.0.1**. Each version is a Git tag that never changes, so you deploy exactly the version that you reviewed. The [releases](https://github.com/coplane/azure-onboarding/releases) list what changed in each version.

| File | What it is |
|---|---|
| `main.bicep` | The template source, at subscription scope. Its modules are `identities.bicep`, `roleAssignments.bicep` and `state.bicep`. |
| `azuredeploy.json` | The same template compiled to an Azure Resource Manager template. The portal and the Azure CLI deploy this file. |
| `uiFormDefinition.json` | The form that the Azure portal shows for this template. |

## Before you start

You need these people and things:

- A Microsoft Entra administrator who can approve an application for your tenant. For example, a Global Administrator or a Cloud Application Administrator.
- A subscription for CoPlane, with an Owner who deploys the template.
- The region where the platform runs, agreed with CoPlane.

## Deploy

### 1. Approve CoPlane's application

As an Entra administrator, open this link and choose **Accept**:

```text
https://login.microsoftonline.com/organizations/v2.0/adminconsent?client_id=58dc25ab-89f7-44bc-8c3f-35817e38b787&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default&redirect_uri=https%3A%2F%2Fcoplane.com%2Fazure%2Fconnected
```

The approval adds CoPlane's application, `CoPlane`, under **Enterprise applications** in your tenant. Its application (client) ID is `58dc25ab-89f7-44bc-8c3f-35817e38b787`. The application alone has no access to anything. Step 2 gives it access to one subscription.

If you prefer the command line, an administrator can add the application with `az ad sp create --id 58dc25ab-89f7-44bc-8c3f-35817e38b787` instead.

### 2. Deploy the template

As a subscription Owner, select **Deploy to Azure**:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#blade/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fcoplane%2Fazure-onboarding%2Fv1.0.1%2Fazuredeploy.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fcoplane%2Fazure-onboarding%2Fv1.0.1%2FuiFormDefinition.json)

In the form:

1. Choose the subscription for CoPlane and the region.
2. Keep the name prefix `coplane`, unless CoPlane asked for another prefix.
3. Enter the object ID of CoPlane's application. In Microsoft Entra ID, open **Enterprise applications**, select **CoPlane** and copy its **Object ID**. This ID is not the application (client) ID. With the Azure CLI, run `az ad sp show --id 58dc25ab-89f7-44bc-8c3f-35817e38b787 --query id -o tsv`.
4. Read the **Access granted** tab.
5. Select **Review + create**, then **Create**. The deployment typically takes about two minutes.

To deploy from the command line or from your own pipeline instead, sign in to the Azure CLI as a subscription Owner. Replace `<subscription-id>` and `<region>`, then run these commands:

```bash
principal_id=$(az ad sp show --id 58dc25ab-89f7-44bc-8c3f-35817e38b787 --query id -o tsv)

az deployment sub create \
  --subscription <subscription-id> \
  --location <region> \
  --name coplane-onboarding \
  --template-uri https://raw.githubusercontent.com/coplane/azure-onboarding/v1.0.1/azuredeploy.json \
  --parameters principalId="$principal_id" namePrefix=coplane location=<region>
```

To see what the template creates before you deploy it, run `az deployment sub what-if` with the same arguments.

A second deployment of the same version changes nothing, so you can run it again safely.

### 3. Send CoPlane the details

Send CoPlane your tenant ID, the subscription ID, the region and the deployment's `stateStorageAccount` output. CoPlane then builds the platform in your subscription.

## What the template grants CoPlane

The template gives CoPlane's application three role assignments on the subscription.

| Role | What CoPlane uses it for |
|---|---|
| Contributor | Creating and updating the platform's resources with Terraform. |
| Role Based Access Control Administrator, with a condition | Letting the platform's cluster pull from its registry, and giving named CoPlane engineers admin access to the cluster. |
| Azure Kubernetes Service RBAC Cluster Admin | Installing and upgrading the platform's components in the cluster, and investigating incidents. |

The condition on Role Based Access Control Administrator lets CoPlane create or delete role assignments for two roles only:

| Role | ID |
|---|---|
| AcrPull | `7f951dda-4ed3-4680-a7ca-43fe172d538d` |
| Azure Kubernetes Service RBAC Cluster Admin | `b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b` |

CoPlane therefore cannot grant Owner, User Access Administrator, Role Based Access Control Administrator, Contributor or any other role. CoPlane also cannot remove any other role assignment. The condition is this expression, with the two IDs above:

```text
(
  (!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'}))
  OR
  (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {<the two IDs>})
)
AND
(
  (!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}))
  OR
  (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {<the two IDs>})
)
```

The condition limits what CoPlane can grant. It does not limit what CoPlane can reach. Contributor can manage how the platform's identities sign in, and cluster admin can run workloads as those identities. So CoPlane, as the platform's operator, can reach your apps' data. CoPlane's changes to Azure resources appear in the subscription's activity log, and actions in the cluster appear in the cluster's audit log. You can revoke all of CoPlane's access at any time.

## What the template creates

The template creates four resource groups. These names use the default prefix `coplane`.

| Resource group | What it holds |
|---|---|
| `rg-coplane` | The cluster, the registry for app images, the gateway and its firewall policy, the app domain, the AI model, and the platform's identities |
| `rg-coplane-network` | The virtual network and the private DNS zone of the app databases |
| `rg-coplane-delivery` | The registry for the platform's configuration, which the cluster pulls |
| `rg-coplane-apps` | The databases, storage accounts and key vaults of each app |

The template creates the resource groups empty. CoPlane builds the platform in them later.

Some of the platform's components need roles that CoPlane is not allowed to grant. The template therefore creates these six managed identities in `rg-coplane` and grants their roles once. CoPlane's Terraform only finds them by name and connects each one to its component.

| Identity | Role | Scope |
|---|---|---|
| `coplane-cluster` (the cluster) | Network Contributor | `rg-coplane-network` |
| `coplane-alb` (the ingress controller) | Network Contributor | `rg-coplane-network` |
| | AppGw for Containers Configuration Manager | `rg-coplane` |
| | Reader | `rg-coplane` |
| `coplane-cert-manager` (certificates) | DNS Zone Contributor | `rg-coplane` |
| `coplane-aso` (Azure Service Operator, which creates each app's resources) | Contributor | `rg-coplane-apps` |
| | Role Based Access Control Administrator, only for Storage Blob Data Contributor, Key Vault Secrets User and Key Vault Secrets Officer | `rg-coplane-apps` |
| | Role Based Access Control Administrator, only for Cognitive Services OpenAI User | `rg-coplane` |
| | Network Contributor | `rg-coplane-network` |
| `coplane-app-push` (app builds) | AcrPush | `rg-coplane` |
| `coplane-bundle-push` (the platform's configuration) | AcrPush | `rg-coplane-delivery` |

The two push identities are the only identities that can write to the registries. App builds can write only to the app image registry. They cannot change the platform's configuration, which the cluster applies with admin rights.

The template also creates a storage account in `rg-coplane` for CoPlane's Terraform state. Its name is in the deployment's `stateStorageAccount` output. The state stays in your subscription. The account has these protections:

- It accepts Microsoft Entra sign-in only. Account keys and anonymous blob access are off.
- It keeps every version of each file, and it keeps deleted files and containers for 30 days.
- It has a delete lock, which CoPlane cannot remove.
- CoPlane's application has Storage Blob Data Contributor on this account only.

## Revoking access

Either of these actions cuts CoPlane off immediately. Your apps keep running, but CoPlane can no longer deploy, update or support them.

```bash
# Remove CoPlane's role assignments on the subscription and on the Terraform state
principal_id=$(az ad sp show --id 58dc25ab-89f7-44bc-8c3f-35817e38b787 --query id -o tsv)
az role assignment delete --assignee "$principal_id" --scope /subscriptions/<subscription-id>
az role assignment delete --assignee "$principal_id" \
  --scope "$(az storage account list -g rg-coplane --query "[?starts_with(name, 'tfstate')].id" -o tsv)"

# Or delete CoPlane's application from your tenant, so that it cannot sign in at all
az ad sp delete --id 58dc25ab-89f7-44bc-8c3f-35817e38b787
```

Deleting the deployment record under **Deployments** does not remove any role assignment. The resource groups, the identities and their role assignments stay in place, but they no longer let CoPlane do anything.

## Questions

Contact your CoPlane team. The [CoPlane BYOC documentation](https://docs.coplane.com/byoc) describes how the platform works in your subscription.
