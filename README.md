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

- Terraform infrastructure: deploys 4x V100 VM with cloud-init that installs NVIDIA drivers 550, CUDA 12.4, Ollama, vLLM, and benchmark suite
- Cloud-init hardened against dpkg lock races, unattended-upgrades conflicts, home dir ownership, and python3-venv issues
- Benchmark suite: async Python client (`benchmark_client.py`) + bash orchestrator (`run_orchestrator.sh`)
- **Ollama benchmarks complete** for both models (results in `benchmarks/results/run_20260405_062728/`):

| Model | Engine | Result |
|---|---|---|
| Llama 3.3 70B | Ollama | 2.6 tok/s at concurrency=1, collapses at higher concurrency (95/96 errors at c=32) |
| Llama 4 Scout | Ollama | 100% timeouts at all concurrency levels (109B MoE too large for Ollama on 4x V100) |

### Remaining: vLLM Benchmarks

vLLM benchmarks are blocked on **Meta Llama HuggingFace access approval**. The HF token is valid but the gated model access request is pending review.

### Handoff Prompt (copy this to continue)

```
I'm continuing the Ollama vs vLLM multi-user benchmark project. Here's where we left off:

1. Ollama benchmarks are DONE — results saved in benchmarks/results/run_20260405_062728/
2. vLLM benchmarks need to be run — they were blocked by HuggingFace gated model access (403)
3. My HF token is approved now (check by running: curl -s -H "Authorization: Bearer hf_YOUR_TOKEN" https://huggingface.co/api/models/meta-llama/Llama-3.3-70B-Instruct)

Steps to complete:
a. Deploy the VM: fill in subscription_id in terraform.tfvars, run ./deploy.sh
b. Wait ~20 min for cloud-init (GPU drivers + software install)
c. SSH in and set the HF token:
   mkdir -p ~/.cache/huggingface && echo "YOUR_HF_TOKEN" > ~/.cache/huggingface/token
   export HF_TOKEN=YOUR_HF_TOKEN
d. Run vLLM benchmarks only — start vLLM server for each model with:
   /opt/vllm-env/bin/python -m vllm.entrypoints.openai.api_server \
     --model meta-llama/Llama-3.3-70B-Instruct \
     --tensor-parallel-size 4 --gpu-memory-utilization 0.90 --max-model-len 8192 \
     --host 0.0.0.0 --port 8000
   Then run: /opt/vllm-env/bin/python benchmarks/benchmark_client.py \
     --base-url http://localhost:8000/v1 --model meta-llama/Llama-3.3-70B-Instruct \
     --engine vllm --output benchmarks/results/llama33-70b_vllm.json
   Repeat for meta-llama/Llama-4-Scout-17B-16E-Instruct
e. Download results via SCP and compare with Ollama results
f. Destroy VM with ./destroy.sh
```

## Costs

This VM is expensive (~$10/hr). **Always destroy when not in use.**

Deploy only when needed, run your workload, then destroy.
