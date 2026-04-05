# Azure GPU VM for Local LLM Inference

On-demand Azure VM with 4x NVIDIA V100 GPUs (64GB total VRAM) for running 70B+ parameter LLMs locally. Managed with Terraform for easy deploy/destroy workflow.

## VM Specifications

| Spec | Value |
|---|---|
| VM Size | Standard_NC24s_v3 |
| GPUs | 4x NVIDIA Tesla V100 (16GB each, 64GB total) |
| vCPUs | 24 |
| RAM | 448 GB |
| OS | Ubuntu 22.04 LTS Gen2 |
| Region | Central US (Zone 1) |
| Disk | 256 GB Premium SSD |

## Prerequisites

- Azure CLI authenticated (`az login`)
- Terraform >= 1.0
- SSH key pair at `~/.ssh/id_rsa.pub`

## Quick Start

### Deploy

```bash
chmod +x deploy.sh destroy.sh
./deploy.sh
```

Wait ~15 minutes for cloud-init to install NVIDIA drivers and reboot. Then SSH in:

```bash
ssh azureuser@<public-ip>
nvidia-smi  # verify 4x V100 GPUs
```

### Run a Model

**With Ollama (simple):**
```bash
start-ollama-model richardyoung/kat-dev-72b:Q4_K_M
```

**With vLLM (better multi-GPU performance):**
```bash
start-vllm-server moonshotai/Kimi-Dev-72B
# API available at http://<public-ip>:8000
```

### Destroy (stop billing)

```bash
./destroy.sh
```

## Configuration

Edit `terraform.tfvars` to customize:

```hcl
vm_size = "Standard_NC6s_v3"   # Smaller: 1x V100, for 30B models
zone    = "3"                   # Alternative zone
```

## Recommended Models

| Model | Params | VRAM (Q4) | Agentic Coding | Notes |
|---|---|---|---|---|
| Kimi-Dev-72B | 72B | ~43 GB | SWE-bench 46.8% | Best for autonomous code editing |
| Qwen3-Coder 30B | 30B (3.3B active) | ~19 GB | SWE-bench 64.6% | MoE, fits on 1x V100 |
| Llama 3.3 70B | 70B | ~40 GB | Competitive with GPT-4o | General purpose |
| DeepSeek-V3.2 | 70B distilled | ~40 GB | Strong tool use | MIT license |

## Benchmarking: Ollama vs vLLM

The `benchmarks/` directory contains a suite for comparing Ollama and vLLM under concurrent load with Llama 3.3 70B and Llama 4 Scout.

### Run Benchmarks

After deploying and waiting for cloud-init (~15 min):

```bash
ssh azureuser@<public-ip>
cd ~/benchmarks   # or wherever you copy the benchmarks/ dir
bash run_orchestrator.sh
```

The orchestrator will:
1. Start Ollama, pull each model, benchmark at concurrency 1/2/4/8/16/32, stop
2. Start vLLM with tensor parallelism, benchmark same levels, stop
3. Output JSON results and a comparison summary table

### Metrics Measured

| Metric | Description |
|---|---|
| TTFT | Time to first token (ms) |
| Total Latency | Full request duration (ms) |
| Tokens/sec | Per-request generation speed |
| Aggregate Throughput | Total tokens/sec across all concurrent requests |

Results are saved to `benchmarks/results/run_<timestamp>/`.

### Run Individual Benchmarks

```bash
/opt/vllm-env/bin/python benchmarks/benchmark_client.py \
  --base-url http://localhost:8000/v1 \
  --model meta-llama/Llama-3.3-70B-Instruct \
  --engine vllm \
  --concurrency 1,4,16 \
  --output results.json
```

## Progress & Status (2026-04-05)

### Completed

- Terraform infrastructure: deploys 4x V100 VM with cloud-init (NVIDIA 550, CUDA 12.4, Ollama, vLLM)
- Cloud-init hardened against dpkg lock races, unattended-upgrades, home dir ownership, python3-venv issues
- Benchmark suite: async Python client + bash orchestrator
- **Ollama benchmarks complete** for both models (results in `benchmarks/results/run_20260405_062728/`)
- HuggingFace Meta Llama access approved

### Ollama Results

| Model | Engine | Result |
|---|---|---|
| Llama 3.3 70B (Q4_K_M) | Ollama | 2.6 tok/s at c=1, collapses at higher concurrency (95/96 errors at c=32) |
| Llama 4 Scout (Q4_K_M) | Ollama | 100% timeouts at all levels (109B MoE too large for Ollama on 4x V100) |

### V100 Compatibility Notes (critical for vLLM)

| Quantization | V100 (cc 7.0) | Notes |
|---|---|---|
| FP16 (unquantized) | OOM | 70B FP16 = ~140GB, 4x V100 = 64GB |
| AWQ 4-bit | Not supported | Requires compute capability >= 7.5 |
| GPTQ 4-bit | Supported | Min capability 6.0 |
| GGUF Q4_K_M | Supported | Same format as Ollama — fairest comparison |

**For fair comparison: use GGUF Q4_K_M on both Ollama and vLLM** (identical quantization).

### Remaining: vLLM GGUF Benchmarks

### Handoff Prompt (copy this to continue)

```
I'm continuing the Ollama vs vLLM benchmark project. Ollama benchmarks are done.
Now I need to run vLLM benchmarks using GGUF Q4_K_M (same quantization as Ollama for fair comparison).

V100 constraints discovered:
- FP16 70B: OOM (140GB won't fit in 64GB VRAM)
- AWQ: Not supported on V100 (needs compute capability 7.5, V100 is 7.0)
- GGUF Q4_K_M: Works — and matches Ollama's quantization exactly

Steps:
a. Fill in subscription_id in terraform.tfvars, run ./deploy.sh (disk is now 512GB)
b. Wait ~20 min for cloud-init
c. SSH in and set HF token:
   sudo chown azureuser:azureuser /home/azureuser
   mkdir -p ~/.cache/huggingface && echo "YOUR_HF_TOKEN" > ~/.cache/huggingface/token
   export HF_TOKEN=YOUR_HF_TOKEN
d. Download GGUF files:
   /opt/vllm-env/bin/python -c "
   from huggingface_hub import hf_hub_download
   hf_hub_download('bartowski/Llama-3.3-70B-Instruct-GGUF', 'Llama-3.3-70B-Instruct-Q4_K_M.gguf')
   "
e. Start vLLM with local GGUF file:
   /opt/vllm-env/bin/python -m vllm.entrypoints.openai.api_server \
     --model /path/to/Llama-3.3-70B-Instruct-Q4_K_M.gguf \
     --tokenizer meta-llama/Llama-3.3-70B-Instruct \
     --tensor-parallel-size 4 --gpu-memory-utilization 0.95 --max-model-len 4096 \
     --enforce-eager --host 0.0.0.0 --port 8000
f. Run benchmark:
   /opt/vllm-env/bin/python benchmarks/benchmark_client.py \
     --base-url http://localhost:8000/v1 --model Llama-3.3-70B-Instruct-Q4_K_M \
     --engine vllm --output benchmarks/results/llama33-70b_vllm.json
g. Repeat for Llama 4 Scout GGUF (unsloth/Llama-4-Scout-17B-16E-Instruct-GGUF)
h. Download results, compare with Ollama, destroy VM
```

## Costs

This VM is expensive (~$10/hr). **Always destroy when not in use.**

Deploy only when needed, run your workload, then destroy.
