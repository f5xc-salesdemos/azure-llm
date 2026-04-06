#!/bin/bash
# ==============================================================================
# GitHub Operations Quality Benchmark Orchestrator
#
# Sequences the quality benchmark across candidate models:
#   - Starts vLLM with each model (TP=1, single A100)
#   - Runs github_ops_benchmark.py for quality scoring
#   - Stops vLLM, waits for GPU, moves to next model
#   - Generates comparison report at the end
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="/opt/vllm-env/bin/python"
TIMEOUT=180
VLLM_STARTUP_TIMEOUT=900
GPU_FREE_TIMEOUT=120
CONCURRENCY=4

# Timestamp for this run
RUN_ID="github_ops_$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="${SCRIPT_DIR}/results/${RUN_ID}"
LOG_FILE="${RESULTS_DIR}/orchestrator.log"

# ==============================================================================
# Model matrix — small efficient models for GitHub operations
# All fit on a single A100 80GB (TP=1)
# ==============================================================================

declare -a MODEL_SLUGS=("qwen25-coder-7b" "deepseek-v2-lite" "starcoder2-15b" "qwen3-coder-30b-a3b" "phi4-mini")
declare -A HF_MODELS=(
    ["qwen25-coder-7b"]="Qwen/Qwen2.5-Coder-7B-Instruct"
    ["deepseek-v2-lite"]="deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct"
    ["starcoder2-15b"]="bigcode/starcoder2-15b"
    ["qwen3-coder-30b-a3b"]="Qwen/Qwen3-Coder-30B-A3B-Instruct"
    ["phi4-mini"]="microsoft/Phi-4-mini-instruct"
)
declare -A TOOL_PARSER=(
    ["qwen25-coder-7b"]="hermes"
    ["deepseek-v2-lite"]="hermes"
    ["starcoder2-15b"]="hermes"
    ["qwen3-coder-30b-a3b"]="qwen3_coder"
    ["phi4-mini"]="hermes"
)
# Conservative context limits — quality benchmark doesn't need large context
declare -A MAX_MODEL_LEN=(
    ["qwen25-coder-7b"]="32768"
    ["deepseek-v2-lite"]="32768"
    ["starcoder2-15b"]="16384"
    ["qwen3-coder-30b-a3b"]="32768"
    ["phi4-mini"]="16384"
)
# Extra vLLM args per model
declare -A VLLM_EXTRA=(
    ["qwen25-coder-7b"]=""
    ["deepseek-v2-lite"]=""
    ["starcoder2-15b"]=""
    ["qwen3-coder-30b-a3b"]=""
    ["phi4-mini"]=""
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

run_quality_benchmark() {
    local model="$1"
    local slug="$2"
    local output_file="${RESULTS_DIR}/github_ops_${slug}.json"

    log "Starting quality benchmark: model=${model} slug=${slug}"

    if "${PYTHON}" "${SCRIPT_DIR}/github_ops_benchmark.py" \
        --base-url "http://localhost:8000/v1" \
        --model "$model" \
        --testdata-dir "${SCRIPT_DIR}/github_ops_testdata" \
        --output "$output_file" \
        --timeout "$TIMEOUT" \
        --concurrency "$CONCURRENCY" \
        2>&1 | tee -a "$LOG_FILE"; then
        log "Quality benchmark complete: ${output_file}"
    else
        log "ERROR: Quality benchmark failed for ${slug}"
    fi
}

# ==============================================================================
# Main
# ==============================================================================

mkdir -p "$RESULTS_DIR"
touch "$LOG_FILE"

log "============================================================"
log "GitHub Operations Quality Benchmark Orchestrator"
log "Run ID: ${RUN_ID}"
log "Results: ${RESULTS_DIR}"
log "Models: ${MODEL_SLUGS[*]}"
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
        ${extra} \
        > "${RESULTS_DIR}/${slug}_vllm_server.log" 2>&1 &
    VLLM_PID=$!
    log "vLLM server PID: ${VLLM_PID}"

    if wait_for_service "http://localhost:8000/health" "$VLLM_STARTUP_TIMEOUT"; then
        run_quality_benchmark "$hf_model" "$slug"
    else
        log "ERROR: vLLM server did not start for ${slug}."
        log "Last 20 lines of vLLM log:"
        tail -20 "${RESULTS_DIR}/${slug}_vllm_server.log" 2>/dev/null | tee -a "$LOG_FILE" || true
    fi

    stop_vllm
    wait_for_gpu_free "$GPU_FREE_TIMEOUT" || true
done

# ==============================================================================
# Generate comparison report
# ==============================================================================

log ""
log "============================================================"
log "Generating comparison report..."
log "============================================================"

if "${PYTHON}" "${SCRIPT_DIR}/compare_github_ops.py" \
    --results-dir "$RESULTS_DIR" \
    2>&1 | tee -a "$LOG_FILE"; then
    log "Comparison report generated: ${RESULTS_DIR}/comparison.md"
else
    log "WARNING: Comparison report generation failed"
fi

log ""
log "All benchmarks complete. Results in: ${RESULTS_DIR}/"
