#!/bin/bash
set -euo pipefail

echo "=== Detecting Azure identity ==="
OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null) || {
  echo "ERROR: Not logged in to Azure CLI. Run: az login"
  exit 1
}
DEPLOY_ID=$(echo -n "$OBJECT_ID" | md5sum | cut -c1-6)
RG_NAME="${RESOURCE_GROUP_NAME:-llm-${DEPLOY_ID}}"
SA_NAME="tfstate${DEPLOY_ID}"
echo "Deploy ID: $DEPLOY_ID"
echo "RG:        $RG_NAME"

echo ""
echo "WARNING: This will destroy ALL infrastructure managed by this Terraform configuration."
echo "Press Ctrl+C within 5 seconds to cancel..."
sleep 5

terraform init -reconfigure \
  -backend-config="resource_group_name=$RG_NAME" \
  -backend-config="storage_account_name=$SA_NAME" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=azure-llm.tfstate"

echo "Destroying infrastructure..."
terraform destroy -auto-approve

echo ""
echo "Cleaning up state backend..."
az storage account delete --name "$SA_NAME" --resource-group "$RG_NAME" --yes 2>/dev/null || true
az group delete --name "$RG_NAME" --yes --no-wait 2>/dev/null || true

echo "All resources destroyed. Billing stopped."
