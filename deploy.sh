#!/bin/bash
set -euo pipefail

echo "Initializing Terraform..."
terraform init

echo ""
echo "Planning deployment..."
terraform plan -out=tfplan

echo ""
echo "Deploying infrastructure..."
terraform apply tfplan

echo ""
echo "Deployment complete."
terraform output

echo ""
echo "NOTE: Cloud-init will install NVIDIA drivers and reboot the VM."
echo "Wait ~10-15 minutes after deploy for GPU setup to complete."
echo "Then SSH in and run: nvidia-smi"
