#!/bin/bash
# ==============================================================================
# Benchmark Orchestrator: Ollama vs vLLM
#
# Sequences the full benchmark matrix:
#   2 models (Llama 3.3 70B, Llama 4 Scout) x 2 engines (Ollama, vLLM)
#
# Each engine is started, benchmarked, and stopped before the next to avoid
# GPU memory conflicts. GPU memory is verified free between runs.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="/opt/vllm-env/bin/python"
CONCURRENCY="1,2,4,8,16,32"
ITERATIONS=3
WARMUP=2
TIMEOUT=180
VLLM_STARTUP_TIMEOUT=900
OLLAMA_PULL_TIMEOUT=1800
GPU_FREE_TIMEOUT=120

# Timestamp for this run
RUN_ID="run_$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="${SCRIPT_DIR}/results/${RUN_ID}"
LOG_FILE="${RESULTS_DIR}/orchestrator.log"

# Model definitions: slug, hf_model_id
# Coding models for Claude Code replacement
# Coding models for Claude Code replacement
# V100 4x16GB (cc 7.0): GPTQ, --enforce-eager, TP=4
# A100 (cc 8.0): can remove --enforce-eager, use AWQ, single GPU
# A100 80GB: MoE models need FP8/AWQ to fit (ALL weights loaded, not just active)
# 80B MoE BF16 = ~160GB (OOM), FP8 = ~80GB (tight), AWQ = ~40GB (comfortable)
# Phase 3: Best models for agentic coding + tool calling + thinking on A100 80GB
# Phase 3 final: best agentic coding models for A100 80GB
# Models ordered by expected quality (SWE-bench / BFCL scores)
declare -a MODEL_SLUGS=("qwen3-coder-next-fp8" "gemma4-31b" "glm47-flash" "llama4-scout")
declare -A HF_MODELS=(
    ["qwen3-coder-next-fp8"]="Qwen/Qwen3-Coder-Next-FP8"
    ["gemma4-31b"]="google/gemma-4-31B-it"
    ["glm47-flash"]="zai-org/GLM-4.7-Flash"
    ["llama4-scout"]="meta-llama/Llama-4-Scout-17B-16E-Instruct"
)
declare -A VLLM_EXTRA=(
    ["qwen3-coder-next-fp8"]="--trust-remote-code --tool-call-parser qwen3_coder"
    ["gemma4-31b"]=""
    ["glm47-flash"]="--reasoning-parser glm45"
    ["llama4-scout"]=""
)
declare -A TOOL_PARSER=(
    ["qwen3-coder-next-fp8"]="qwen3_coder"
    ["gemma4-31b"]="gemma4"
    ["glm47-flash"]="glm47"
    ["llama4-scout"]="llama4_pythonic"
)
# Per-model max context (based on A100 80GB VRAM budget after weights)
# FP8 models have smaller weights = more room for KV cache = longer context
declare -A MAX_MODEL_LEN=(
    ["qwen3-coder-next-fp8"]="32768"
    ["gemma4-31b"]="8192"
    ["glm47-flash"]="8192"
    ["llama4-scout"]="32768"
)

# ==============================================================================
# Helper functions
# ==============================================================================

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

wait_for_service() {
    local url="$1"
    local timeout_secs="$2"
    local start_time=$SECONDS

    log "Waiting for service at ${url} (timeout: ${timeout_secs}s)..."
    while true; do
        if curl -sf "$url" > /dev/null 2>&1; then
            log "Service is ready at ${url}"
            return 0
        fi
        if (( SECONDS - start_time >= timeout_secs )); then
            log "ERROR: Service at ${url} did not become ready in ${timeout_secs}s"
            return 1
        fi
        sleep 5
    done
}

wait_for_gpu_free() {
    local timeout_secs="$1"
    local start_time=$SECONDS

    log "Waiting for GPU memory to be released (timeout: ${timeout_secs}s)..."
    while true; do
        local max_used
        max_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits \
                   | sort -n | tail -1)
        if (( max_used < 500 )); then
            log "GPU memory is free (max used: ${max_used} MiB)"
            return 0
        fi
        if (( SECONDS - start_time >= timeout_secs )); then
            log "WARNING: GPU memory not fully released after ${timeout_secs}s (max used: ${max_used} MiB)"
            return 1
        fi
        sleep 5
    done
}

stop_ollama() {
    log "Stopping Ollama..."
    sudo systemctl stop ollama 2>/dev/null || true
    # Kill any leftover ollama processes
    pkill -f "ollama" 2>/dev/null || true
    sleep 3
}

stop_vllm() {
    log "Stopping vLLM..."
    if [[ -n "${VLLM_PID:-}" ]]; then
        kill "$VLLM_PID" 2>/dev/null || true
        wait "$VLLM_PID" 2>/dev/null || true
        unset VLLM_PID
    fi
    # Kill any leftover vllm processes
    pkill -f "vllm.entrypoints" 2>/dev/null || true
    sleep 3
}

cleanup() {
    log "Cleaning up..."
    stop_ollama
    stop_vllm
}
trap cleanup EXIT

run_benchmark() {
    local engine="$1"
    local model="$2"
    local base_url="$3"
    local slug="$4"
    local output_file="${RESULTS_DIR}/${slug}_${engine}.json"

    log "Starting benchmark: engine=${engine} model=${model} concurrency=${CONCURRENCY}"

    if "${PYTHON}" "${SCRIPT_DIR}/benchmark_client.py" \
        --base-url "$base_url" \
        --model "$model" \
        --engine "$engine" \
        --concurrency "$CONCURRENCY" \
        --prompts "${SCRIPT_DIR}/prompts.json" \
        --output "$output_file" \
        --warmup "$WARMUP" \
        --iterations "$ITERATIONS" \
        --timeout "$TIMEOUT" \
        2>&1 | tee -a "$LOG_FILE"; then
        log "Benchmark complete: ${output_file}"
    else
        log "ERROR: Benchmark failed for ${engine}/${slug}"
    fi
}

# ==============================================================================
# Main
# ==============================================================================

mkdir -p "$RESULTS_DIR"
touch "$LOG_FILE"

log "============================================================"
log "Benchmark Orchestrator Starting"
log "Run ID: ${RUN_ID}"
log "Results: ${RESULTS_DIR}"
log "Models: ${MODEL_SLUGS[*]}"
log "Concurrency: ${CONCURRENCY}"
log "Iterations: ${ITERATIONS}"
log "============================================================"

# Install Python dependencies
log "Installing Python dependencies..."
"${PYTHON}" -m pip install -q -r "${SCRIPT_DIR}/requirements.txt" 2>&1 | tee -a "$LOG_FILE"

# Capture system info
log "Capturing system information..."
{
    echo "=== GPU Info ==="
    nvidia-smi
    echo ""
    echo "=== VM Info ==="
    uname -a
    echo "CPU cores: $(nproc)"
    echo "RAM: $(free -h | grep Mem | awk '{print $2}')"
} > "${RESULTS_DIR}/system_info.txt" 2>&1

# ==============================================================================
# Run benchmark matrix
# ==============================================================================

for slug in "${MODEL_SLUGS[@]}"; do
    hf_model="${HF_MODELS[$slug]}"
    extra="${VLLM_EXTRA[$slug]:-}"
    tool_parser="${TOOL_PARSER[$slug]:-hermes}"
    max_len="${MAX_MODEL_LEN[$slug]:-8192}"

    log ""
    log "============================================================"
    log "MODEL: ${slug}"
    log "  HuggingFace: ${hf_model}"
    log "  Tool parser: ${tool_parser}"
    log "  Max context: ${max_len}"
    log "  Extra args: ${extra:-none}"
    log "============================================================"

    stop_vllm

    log "Starting vLLM server: ${hf_model}..."
    nohup "${PYTHON}" -m vllm.entrypoints.openai.api_server \
        --model "$hf_model" \
        --gpu-memory-utilization 0.90 \
        --max-model-len "$max_len" \
        --enable-auto-tool-choice \
        --tool-call-parser "$tool_parser" \
        --host 0.0.0.0 \
        --port 8000 \
        ${extra} \
        > "${RESULTS_DIR}/${slug}_vllm_server.log" 2>&1 &
    VLLM_PID=$!
    log "vLLM server PID: ${VLLM_PID}"

    if wait_for_service "http://localhost:8000/health" "$VLLM_STARTUP_TIMEOUT"; then
        run_benchmark "vllm" "$hf_model" "http://localhost:8000/v1" "$slug"
    else
        log "ERROR: vLLM server did not start for ${slug}."
        log "Last 20 lines of vLLM log:"
        tail -20 "${RESULTS_DIR}/${slug}_vllm_server.log" 2>/dev/null | tee -a "$LOG_FILE" || true
    fi

    stop_vllm
    wait_for_gpu_free "$GPU_FREE_TIMEOUT" || true
done

# ==============================================================================
# Generate comparison summary
# ==============================================================================

log ""
log "============================================================"
log "Generating comparison summary..."
log "============================================================"

SUMMARY_FILE="${RESULTS_DIR}/summary.txt"
{
    echo "============================================================"
    echo "BENCHMARK COMPARISON SUMMARY"
    echo "Run: ${RUN_ID}"
    echo "Date: $(date)"
    echo "VM: Standard_NC24s_v3 (4x V100, 24 vCPUs, 448 GB RAM)"
    echo "============================================================"
    echo ""

    for f in "${RESULTS_DIR}"/*.json; do
        [[ -f "$f" ]] || continue
        # Print the corresponding .txt table if it exists
        txt_file="${f%.json}.txt"
        if [[ -f "$txt_file" ]]; then
            cat "$txt_file"
            echo ""
        fi
    done

    echo ""
    echo "Full results in: ${RESULTS_DIR}/"
    echo "System info: ${RESULTS_DIR}/system_info.txt"
} > "$SUMMARY_FILE"

cat "$SUMMARY_FILE"

log ""
log "All benchmarks complete. Results in: ${RESULTS_DIR}/"
log "Summary: ${SUMMARY_FILE}"
