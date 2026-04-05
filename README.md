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
| GPTQ 4-bit | **Works** | Min capability 6.0. Use `--quantization gptq` |
| GGUF Q4_K_M | OOM in vLLM | Loads but dequantization overhead fills VRAM, no room for KV cache |

**For vLLM on V100: must use GPTQ 4-bit** with `--enforce-eager --max-model-len 2048 --max-num-seqs 32`.

Quantization comparison (both are 4-bit, different methods):
- **Ollama**: Q4_K_M (GGUF mixed-precision 4-bit) — Ollama's default
- **vLLM**: GPTQ (INT4 packed weights) — only 4-bit method that fits on V100

### Current VM State (checkpoint 2026-04-05 18:55 UTC)

**VM is RUNNING** at `20.112.232.231` (billing active ~$10/hr)
- vLLM GPTQ Llama 3.3 70B benchmark is running via nohup
- Results saving to: `/home/azureuser/benchmarks/results/vllm_gptq_20260405_185242/`
- Llama 4 Scout vLLM benchmark still needs to be run after

### Handoff Prompt (copy this to continue)

```
I'm continuing the Ollama vs vLLM benchmark project. Here's the exact state:

COMPLETED:
- Ollama benchmarks for Llama 3.3 70B and Llama 4 Scout (results in benchmarks/results/run_20260405_062728/)
- Ollama used Q4_K_M quantization (GGUF)

IN PROGRESS (may be complete by now):
- vLLM GPTQ Llama 3.3 70B benchmark is running on VM 20.112.232.231
- Results at: /home/azureuser/benchmarks/results/vllm_gptq_20260405_185242/
- vLLM server command that worked:
  /opt/vllm-env/bin/python -m vllm.entrypoints.openai.api_server \
    --model shuyuej/Llama-3.3-70B-Instruct-GPTQ --quantization gptq \
    --tensor-parallel-size 4 --gpu-memory-utilization 0.95 --max-model-len 2048 \
    --max-num-seqs 32 --enforce-eager --host 0.0.0.0 --port 8000

REMAINING:
1. Check if Llama 3.3 70B vLLM benchmark completed:
   ssh azureuser@20.112.232.231
   ls -la /home/azureuser/benchmarks/results/vllm_gptq_*/llama33-70b_vllm.json
2. Run Llama 4 Scout on vLLM (Llama 4 GGUF not supported in vLLM, need GPTQ):
   - Only GPTQ available: farshoreNext/Llama-4-Scout-17B-16E-Instruct-abliterated-v2-GPTQ (6 downloads, low trust)
   - May need to skip Llama 4 Scout vLLM or find a better GPTQ model
3. Download all results via SCP
4. Generate comparison report
5. DESTROY VM (./destroy.sh) to stop $10/hr billing
6. Commit results to git

HF_TOKEN is set at ~/.cache/huggingface/token on the VM.
SSH: ssh azureuser@20.112.232.231 (key generated in this container session)

CRITICAL V100 constraints learned:
- AWQ: NOT supported (compute capability 7.0, needs 7.5)
- GGUF in vLLM: Loads but OOM (dequantization overhead fills VRAM)
- GPTQ: WORKS with --enforce-eager --max-model-len 2048 --max-num-seqs 32
- FP16: OOM (70B = 140GB, only 64GB VRAM)
```

## Costs

This VM is expensive (~$10/hr). **Always destroy when not in use.**

Deploy only when needed, run your workload, then destroy.
