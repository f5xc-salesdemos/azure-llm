###############################################################################
# Shared
###############################################################################

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name (auto-generated from Azure identity if empty)"
  type        = string
  default     = ""
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
# Per-VM deploy toggles (set false to skip provisioning)
###############################################################################

variable "llm01_deployed" {
  description = "Deploy llm01 (large LLM server)"
  type        = bool
  default     = true
}

variable "llm02_deployed" {
  description = "Deploy llm02 (small/medium/vision LLM server)"
  type        = bool
  default     = true
}

variable "llm03_deployed" {
  description = "Deploy llm03 (PersonaPlex speech-to-speech server)"
  type        = bool
  default     = true
}

variable "workstation_deployed" {
  description = "Deploy workstation VM"
  type        = bool
  default     = true
}

###############################################################################
# llm01 — Large LLM inference server (4x A100 80GB)
###############################################################################

variable "llm01_vm_size" {
  description = "VM size for llm01 (large LLM)"
  type        = string
  default     = "Standard_NC96ads_A100_v4" # 4x A100 80GB, 96 vCPU, 880 GiB
}

variable "llm01_zone" {
  description = "Availability zone for llm01"
  type        = string
  default     = "2"
}

variable "llm01_disk_size" {
  description = "OS disk size in GB for llm01"
  type        = number
  default     = 256
}

variable "llm01_model_id" {
  description = "HuggingFace model ID for llm01 (large LLM)"
  type        = string
  default     = "google/gemma-4-31B-it"
}

variable "llm01_served_name" {
  description = "Abstract served-model-name for the large LLM (model-agnostic)"
  type        = string
  default     = "large-llm"
}

variable "llm01_max_model_len" {
  description = "Maximum context length for llm01"
  type        = number
  default     = 262144
}

variable "llm01_gpu_memory_utilization" {
  description = "GPU memory fraction for llm01"
  type        = number
  default     = 0.95
}

variable "llm01_tp_size" {
  description = "Tensor parallel size for llm01 (number of GPUs)"
  type        = number
  default     = 4
}

variable "llm01_tool_call_parser" {
  description = "vLLM tool call parser for llm01"
  type        = string
  default     = "gemma4"
}

variable "llm01_reasoning_parser" {
  description = "vLLM reasoning parser for llm01"
  type        = string
  default     = "gemma4"
}

variable "llm01_hf_overrides" {
  description = "JSON string for vLLM --hf-overrides (e.g. YaRN rope config for extended context)"
  type        = string
  default     = ""
}

variable "llm01_allow_long_context" {
  description = "Set VLLM_ALLOW_LONG_MAX_MODEL_LEN=1 for context lengths beyond model default"
  type        = bool
  default     = false
}

variable "llm01_extra_served_names" {
  description = "Additional served-model-name aliases, comma-separated (for consolidated single-model mode)"
  type        = string
  default     = ""
}

###############################################################################
# llm02 — Small/Medium/Vision LLM server (4x A100 80GB, three models)
###############################################################################

variable "llm02_vm_size" {
  description = "VM size for llm02 (small/medium/vision LLM)"
  type        = string
  default     = "Standard_NC96ads_A100_v4" # 4x A100 80GB, 96 vCPU, 880 GiB
}

variable "llm02_zone" {
  description = "Availability zone for llm02"
  type        = string
  default     = "2"
}

variable "llm02_disk_size" {
  description = "OS disk size in GB for llm02"
  type        = number
  default     = 256
}

# Small LLM (port 8000)
variable "small_llm_model_id" {
  description = "HuggingFace model ID for small LLM"
  type        = string
  default     = "microsoft/Phi-4-mini-instruct"
}

variable "small_llm_served_name" {
  description = "Abstract served-model-name for the small LLM (model-agnostic)"
  type        = string
  default     = "small-llm"
}

variable "small_llm_max_model_len" {
  description = "Maximum context length for small LLM"
  type        = number
  default     = 131072
}

variable "small_llm_gpu_memory_utilization" {
  description = "GPU memory fraction for small LLM"
  type        = number
  default     = 0.88
}

variable "small_llm_tool_call_parser" {
  description = "vLLM tool call parser for small LLM"
  type        = string
  default     = "hermes"
}

variable "small_llm_port" {
  description = "Port for small LLM vLLM API"
  type        = number
  default     = 8000
}

variable "small_llm_cuda_devices" {
  description = "CUDA device IDs for small LLM"
  type        = string
  default     = "0"
}

variable "small_llm_speculative_model" {
  description = "Speculative decoding model ('[ngram]' for n-gram, '' to disable)"
  type        = string
  default     = "[ngram]"
}

variable "small_llm_num_speculative_tokens" {
  description = "Number of speculative tokens per decoding step"
  type        = number
  default     = 5
}

variable "small_llm_ngram_prompt_lookup_min" {
  description = "Minimum n-gram size for prompt-lookup speculative decoding"
  type        = number
  default     = 4
}

variable "small_llm_ngram_prompt_lookup_max" {
  description = "Maximum n-gram size for prompt-lookup speculative decoding"
  type        = number
  default     = 8
}

variable "small_llm_enable_chunked_prefill" {
  description = "Enable chunked prefill (must be false when speculative decoding is active)"
  type        = bool
  default     = false
}

variable "small_llm_vllm_compile_level" {
  description = "vLLM torch compile optimization level (0=off, 3=max CUDA graph capture)"
  type        = number
  default     = 3
}

# Vision LLM (port 8001)
variable "vision_llm_model_id" {
  description = "HuggingFace model ID for vision LLM"
  type        = string
  default     = "Qwen/Qwen2.5-VL-7B-Instruct"
}

variable "vision_llm_served_name" {
  description = "Abstract served-model-name for the vision LLM (model-agnostic)"
  type        = string
  default     = "vision-llm"
}

variable "vision_llm_max_model_len" {
  description = "Maximum context length for vision LLM"
  type        = number
  default     = 32768
}

variable "vision_llm_gpu_memory_utilization" {
  description = "GPU memory fraction for vision LLM"
  type        = number
  default     = 0.90
}

variable "vision_llm_port" {
  description = "Port for vision LLM vLLM API"
  type        = number
  default     = 8001
}

variable "vision_llm_cuda_devices" {
  description = "CUDA device IDs for vision LLM"
  type        = string
  default     = "2"
}

# Medium LLM (port 8002)
variable "medium_llm_model_id" {
  description = "HuggingFace model ID for medium LLM"
  type        = string
  default     = "mistralai/Devstral-Small-2-24B-Instruct-2512"
}

variable "medium_llm_served_name" {
  description = "Abstract served-model-name for the medium LLM (model-agnostic)"
  type        = string
  default     = "medium-llm"
}

variable "medium_llm_max_model_len" {
  description = "Maximum context length for medium LLM"
  type        = number
  default     = 262144
}

variable "medium_llm_gpu_memory_utilization" {
  description = "GPU memory fraction for medium LLM"
  type        = number
  default     = 0.95
}

variable "medium_llm_tp_size" {
  description = "Tensor parallel size for medium LLM (number of GPUs)"
  type        = number
  default     = 2
}

variable "medium_llm_port" {
  description = "Port for medium LLM vLLM API"
  type        = number
  default     = 8002
}

variable "medium_llm_cuda_devices" {
  description = "CUDA device IDs for medium LLM"
  type        = string
  default     = "1,3"
}

variable "medium_llm_tool_call_parser" {
  description = "vLLM tool call parser for medium LLM"
  type        = string
  default     = "mistral"
}

variable "medium_llm_reasoning_parser" {
  description = "vLLM reasoning parser for medium LLM (empty = disabled)"
  type        = string
  default     = ""
}

variable "medium_llm_hf_overrides" {
  description = "JSON string for vLLM --hf-overrides on medium LLM"
  type        = string
  default     = ""
}

variable "medium_llm_allow_long_context" {
  description = "Set VLLM_ALLOW_LONG_MAX_MODEL_LEN=1 for medium LLM"
  type        = bool
  default     = false
}

variable "medium_llm_extra_served_names" {
  description = "Additional served-model-name aliases for medium LLM, comma-separated"
  type        = string
  default     = ""
}

variable "medium_llm_enforce_eager" {
  description = "Disable torch.compile and CUDA graphs for medium LLM (workaround for V1 engine IPC on some hardware)"
  type        = bool
  default     = false
}

variable "medium_llm_chat_template_content_format" {
  description = "Chat template content format for medium LLM (empty = omit flag)"
  type        = string
  default     = "string"
}

variable "vision_llm_tool_call_parser" {
  description = "vLLM tool call parser for vision LLM"
  type        = string
  default     = "hermes"
}

###############################################################################
# llm03 — PersonaPlex speech-to-speech server (1x H100 NVL 94GB)
###############################################################################

variable "llm03_vm_size" {
  description = "VM size for llm03 (PersonaPlex speech-to-speech)"
  type        = string
  default     = "Standard_NC40ads_H100_v5" # 1x H100 NVL 94GB, 40 vCPU, 320 GiB
}

variable "llm03_zone" {
  description = "Availability zone for llm03"
  type        = string
  default     = "2"
}

variable "llm03_disk_size" {
  description = "OS disk size in GB for llm03"
  type        = number
  default     = 256
}

variable "llm03_model_id" {
  description = "HuggingFace model ID for PersonaPlex speech-to-speech"
  type        = string
  default     = "nvidia/personaplex-7b-v1"
}

variable "llm03_port" {
  description = "Port for PersonaPlex WebSocket server"
  type        = number
  default     = 8998
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
