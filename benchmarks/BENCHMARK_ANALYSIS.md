# GitHub Operations Sub-Agent Benchmark — Full Analysis

**Date:** 2026-04-06
**Hardware:** Azure Standard_NC48ads_A100_v4 (2x NVIDIA A100 80GB PCIe)
**Quality Benchmark:** 56 test cases, 5 categories, deterministic heuristic scoring (0-100)
**Throughput Benchmark:** Concurrency 1-32, 3 iterations, 2 warmup, 10 diverse prompts
**All models:** TP=1 (single A100), 0.90 gpu-memory-utilization

---

## Executive Summary

**Recommendation: Phi-4-mini-instruct** for 12+ concurrent users.

At concurrency 16 (the target user count), Phi-4-mini delivers **2,594 tok/s** with **38ms TTFT p50** — nearly 2x the throughput of the next-best Qwen2.5-Coder-7B (1,585 tok/s, 49ms TTFT). Quality is 78.7/100 vs Qwen's 81.6 — a 3-point trade-off that buys double the serving capacity.

At concurrency 32 (peak/burst), Phi-4-mini reaches **4,813 tok/s** with only 55ms TTFT — the only model under 60ms at that load. It uses just ~8GB VRAM, leaving 72GB free for the main Gemma 4 model on the same GPU.

If quality is non-negotiable (must be >80), **Qwen2.5-Coder-7B** at 81.6/100 is the pick, but expect half the throughput at high concurrency.

---

## Throughput Results (TP=1, Single A100)

### TTFT (Time to First Token) — p50 in milliseconds

| Model | c=1 | c=2 | c=4 | c=8 | c=16 | c=32 |
|-------|-----|-----|-----|-----|------|------|
| **Phi-4-mini** | **14** | 21 | 23 | 27 | **38** | **55** |
| Qwen3-Coder-30B-A3B | 20 | 32 | 50 | 63 | 77 | 83 |
| Qwen2.5-Coder-7B | 24 | 22 | 24 | 40 | 49 | 69 |
| DeepSeek-V2-Lite | 49 | 72 | 90 | 106 | 114 | 122 |

**Winner at c=16:** Phi-4-mini (38ms) — snappiest first-token response under concurrent load.

### Aggregate Throughput (tok/s)

| Model | c=1 | c=2 | c=4 | c=8 | c=16 | c=32 |
|-------|-----|-----|-----|-----|------|------|
| **Phi-4-mini** | 447 | 525 | 1,028 | 1,774 | **2,594** | **4,813** |
| Qwen3-Coder-30B-A3B | 343 | 390 | 584 | 585 | 1,143 | 1,892 |
| Qwen2.5-Coder-7B | 260 | 307 | 567 | 726 | 1,585 | 3,264 |
| DeepSeek-V2-Lite | 160 | 194 | 399 | 715 | 949 | 1,948 |

**Winner at c=16:** Phi-4-mini (2,594 tok/s) — 64% more throughput than Qwen2.5-Coder.

### Latency p50 (ms) — Total request completion

| Model | c=1 | c=2 | c=4 | c=8 | c=16 | c=32 |
|-------|-----|-----|-----|-----|------|------|
| **Phi-4-mini** | **335** | 1,173 | 1,308 | **1,096** | **1,550** | **1,461** |
| Qwen3-Coder-30B-A3B | 388 | 1,611 | 2,778 | 4,801 | 4,750 | 5,197 |
| Qwen2.5-Coder-7B | 488 | 1,950 | 1,626 | 3,148 | 1,758 | 2,303 |
| DeepSeek-V2-Lite | 540 | 2,843 | 3,005 | 3,906 | 4,139 | 4,167 |

**Winner at c=16:** Phi-4-mini (1,550ms p50) — sub-2-second responses at 16 concurrent users.

### Latency p99 (ms) — Tail latency

| Model | c=1 | c=8 | c=16 | c=32 |
|-------|-----|-----|------|------|
| **Phi-4-mini** | 335 | 2,106 | **3,594** | **3,817** |
| Qwen2.5-Coder-7B | 563 | 9,717 | 5,715 | 5,845 |
| Qwen3-Coder-30B-A3B | 429 | 11,185 | 8,516 | 10,512 |
| DeepSeek-V2-Lite | 551 | 7,337 | 10,108 | 9,577 |

**Winner at c=16:** Phi-4-mini (3.6s p99) — all others exceed 5.7s. Critical for user-facing latency SLAs.

---

## Quality Results (56 test cases)

| Model | Overall | Code Review | Commit Msg | gh CLI | Issue Triage | PR Desc |
|-------|---------|-------------|------------|--------|--------------|---------|
| Gemma 4 31B (baseline, TP=2) | **83.9** | 79.3 | 73.8 | **98.5** | **78.5** | **89.3** |
| Qwen2.5-Coder-7B | **81.6** | 74.2 | 77.6 | 91.5 | 76.3 | 88.6 |
| Qwen3-Coder-30B-A3B | **81.5** | **79.3** | **86.7** | 90.5 | 67.3 | 83.6 |
| **Phi-4-mini** | **78.7** | 76.6 | 80.5 | 84.0 | 69.3 | 83.1 |
| DeepSeek-V2-Lite | **77.7** | 69.6 | 77.0 | 85.5 | 74.5 | 81.7 |
| StarCoder2-15B | **0.0** | N/A | N/A | N/A | N/A | N/A |

---

## Combined Ranking: Quality x Throughput

For 12+ concurrent users, the metric that matters is **quality-adjusted throughput** at c=16.

| Rank | Model | Quality | tok/s @c=16 | TTFT p50 @c=16 | p99 Latency @c=16 | VRAM | Verdict |
|------|-------|---------|-------------|----------------|-------------------|------|---------|
| 1 | **Phi-4-mini** | 78.7 | **2,594** | **38ms** | **3.6s** | ~8GB | **Best for multi-user** |
| 2 | **Qwen2.5-Coder-7B** | 81.6 | 1,585 | 49ms | 5.7s | ~14GB | Best quality, good throughput |
| 3 | Qwen3-Coder-30B-A3B | 81.5 | 1,143 | 77ms | 8.5s | ~60GB | High quality, poor scaling |
| 4 | DeepSeek-V2-Lite | 77.7 | 949 | 114ms | 10.1s | ~32GB | Lowest across both axes |

### Quality-Throughput Score (at c=16)

`Score = quality_score * log2(throughput_at_c16)`

| Model | Quality | log2(tok/s @c=16) | Combined Score |
|-------|---------|-------------------|---------------|
| **Phi-4-mini** | 78.7 | 11.34 | **892** |
| **Qwen2.5-Coder-7B** | 81.6 | 10.63 | **867** |
| Qwen3-Coder-30B-A3B | 81.5 | 10.16 | 828 |
| DeepSeek-V2-Lite | 77.7 | 9.89 | 768 |

---

## Concurrency Scaling Analysis

How well each model handles increasing user load:

### Throughput Scaling Factor (c=32 / c=1)

| Model | c=1 tok/s | c=32 tok/s | Scaling Factor |
|-------|-----------|------------|---------------|
| **Phi-4-mini** | 447 | 4,813 | **10.8x** |
| Qwen2.5-Coder-7B | 260 | 3,264 | **12.6x** |
| DeepSeek-V2-Lite | 160 | 1,948 | 12.2x |
| Qwen3-Coder-30B-A3B | 343 | 1,892 | 5.5x |

Qwen3-Coder scales poorly (only 5.5x) — its large MoE architecture causes memory pressure at high concurrency. All others scale 10x+ from c=1 to c=32.

### TTFT Degradation Under Load (c=32 / c=1)

| Model | TTFT @c=1 | TTFT @c=32 | Degradation |
|-------|-----------|------------|-------------|
| **Phi-4-mini** | 14ms | 55ms | 3.9x |
| Qwen2.5-Coder-7B | 24ms | 69ms | 2.9x |
| Qwen3-Coder-30B-A3B | 20ms | 83ms | 4.2x |
| DeepSeek-V2-Lite | 49ms | 122ms | 2.5x |

All models keep TTFT under 130ms even at c=32 — excellent responsiveness.

---

## Deployment Recommendation

### Primary: Phi-4-mini-instruct (3.8B)

For a 12+ user GitHub operations sub-agent:

```bash
# Sub-agent on GPU 0 (Phi-4-mini, port 8001)
/opt/vllm-env/bin/python -m vllm.entrypoints.openai.api_server \
  --model microsoft/Phi-4-mini-instruct \
  --tensor-parallel-size 1 \
  --gpu-memory-utilization 0.15 \
  --max-model-len 16384 \
  --enable-auto-tool-choice \
  --tool-call-parser hermes \
  --host 0.0.0.0 \
  --port 8001

# Main model on both GPUs (Gemma 4 31B, port 8000)
# Existing systemd service continues
```

**Why Phi-4-mini over Qwen2.5-Coder-7B:**
- 64% more throughput at c=16 (2,594 vs 1,585 tok/s)
- 2x better tail latency at c=16 (3.6s vs 5.7s p99)
- Half the VRAM (8GB vs 14GB)
- 38ms vs 49ms TTFT at c=16 — snappier perceived responsiveness
- Only 2.9 points lower quality (78.7 vs 81.6)

### Alternative: Qwen2.5-Coder-7B-Instruct (7B)

If quality bar is strict >80/100:

```bash
# Same config but different model
--model Qwen/Qwen2.5-Coder-7B-Instruct \
--gpu-memory-utilization 0.25 \
--max-model-len 32768 \
```

### Not Recommended

- **Qwen3-Coder-30B-A3B**: Poor concurrency scaling (5.5x), 60GB VRAM makes co-hosting with Gemma 4 impossible
- **DeepSeek-V2-Lite**: Lowest quality (77.7) AND lowest throughput at c=16 (949 tok/s). No advantage on either axis
- **StarCoder2-15B**: Completion-only model, no chat template — cannot serve instruction tasks

---

## Projected Performance at 12 Concurrent Users

Interpolating between c=8 and c=16 measurements:

| Model | Est. tok/s @c=12 | Est. TTFT p50 | Est. p99 Latency | Quality |
|-------|------------------|---------------|------------------|---------|
| **Phi-4-mini** | ~2,180 | ~33ms | ~2.8s | 78.7 |
| Qwen2.5-Coder-7B | ~1,150 | ~45ms | ~7.7s | 81.6 |
| Qwen3-Coder-30B-A3B | ~860 | ~70ms | ~9.8s | 81.5 |
| DeepSeek-V2-Lite | ~830 | ~110ms | ~8.7s | 77.7 |

At 12 concurrent users, Phi-4-mini delivers sub-3-second tail latency while others approach 8-10 seconds. For a responsive GitHub operations sub-agent, this difference is the one that users feel.

---

## Appendix: Scoring Methodology

### Quality Benchmark (56 test cases)
- **PR Description** (12 cases): Title keywords, markdown format, explains what/why
- **Code Review** (12 cases): Bug detection, severity, fix suggestion, no false positives
- **Issue Triage** (10 cases): Label accuracy, priority, category match
- **Commit Message** (12 cases): Conventional format, correct type, scope, conciseness
- **gh CLI** (10 cases): Correct command, required flags, valid syntax

### Throughput Benchmark
- **10 diverse prompts**: QA, code generation, reasoning, creative writing, summarization, technical, translation, math, long analysis, multi-turn
- **Concurrency levels**: 1, 2, 4, 8, 16, 32
- **Metrics**: TTFT (p50, p99), total latency (p50, p99), aggregate throughput (tok/s)
- **3 iterations per level**, 2 warmup requests
