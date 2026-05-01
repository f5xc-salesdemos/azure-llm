#!/bin/bash
set -euo pipefail

LOCATION="${LOCATION:-centralus}"

echo "=== Detecting Azure identity ==="
OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null) || {
  echo "ERROR: Not logged in to Azure CLI. Run: az login"
  exit 1
}
DEPLOY_ID=$(echo -n "$OBJECT_ID" | md5sum | cut -c1-6)
UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || echo "unknown")
echo "User:      $UPN"
echo "Deploy ID: $DEPLOY_ID"

RG_NAME="${RESOURCE_GROUP_NAME:-llm-${DEPLOY_ID}}"
SA_NAME="tfstate${DEPLOY_ID}"
echo "RG:        $RG_NAME"
echo "State SA:  $SA_NAME"

echo ""
echo "=== Bootstrapping Terraform state backend ==="
az group create --name "$RG_NAME" --location "$LOCATION" -o none 2>/dev/null || true
az storage account create --name "$SA_NAME" --resource-group "$RG_NAME" \
  --location "$LOCATION" --sku Standard_LRS --kind StorageV2 -o none 2>/dev/null || true
az storage container create --name tfstate --account-name "$SA_NAME" \
  --auth-mode login -o none 2>/dev/null || true

echo ""
echo "=== Initializing Terraform ==="
terraform init \
  -backend-config="resource_group_name=$RG_NAME" \
  -backend-config="storage_account_name=$SA_NAME" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=azure-llm.tfstate"

echo ""
echo "=== Planning deployment ==="
terraform plan -out=tfplan

echo ""
echo "=== Deploying infrastructure ==="
terraform apply tfplan

echo ""
echo "=== Deployment complete ==="
terraform output

echo ""
echo "NOTE: Cloud-init will install NVIDIA drivers and reboot the VM."
echo "Wait ~10-15 minutes after deploy for GPU setup to complete."
echo "Then SSH in and run: nvidia-smi"
