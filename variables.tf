###############################################################################
# Shared
###############################################################################

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "admin_username" {
  description = "Admin username for all VMs"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "os_image" {
  description = "VM OS image reference (shared across all VMs)"
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
  description = "HuggingFace API token for downloading gated models"
  type        = string
  sensitive   = true
}

variable "vllm_port" {
  description = "Port for vLLM API server (same on both GPU VMs)"
  type        = number
  default     = 8000
}

###############################################################################
# Gemma VM — primary inference server (4x A100 80GB)
###############################################################################

variable "gemma_vm_size" {
  description = "VM size for the Gemma inference server"
  type        = string
  default     = "Standard_NC96ads_A100_v4" # 4x A100 80GB, 96 vCPU, 880 GiB
}

variable "gemma_zone" {
  description = "Availability zone for Gemma VM"
  type        = string
  default     = "2"
}

variable "gemma_disk_size" {
  description = "OS disk size in GB for Gemma VM (model cache ~80GB)"
  type        = number
  default     = 256
}

variable "gemma_model_id" {
  description = "HuggingFace model ID for Gemma"
  type        = string
  default     = "google/gemma-4-31B-it"
}

variable "gemma_served_name" {
  description = "Model name exposed by Gemma vLLM API"
  type        = string
  default     = "gemma-4-31b"
}

variable "gemma_max_model_len" {
  description = "Maximum context length for Gemma (256K with 4x A100)"
  type        = number
  default     = 262144
}

variable "gemma_gpu_memory_utilization" {
  description = "GPU memory fraction for Gemma"
  type        = number
  default     = 0.95
}

variable "gemma_tp_size" {
  description = "Tensor parallel size for Gemma (number of GPUs)"
  type        = number
  default     = 4
}

variable "gemma_tool_call_parser" {
  description = "vLLM tool call parser for Gemma"
  type        = string
  default     = "gemma4"
}

###############################################################################
# Phi VM — GitHub operations sub-agent (1x A100 80GB)
###############################################################################

variable "phi_vm_size" {
  description = "VM size for the Phi inference server"
  type        = string
  default     = "Standard_NC24ads_A100_v4" # 1x A100 80GB, 24 vCPU, 220 GiB
}

variable "phi_zone" {
  description = "Availability zone for Phi VM"
  type        = string
  default     = "2"
}

variable "phi_disk_size" {
  description = "OS disk size in GB for Phi VM (model cache ~10GB)"
  type        = number
  default     = 128
}

variable "phi_model_id" {
  description = "HuggingFace model ID for Phi"
  type        = string
  default     = "microsoft/Phi-4-mini-instruct"
}

variable "phi_served_name" {
  description = "Model name exposed by Phi vLLM API"
  type        = string
  default     = "phi-4-mini"
}

variable "phi_max_model_len" {
  description = "Maximum context length for Phi"
  type        = number
  default     = 16384
}

variable "phi_gpu_memory_utilization" {
  description = "GPU memory fraction for Phi"
  type        = number
  default     = 0.90
}

variable "phi_tool_call_parser" {
  description = "vLLM tool call parser for Phi"
  type        = string
  default     = "hermes"
}

###############################################################################
# Workstation VM — developer tools (1x T4 16GB for Chrome/Playwright)
###############################################################################

variable "workstation_vm_size" {
  description = "VM size for the developer workstation"
  type        = string
  default     = "Standard_NC8as_T4_v3" # 1x T4 16GB, 8 vCPU, 56 GiB
}

variable "workstation_zone" {
  description = "Availability zone for Workstation VM"
  type        = string
  default     = "2"
}

variable "workstation_disk_size" {
  description = "OS disk size in GB for Workstation VM"
  type        = number
  default     = 512
}
