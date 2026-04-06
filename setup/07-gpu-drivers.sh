#!/bin/bash
# ==============================================================================
# SECTION 7: GPU DRIVERS & CUDA
# ==============================================================================

# NVIDIA CUDA keyring (Ubuntu 24.04)
wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update

# NVIDIA drivers + CUDA toolkit 12.8
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  cuda-drivers cuda-toolkit-12-8

# NVIDIA Container Toolkit (for Docker GPU passthrough)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
apt-get install -y nvidia-container-toolkit

echo "GPU drivers installed: CUDA 12.8 + Container Toolkit"
