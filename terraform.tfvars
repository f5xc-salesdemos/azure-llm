location            = "centralus"
admin_username      = "azureuser"
ssh_public_key_path = "~/.ssh/id_rsa.pub"

# Deploy toggles — 2 servers: llm02 (Qwen 3.6 + Phi) + workstation
llm01_deployed       = false
llm02_deployed       = true
llm03_deployed       = false
workstation_deployed = true

# llm02 — 4x A100 80GB: Phi-4-mini (GPU 0) + Qwen 3.6 (GPUs 1,2)
llm02_vm_size = "Standard_NC96ads_A100_v4"
llm02_zone    = "2"

# Small LLM: Phi-4-mini on GPU 0 — full A100 utilization
small_llm_cuda_devices           = "0"
small_llm_gpu_memory_utilization = 0.95

# Vision LLM: DISABLED
vision_llm_model_id = ""

# Medium LLM: Qwen 3.6-35B-A3B on GPUs 1,2 (TP=2, 1M context via YaRN)
medium_llm_model_id                     = "Qwen/Qwen3.6-35B-A3B"
medium_llm_served_name                  = "medium-llm"
medium_llm_tp_size                      = 2
medium_llm_cuda_devices                 = "1,2"
medium_llm_max_model_len                = 1010000
medium_llm_gpu_memory_utilization       = 0.95
medium_llm_tool_call_parser             = "qwen3_coder"
medium_llm_reasoning_parser             = "qwen3"
medium_llm_allow_long_context           = true
medium_llm_enforce_eager                = true
medium_llm_extra_served_names           = "large-llm"
medium_llm_hf_overrides                 = "{\"text_config\":{\"rope_parameters\":{\"rope_type\":\"yarn\",\"rope_theta\":10000000,\"factor\":4.0,\"original_max_position_embeddings\":262144,\"partial_rotary_factor\":0.25,\"mrope_interleaved\":true,\"mrope_section\":[11,11,10]}}}"
medium_llm_chat_template_content_format = ""

# llm03 — PersonaPlex (disabled)
llm03_vm_size = "Standard_NC40ads_H100_v5"
llm03_zone    = ""

# Workstation — T4 for Chrome/Playwright
workstation_vm_size = "Standard_NC8as_T4_v3"
workstation_zone    = "2"
