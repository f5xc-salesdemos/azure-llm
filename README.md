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

### vLLM Results (GPTQ 4-bit)

| Model | Engine | Result |
|---|---|---|
| Llama 3.3 70B (GPTQ 4-bit) | vLLM | **277.6 tok/s at c=32, 0 errors at all levels** |

### Head-to-Head: Ollama vs vLLM — Llama 3.3 70B (4x V100)

| Concurrency | Ollama (tok/s) | Ollama Errors | vLLM (tok/s) | vLLM Errors | vLLM Speedup |
|---|---|---|---|---|---|
| 1 | 2.6 | 0 | **24.4** | 0 | 9x |
| 2 | 0.6 | 4/6 | **32.5** | 0 | 54x |
| 4 | 0 | 12/12 | **56.6** | 0 | -- |
| 8 | 1.1 | 22/24 | **100.5** | 0 | 91x |
| 16 | 0.5 | 47/48 | **157.1** | 0 | 314x |
| 32 | 0.3 | 95/96 | **277.6** | 0 | 925x |

**Conclusion: vLLM is dramatically better for multi-user workloads.** Ollama collapses under concurrent load (95/96 errors at 32 users), while vLLM scales linearly with zero errors and 277 tok/s aggregate throughput.

### Phase 2: A100 80GB — Coding Model Comparison

| Model | c=1 tok/s | c=1 TTFT | c=32 tok/s | c=32 TTFT | Errors | VRAM |
|---|---|---|---|---|---|---|
| **Qwen3-Coder-30B (BF16)** | **352** | **20ms** | **1,924** | **80ms** | **0** | 74.5 GB |
| Qwen2.5-Coder-14B (BF16) | 139 | 42ms | 1,675 | 85ms | 0 | 73.5 GB |

**Winner: Qwen3-Coder-30B** — 2.5x faster at c=1, 15% faster at c=32, with a 20ms TTFT (vs 42ms).

### A100 vs V100 Cost-Performance

| Config | c=32 tok/s | Cost/hr | tok/s per dollar |
|---|---|---|---|
| **Qwen3-Coder-30B, 1x A100** | **1,924** | **$3.67** | **524** |
| Llama 3.3 70B GPTQ, 4x V100 | 278 | $10.00 | 28 |
| Llama 3.3 70B Ollama, 4x V100 | 0.3 | $10.00 | 0.03 |

**A100 is 19x more cost-effective than V100 for inference.**

### Handoff Prompt (copy this to continue)

```
I'm continuing the vLLM-based LLM inference platform project. Here's the exact state:

PHASE 1 COMPLETE — Ollama vs vLLM:
- vLLM wins: 277.6 tok/s at c=32 vs Ollama 0.3 tok/s (925x faster, 0 errors vs 99%)
- Results in benchmarks/results/run_20260405_062728/ (Ollama) and vllm_gptq_20260405_185242/ (vLLM)

PHASE 2 IN PROGRESS — Testing coding models for Claude Code replacement:
- VM MAY BE RUNNING at 40.67.170.234 (4x V100, centralus, ~$10/hr)
  First check: ssh azureuser@40.67.170.234 (if SSH key exists)
  If VM is gone, redeploy: fill subscription_id in terraform.tfvars, run ./deploy.sh
- Benchmarks were running: Qwen3-Coder-30B-A3B then Gemma 4 26B-A4B on vLLM
- Check results: ls /home/azureuser/benchmarks/results/run_*/
- HF token: (stored in secrets.auto.tfvars — never commit tokens to README)
- Claude Code installed at /usr/bin/claude on VM

CORRECT MODEL IDS (verified on HuggingFace):
- Qwen/Qwen3-Coder-30B-A3B-Instruct (MoE, 3.3B active — coding focused)
- google/gemma-4-26B-A4B-it (MoE, 4B active — latest Gemma 4)
- google/gemma-4-31B-it (31B dense — needs more VRAM)

A100 UPGRADE:
- Quota approved: 48 cores StandardNCADSA100v4 in southcentralus
- But ZERO physical capacity in any zone — all allocation failed
- Terraform ready: change vm_size to Standard_NC24ads_A100_v4, location to southcentralus
- A100 unlocks: AWQ, FlashAttention2, BFloat16, FP8 at $3.67/hr (vs $10/hr V100)

AGENTIC QUALITY BENCHMARKS (next step):
- tau-bench (sierra-research/tau2-bench) added to cloud-init for next deploy
- Use tau-bench to evaluate tool-calling quality, not just throughput
- SWE-bench for coding task evaluation
- Goal: find which model works best with Claude Code for interactive coding

CLAUDE CODE + vLLM CONFIG:
  export ANTHROPIC_BASE_URL=http://localhost:8000
  export ANTHROPIC_API_KEY=local-vllm
  export ANTHROPIC_AUTH_TOKEN=local-vllm
  export ANTHROPIC_DEFAULT_OPUS_MODEL=my-model
  vLLM must start with: --enable-auto-tool-choice --tool-call-parser hermes

V100 CONSTRAINTS:
- AWQ: NOT supported (cc 7.0, needs 7.5)
- GGUF in vLLM: OOM (dequantization fills VRAM)
- GPTQ: WORKS with --enforce-eager --max-model-len 2048 --max-num-seqs 32
- MoE models (Qwen3-Coder 3.3B active, Gemma4 4B active): should fit in FP16

IMPORTANT: DESTROY VM when done (./destroy.sh) — $10/hr billing
```

## TODO

- [x] ~~Check/collect Phase 2 benchmark results~~ — Qwen3-Coder-30B wins
- [x] ~~Upgrade to A100~~ — Central US zone 2, $3.67/hr
- [ ] **Test Qwen3-Coder-Next** (80B MoE, 3B active, 70.6% SWE-bench — #1 open-source)
- [ ] **Test Qwen3.5-122B-A10B** (122B MoE, 10B active, best tool-calling: 72.2 BFCL-V4)
- [ ] **Test gpt-oss-120b** (120B, matches o4-mini, designed for single 80GB GPU)
- [ ] **Run tau-bench** quality evaluation on top models
- [ ] **Run BFCL** (Berkeley Function Calling Leaderboard) for tool-calling quality
- [ ] **Claude Code interactive testing**: `start-claude-code` with local vLLM
- [ ] **Run SWE-bench Lite** on top model candidates

## Costs

| VM SKU | GPU | VRAM | Cost/hr |
|---|---|---|---|
| Standard_NC24s_v3 | 4x V100 | 64 GB | ~$10/hr |
| Standard_NC24ads_A100_v4 | 1x A100 | 80 GB | ~$3.67/hr |

**Always destroy when not in use.** Deploy, run workload, destroy.
