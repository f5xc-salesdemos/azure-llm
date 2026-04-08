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
# llm01 — Large LLM inference server (4x A100 80GB)
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
  description = "Abstract served-model-name for the large LLM (model-agnostic)"
  type        = string
  default     = "large-llm"
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
# llm02 — Small/Medium/Vision LLM server (4x A100 80GB, three models)
###############################################################################

variable "phi_vm_size" {
  description = "VM size for the sub-agent inference server"
  type        = string
  default     = "Standard_NC96ads_A100_v4" # 4x A100 80GB, 96 vCPU, 880 GiB
}

variable "phi_zone" {
  description = "Availability zone for Phi VM"
  type        = string
  default     = "2"
}

variable "phi_disk_size" {
  description = "OS disk size in GB for Phi VM (three model caches ~100GB)"
  type        = number
  default     = 256
}

# Model 1: Phi-4-mini (port 8000) — GitHub operations sub-agent
variable "phi_model_id" {
  description = "HuggingFace model ID for Phi"
  type        = string
  default     = "microsoft/Phi-4-mini-instruct"
}

variable "phi_served_name" {
  description = "Abstract served-model-name for the small LLM (model-agnostic)"
  type        = string
  default     = "small-llm"
}

variable "phi_max_model_len" {
  description = "Maximum context length for Phi (128K on dedicated GPU 0)"
  type        = number
  default     = 131072
}

variable "phi_gpu_memory_utilization" {
  description = "GPU memory fraction for Phi (dedicated GPU 0)"
  type        = number
  default     = 0.88
}

variable "phi_tool_call_parser" {
  description = "vLLM tool call parser for Phi"
  type        = string
  default     = "hermes"
}

variable "phi_port" {
  description = "Port for Phi vLLM API"
  type        = number
  default     = 8000
}

variable "phi_cuda_devices" {
  description = "CUDA device IDs for Phi (dedicated GPU 0)"
  type        = string
  default     = "0"
}

variable "phi_speculative_model" {
  description = "Speculative decoding model ('[ngram]' for n-gram, '' to disable)"
  type        = string
  default     = "[ngram]"
}

variable "phi_num_speculative_tokens" {
  description = "Number of speculative tokens per decoding step"
  type        = number
  default     = 5
}

variable "phi_ngram_prompt_lookup_min" {
  description = "Minimum n-gram size for prompt-lookup speculative decoding"
  type        = number
  default     = 4
}

variable "phi_ngram_prompt_lookup_max" {
  description = "Maximum n-gram size for prompt-lookup speculative decoding"
  type        = number
  default     = 8
}

variable "phi_enable_chunked_prefill" {
  description = "Enable chunked prefill (must be false when speculative decoding is active)"
  type        = bool
  default     = false
}

variable "phi_vllm_compile_level" {
  description = "vLLM torch compile optimization level (0=off, 3=max CUDA graph capture)"
  type        = number
  default     = 3
}

# Model 2: Qwen2.5-VL-7B (port 8001) — vision/multimodal sub-agent
variable "qwen_vl_model_id" {
  description = "HuggingFace model ID for Qwen2.5-VL"
  type        = string
  default     = "Qwen/Qwen2.5-VL-7B-Instruct"
}

variable "qwen_vl_served_name" {
  description = "Abstract served-model-name for the vision LLM (model-agnostic)"
  type        = string
  default     = "vision-llm"
}

variable "qwen_vl_max_model_len" {
  description = "Maximum context length for Qwen VL"
  type        = number
  default     = 32768
}

variable "qwen_vl_gpu_memory_utilization" {
  description = "GPU memory fraction for Qwen VL (dedicated GPU 2)"
  type        = number
  default     = 0.90
}

variable "qwen_vl_port" {
  description = "Port for Qwen VL vLLM API"
  type        = number
  default     = 8001
}

variable "qwen_vl_cuda_devices" {
  description = "CUDA device IDs for Qwen-VL (dedicated GPU 2)"
  type        = string
  default     = "2"
}

# Model 3: Devstral-Small-2-24B (port 8002) — coding agent / tool calling / API orchestration
variable "devstral_model_id" {
  description = "HuggingFace model ID for Devstral"
  type        = string
  default     = "mistralai/Devstral-Small-2-24B-Instruct-2512"
}

variable "devstral_served_name" {
  description = "Abstract served-model-name for the medium LLM (model-agnostic)"
  type        = string
  default     = "medium-llm"
}

variable "devstral_max_model_len" {
  description = "Maximum context length for Devstral (256K with TP=2 on 2x A100)"
  type        = number
  default     = 262144
}

variable "devstral_gpu_memory_utilization" {
  description = "GPU memory fraction for Devstral (GPU 1+3, TP=2)"
  type        = number
  default     = 0.95
}

variable "devstral_tp_size" {
  description = "Tensor parallel size for Devstral (number of GPUs)"
  type        = number
  default     = 2
}

variable "devstral_port" {
  description = "Port for Devstral vLLM API"
  type        = number
  default     = 8002
}

variable "devstral_cuda_devices" {
  description = "CUDA device IDs for Devstral (GPU 1+3, TP=2)"
  type        = string
  default     = "1,3"
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
