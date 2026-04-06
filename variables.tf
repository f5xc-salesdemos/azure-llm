variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "location" {
  description = "Azure region (e.g., centralus, eastus, westus2)"
  type        = string
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "gpu-llm-vm"
}

variable "vm_size" {
  description = "Size of the VM. Default: 1x A100 80GB for optimal vLLM inference"
  type        = string
  default     = "Standard_NC24ads_A100_v4"

  validation {
    condition = contains([
      # A100 (cc 8.0) — recommended for vLLM (AWQ, FlashAttention2, BFloat16, FP8)
      "Standard_NC24ads_A100_v4",  # 1x A100 80GB, 24 vCPUs, 220 GiB RAM
      "Standard_NC48ads_A100_v4",  # 2x A100 80GB, 48 vCPUs, 440 GiB RAM
      "Standard_NC96ads_A100_v4",  # 4x A100 80GB, 96 vCPUs, 880 GiB RAM
      # V100 (cc 7.0) — legacy, GPTQ only, no AWQ/FlashAttention2
      "Standard_NC6s_v3",          # 1x V100 16GB
      "Standard_NC12s_v3",         # 2x V100 32GB
      "Standard_NC24s_v3",         # 4x V100 64GB
      # T4 (cc 7.5) — budget option, AWQ supported but low bandwidth
      "Standard_NC4as_T4_v3",      # 1x T4 16GB
      "Standard_NC8as_T4_v3",      # 2x T4 32GB
      "Standard_NC16as_T4_v3",     # 4x T4 64GB
    ], var.vm_size)
    error_message = "Must be a GPU VM size available in centralus."
  }
}

variable "zone" {
  description = "Availability zone (set to empty string to let Azure choose)"
  type        = string
  default     = ""
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB. 512GB recommended for model weights."
  type        = number
  default     = 512
}

variable "os_image" {
  description = "VM OS image reference"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

variable "hf_token" {
  description = "HuggingFace API token for downloading gated models (Meta Llama, Google Gemma)"
  type        = string
  sensitive   = true
}

variable "model_id" {
  description = "HuggingFace model ID for vLLM to serve"
  type        = string
  default     = "google/gemma-4-31B-it"
}

variable "served_model_name" {
  description = "Model name exposed by vLLM API (used in Claude Code config)"
  type        = string
  default     = "gemma-4-31b"
}

variable "max_model_len" {
  description = "Maximum context length in tokens"
  type        = number
  default     = 131072
}

variable "gpu_memory_utilization" {
  description = "Fraction of GPU memory for model + KV cache (0.0-1.0)"
  type        = number
  default     = 0.95
}

variable "tool_call_parser" {
  description = "vLLM tool call parser (gemma4, hermes, llama4_pythonic, qwen3_coder, glm47)"
  type        = string
  default     = "gemma4"
}

variable "vllm_port" {
  description = "Port for vLLM API server"
  type        = number
  default     = 8000
}
