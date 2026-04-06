#!/bin/bash
# ==============================================================================
# GPU LLM VM Setup Orchestrator
#
# Runs all modular setup scripts in order with timing and error handling.
# Each script is idempotent and can be run independently.
#
# Usage: bash /opt/setup/setup-all.sh [HF_TOKEN] [ADMIN_USERNAME]
# ==============================================================================
set -uo pipefail
exec > /var/log/gpu-setup.log 2>&1

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export HF_TOKEN="${1:-${HF_TOKEN:-}}"
export ADMIN_USERNAME="${2:-${ADMIN_USERNAME:-azureuser}}"
SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT_VERSION="2026-04-06-v5-full-devcontainer-parity"

echo "============================================================"
echo "GPU LLM VM Setup — $CLOUD_INIT_VERSION"
echo "Started: $(date)"
echo "Admin user: $ADMIN_USERNAME"
echo "Setup dir: $SETUP_DIR"
echo "============================================================"

run_section() {
    local script="$1"
    local name="$(basename "$script" .sh)"
    local start=$SECONDS

    echo ""
    echo "=== [$name] Starting: $(date) ==="
    if bash "$script"; then
        local elapsed=$((SECONDS - start))
        echo "=== [$name] Completed in ${elapsed}s ==="
    else
        local elapsed=$((SECONDS - start))
        echo "=== [$name] FAILED after ${elapsed}s (exit code: $?) ==="
        echo "WARNING: Continuing with next section..."
    fi
}

# Run all sections in order
for script in "$SETUP_DIR"/[0-9][0-9]-*.sh; do
    if [ -f "$script" ]; then
        run_section "$script"
    fi
done

echo ""
echo "============================================================"
echo "GPU LLM VM Setup Complete: $(date)"
echo "Cloud-init version: $CLOUD_INIT_VERSION"
echo "============================================================"
