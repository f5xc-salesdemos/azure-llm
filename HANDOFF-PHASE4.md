# Phase 4: GitHub Operations LLM Benchmark

## Handoff — paste this into a fresh Claude Code session

```
I'm starting Phase 4 of the azure-llm project: benchmarking small efficient LLMs
specifically for GitHub operations (PR management, code review, issue triage,
commit analysis) running on vLLM with OpenCode as the agent framework.

## Project Repository
- Repo: f5xc-salesdemos/azure-llm (GitHub)
- Working dir: /workspace/azure-llm

## Infrastructure (already built and working)
- Azure VM: Standard_NC48ads_A100_v4 (2x A100 80GB, 160GB VRAM total)
- Region: centralus, zone 2
- OS: Ubuntu 24.04 LTS
- GPU: 2x NVIDIA A100 80GB PCIe (cc 8.0)
- vLLM nightly 0.19.1rc1 + transformers 5.5.0 installed
- Claude Code CLI installed and pre-configured
- Terraform fully parameterized (secrets.auto.tfvars for subscription_id + hf_token)
- Modular setup scripts in setup/ directory (16 scripts, tested incrementally)
- Cost: ~$7.34/hr for 2x A100

## Deployment
- Fill secrets.auto.tfvars: subscription_id + hf_token
- terraform init && terraform plan -out=tfplan && terraform apply tfplan
- Cloud-init auto-installs everything (~15-20 min)
- VM auto-starts vLLM via systemd service after reboot

## Key Files
- terraform.tfvars — VM config (model_id, served_model_name, tool_call_parser, etc.)
- secrets.auto.tfvars — subscription_id + hf_token (gitignored)
- cloud-init.yaml — templatefile with ${variable} injection
- setup/ — 16 modular setup scripts
- benchmarks/benchmark_client.py — async throughput benchmark (TTFT, latency, tok/s)
- benchmarks/run_orchestrator.sh — sequential model comparison runner

## What Was Already Benchmarked (throughput only, not quality)
Previous phases tested throughput at concurrency 1-32:
- Qwen3-Coder-30B (1x A100 BF16): 1,924 tok/s at c=32 — fastest overall
- Gemma 4 31B (2x A100 BF16 128K): 1,348 tok/s at c=32 — best multimodal
- Llama 4 Scout INT4 (2x A100 128K): 735 tok/s at c=32
- Qwen2.5-Coder-14B (1x A100 BF16): 1,675 tok/s at c=32

## Phase 4 Goal
Find the most efficient small LLM (7B-15B range) for a dedicated GitHub operations
sub-agent. This agent handles: PR creation/review, issue management, commit analysis,
branch operations, code review — NOT general coding. It runs alongside the main
model (Gemma 4) as a specialized sub-agent via OpenCode.

## Models to Benchmark
Candidate models (all fit easily on a single A100 or even share with main model):

1. Qwen2.5-Coder-7B-Instruct — 88.4% HumanEval, strong tool calling
2. DeepSeek-Coder-V2-Lite-Instruct — 16B MoE, good at completion
3. StarCoder2-15B — 15B, large context, code-focused
4. Qwen3-Coder-30B-A3B-Instruct — 3B active MoE, proven in our tests
5. Research and add any other competitors found online

## What Needs to Be Done

### 1. Install OpenCode on the VM
- npm install -g opencode (or from GitHub)
- Configure opencode.json to point at local vLLM
- Set up a custom "github-ops" agent profile

### 2. Create GitHub Operations Benchmark
- NOT throughput testing (we already have benchmark_client.py for that)
- Quality/accuracy testing for:
  - PR description generation from diffs
  - Code review comments (find bugs, suggest fixes)
  - Issue triage (categorize, assign labels)
  - Commit message generation
  - Branch naming conventions
  - gh CLI command generation
- Use real GitHub repos as test data

### 3. Run Models Sequentially
- Start vLLM with model A → run github-ops benchmark → stop
- Start vLLM with model B → run github-ops benchmark → stop
- Compare quality scores, not just speed

### 4. Configure OpenCode Sub-Agent
- Create opencode.json with github-ops agent pointing at vLLM
- The sub-agent should be callable from Claude Code or standalone
- Test with real GitHub operations on this repo

## Key Learnings from Previous Phases (save you time)
- A100 doesn't support FP8 KV cache (H100 only) — use BF16
- AWQ quantization works on A100 (cc 8.0+), NOT on V100 (cc 7.0)
- vLLM nightly needed for Gemma 4 (transformers 5.5.0)
- MoE models load ALL weights, not just active params (109B Scout = 218GB BF16)
- cloud-init packages: section races with runcmd — all apt in setup script, not cloud-init
- Terraform templatefile: escape bash ${} as $${}, only ${var} for Terraform vars
- Ubuntu 24.04: cuda-toolkit-12-8 (not 12-4), neovim via apt (not AppImage)
- Rust: install to /usr/local/rustup + /usr/local/cargo (not /root/.cargo)
- --limit-mm-per-prompt needs JSON: '{"image": 4}' not image=4
- ANTHROPIC_API_KEY only (not both API_KEY + AUTH_TOKEN — causes conflict)
- Settings at /etc/skel/.claude/ for all users, /etc/claude-code/CLAUDE.md system-wide
```
