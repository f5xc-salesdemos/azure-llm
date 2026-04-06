#!/bin/bash
# ==============================================================================
# SECTION 6: CLOUD & INFRASTRUCTURE CLIs
# ==============================================================================

# ---- Azure CLI (may already be on Azure VM) ----
if command -v az &>/dev/null; then
  echo "Azure CLI already installed: $(az version --query '\"azure-cli\"' -o tsv)"
else
  curl -sL https://aka.ms/InstallAzureCLIDeb | bash
fi

# ---- GitHub CLI ----
if command -v gh &>/dev/null; then
  echo "GitHub CLI already installed"
else
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list
  apt-get update && apt-get install -y gh
fi

# ---- Terraform ----
if command -v terraform &>/dev/null; then
  echo "Terraform already installed"
else
  wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
  apt-get update && apt-get install -y terraform
fi

# ---- kubectl ----
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# ---- Helm ----
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ---- Google Cloud CLI ----
apt-get install -y apt-transport-https ca-certificates gnupg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
apt-get update && apt-get install -y google-cloud-cli 2>/dev/null || echo "GCP CLI install skipped (may not be available)"

# ---- AWS CLI v2 ----
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp/ && /tmp/aws/install --update && rm -rf /tmp/aws /tmp/awscliv2.zip

echo "Cloud CLIs installed: Azure, GitHub, Terraform, kubectl, Helm, GCP, AWS"
