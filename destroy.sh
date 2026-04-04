#!/bin/bash
set -euo pipefail

echo "WARNING: This will destroy ALL infrastructure managed by this Terraform configuration."
echo "Press Ctrl+C within 5 seconds to cancel..."
sleep 5

echo "Destroying infrastructure..."
terraform destroy -auto-approve

echo "All resources destroyed. Billing stopped."
