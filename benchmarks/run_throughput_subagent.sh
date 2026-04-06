#!/bin/bash
# ==============================================================================
# Throughput Benchmark for GitHub Operations Sub-Agent Candidates
#
# Measures TTFT, latency, tok/s at concurrency 1-32 for each candidate model.
# All models run TP=1 on a single A100 80GB.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="/opt/vllm-env/bin/python"
CONCURRENCY="1,2,4,8,16,32"
ITERATIONS=3
WARMUP=2
TIMEOUT=180
VLLM_STARTUP_TIMEOUT=900
GPU_FREE_TIMEOUT=120

RUN_ID="throughput_subagent_$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="${SCRIPT_DIR}/results/${RUN_ID}"
LOG_FILE="${RESULTS_DIR}/orchestrator.log"

# ==============================================================================
# Model matrix — same candidates as quality benchmark, skip StarCoder2 (no chat)
# ==============================================================================

declare -a MODEL_SLUGS=("qwen25-coder-7b" "phi4-mini" "deepseek-v2-lite" "qwen3-coder-30b-a3b")
declare -A HF_MODELS=(
    ["qwen25-coder-7b"]="Qwen/Qwen2.5-Coder-7B-Instruct"
    ["phi4-mini"]="microsoft/Phi-4-mini-instruct"
    ["deepseek-v2-lite"]="deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct"
    ["qwen3-coder-30b-a3b"]="Qwen/Qwen3-Coder-30B-A3B-Instruct"
)
declare -A SERVED_NAME=(
    ["qwen25-coder-7b"]="Qwen/Qwen2.5-Coder-7B-Instruct"
    ["phi4-mini"]="microsoft/Phi-4-mini-instruct"
    ["deepseek-v2-lite"]="deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct"
    ["qwen3-coder-30b-a3b"]="Qwen/Qwen3-Coder-30B-A3B-Instruct"
)
declare -A TOOL_PARSER=(
    ["qwen25-coder-7b"]="hermes"
    ["phi4-mini"]="hermes"
    ["deepseek-v2-lite"]="hermes"
    ["qwen3-coder-30b-a3b"]="qwen3_coder"
)
declare -A MAX_MODEL_LEN=(
    ["qwen25-coder-7b"]="32768"
    ["phi4-mini"]="16384"
    ["deepseek-v2-lite"]="32768"
    ["qwen3-coder-30b-a3b"]="32768"
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

stop_vllm() {
    log "Stopping vLLM..."
    if [[ -n "${VLLM_PID:-}" ]]; then
        kill "$VLLM_PID" 2>/dev/null || true
        wait "$VLLM_PID" 2>/dev/null || true
        unset VLLM_PID
    fi
    pkill -f "vllm.entrypoints" 2>/dev/null || true
    sleep 3
}

cleanup() {
    log "Cleaning up..."
    stop_vllm
}
trap cleanup EXIT

run_throughput_benchmark() {
    local model="$1"
    local slug="$2"
    local output_file="${RESULTS_DIR}/${slug}_throughput.json"

    log "Starting throughput benchmark: model=${model} concurrency=${CONCURRENCY}"

    if "${PYTHON}" "${SCRIPT_DIR}/benchmark_client.py" \
        --base-url "http://localhost:8000/v1" \
        --model "$model" \
        --engine "vllm" \
        --concurrency "$CONCURRENCY" \
        --prompts "${SCRIPT_DIR}/prompts.json" \
        --output "$output_file" \
        --warmup "$WARMUP" \
        --iterations "$ITERATIONS" \
        --timeout "$TIMEOUT" \
        2>&1 | tee -a "$LOG_FILE"; then
        log "Throughput benchmark complete: ${output_file}"
    else
        log "ERROR: Throughput benchmark failed for ${slug}"
    fi
}

# ==============================================================================
# Main
# ==============================================================================

mkdir -p "$RESULTS_DIR"
touch "$LOG_FILE"

# Stop any running vLLM (including Gemma 4 systemd service)
sudo systemctl stop vllm-gemma4 2>/dev/null || true
stop_vllm
wait_for_gpu_free "$GPU_FREE_TIMEOUT" || true

log "============================================================"
log "Throughput Benchmark — Sub-Agent Candidates"
log "Run ID: ${RUN_ID}"
log "Results: ${RESULTS_DIR}"
log "Models: ${MODEL_SLUGS[*]}"
log "Concurrency: ${CONCURRENCY}"
log "Iterations: ${ITERATIONS}"
log "============================================================"

# Capture system info
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
    tool_parser="${TOOL_PARSER[$slug]:-hermes}"
    max_len="${MAX_MODEL_LEN[$slug]:-8192}"

    log ""
    log "============================================================"
    log "MODEL: ${slug}"
    log "  HuggingFace: ${hf_model}"
    log "  Tool parser: ${tool_parser}"
    log "  Max context: ${max_len}"
    log "============================================================"

    stop_vllm
    wait_for_gpu_free "$GPU_FREE_TIMEOUT" || true

    log "Starting vLLM server: ${hf_model} (TP=1)..."
    nohup "${PYTHON}" -m vllm.entrypoints.openai.api_server \
        --model "$hf_model" \
        --tensor-parallel-size 1 \
        --gpu-memory-utilization 0.90 \
        --max-model-len "$max_len" \
        --enable-auto-tool-choice \
        --tool-call-parser "$tool_parser" \
        --host 0.0.0.0 \
        --port 8000 \
        > "${RESULTS_DIR}/${slug}_vllm_server.log" 2>&1 &
    VLLM_PID=$!
    log "vLLM server PID: ${VLLM_PID}"

    if wait_for_service "http://localhost:8000/health" "$VLLM_STARTUP_TIMEOUT"; then
        run_throughput_benchmark "$hf_model" "$slug"
    else
        log "ERROR: vLLM server did not start for ${slug}."
        log "Last 20 lines of vLLM log:"
        tail -20 "${RESULTS_DIR}/${slug}_vllm_server.log" 2>/dev/null | tee -a "$LOG_FILE" || true
    fi

    stop_vllm
done

# ==============================================================================
# Generate summary
# ==============================================================================

log ""
log "============================================================"
log "Generating comparison summary..."
log "============================================================"

SUMMARY_FILE="${RESULTS_DIR}/summary.txt"
{
    echo "============================================================"
    echo "THROUGHPUT BENCHMARK — SUB-AGENT CANDIDATES"
    echo "Run: ${RUN_ID}"
    echo "Date: $(date)"
    echo "VM: Standard_NC48ads_A100_v4 (2x A100 80GB)"
    echo "Mode: TP=1 (single GPU per model)"
    echo "============================================================"
    echo ""

    for f in "${RESULTS_DIR}"/*_throughput.txt; do
        [[ -f "$f" ]] || continue
        cat "$f"
        echo ""
    done

    echo "Full results in: ${RESULTS_DIR}/"
} > "$SUMMARY_FILE"

cat "$SUMMARY_FILE"

# Restart Gemma 4 production service
log "Restarting Gemma 4 production service..."
sudo systemctl start vllm-gemma4 2>/dev/null || true

log ""
log "All throughput benchmarks complete. Results in: ${RESULTS_DIR}/"
