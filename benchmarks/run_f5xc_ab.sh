#!/usr/bin/env bash
# A/B benchmark: Devstral-Small-2-24B vs Gemma-4-31B on F5 XC API tasks
# Deploys and runs benchmark_f5xc_ab.py on the workstation VM.
#
# Usage:
#   export F5XC_API_URL=https://...
#   export F5XC_API_TOKEN=...
#   bash run_f5xc_ab.sh [iterations]

set -euo pipefail

WORKSTATION="azureuser@135.233.100.110"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ITERATIONS="${1:-5}"
RUN_ID="f5xc_ab_$(date +%Y%m%d_%H%M%S)"
REMOTE_DIR="/tmp/benchmark_f5xc_ab"

# Verify env vars
for var in F5XC_API_URL F5XC_API_TOKEN; do
    val=$(printenv "$var" 2>/dev/null || true)
    if [ -z "$val" ]; then
        echo "ERROR: $var is not set" >&2
        exit 1
    fi
done

echo "=== F5 XC A/B Benchmark ==="
echo "  Iterations: $ITERATIONS"
echo "  Run ID:     $RUN_ID"
echo ""

# Check endpoints
echo "--- Checking vLLM endpoints ---"
ssh -o StrictHostKeyChecking=no "$WORKSTATION" bash -c "'
    echo -n \"  Gemma    (10.0.0.10:8000): \"; curl -sf http://10.0.0.10:8000/health && echo UP || echo DOWN
    echo -n \"  Devstral (10.0.0.11:8002): \"; curl -sf http://10.0.0.11:8002/health && echo UP || echo DOWN
'"

# Deploy
echo ""
echo "--- Deploying benchmark script ---"
ssh -o StrictHostKeyChecking=no "$WORKSTATION" "mkdir -p $REMOTE_DIR"
scp -o StrictHostKeyChecking=no \
    "$SCRIPT_DIR/benchmark_f5xc_ab.py" \
    "$WORKSTATION:$REMOTE_DIR/"

# Run
echo ""
echo "--- Running benchmark ---"
ssh -o StrictHostKeyChecking=no "$WORKSTATION" bash -c "'
    export F5XC_API_URL=\"$F5XC_API_URL\"
    export F5XC_API_TOKEN=\"$F5XC_API_TOKEN\"
    cd $REMOTE_DIR
    python3 benchmark_f5xc_ab.py \
        --iterations $ITERATIONS \
        --warmup 1 \
        --timeout 120 \
        --output $REMOTE_DIR/results/$RUN_ID/
'"

# Retrieve results
echo ""
echo "--- Retrieving results ---"
mkdir -p "$SCRIPT_DIR/results/$RUN_ID"
scp -o StrictHostKeyChecking=no -r \
    "$WORKSTATION:$REMOTE_DIR/results/$RUN_ID/" \
    "$SCRIPT_DIR/results/$RUN_ID/"

echo ""
echo "Results saved to: $SCRIPT_DIR/results/$RUN_ID/"
