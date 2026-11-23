# CoPlane onboarding for Azure

The Azure Resource Manager template and portal form a customer deploys to run CoPlane in their own Azure subscription. CoPlane sends each customer the link for the version they reviewed; every version is a tag and never changes.

1. An Entra ID administrator accepts CoPlane's admin consent link, which CoPlane sends.
2. A subscription Owner opens the link below for the version CoPlane sent, and deploys.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#blade/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fcoplane%2Fazure-onboarding%2Fv1.0.0%2Fazuredeploy.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fcoplane%2Fazure-onboarding%2Fv1.0.0%2FuiFormDefinition.json)

What it creates, which roles it grants CoPlane and how to revoke them are in the guide CoPlane sends with it.
