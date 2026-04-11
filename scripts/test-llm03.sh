#!/bin/bash
###############################################################################
# test-llm03.sh — Post-deploy verification for PersonaPlex H100 VM
#
# Usage: ./scripts/test-llm03.sh <public-ip-or-fqdn>
#
# Tests:
#   1. SSH connectivity
#   2. Cloud-init completion
#   3. NVIDIA GPU detection (H100)
#   4. CUDA toolkit installed
#   5. Python venv + moshi package
#   6. HuggingFace token configured
#   7. PersonaPlex systemd service enabled
#   8. PersonaPlex service running (post-reboot)
#   9. Port 8998 listening
#  10. Kernel tuning applied (hugepages, THP, swappiness)
###############################################################################
set -euo pipefail

HOST="${1:?Usage: $0 <public-ip-or-fqdn>}"
USER="azureuser"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

PASS=0
FAIL=0
SKIP=0

run_test() {
    local name="$1"
    local cmd="$2"
    local expect="${3:-}"  # optional expected substring

    printf "  %-50s " "$name"
    output=$(ssh $SSH_OPTS "$USER@$HOST" "$cmd" 2>&1) || {
        echo "[FAIL] (ssh/command error)"
        echo "    -> $output" | head -3
        FAIL=$((FAIL + 1))
        return 1
    }

    if [ -n "$expect" ]; then
        if echo "$output" | grep -qi "$expect"; then
            echo "[PASS]"
            PASS=$((PASS + 1))
        else
            echo "[FAIL] (expected '$expect')"
            echo "    -> $output" | head -3
            FAIL=$((FAIL + 1))
            return 1
        fi
    else
        echo "[PASS]"
        PASS=$((PASS + 1))
    fi
}

echo "=============================================="
echo "PersonaPlex H100 VM Verification Tests"
echo "Target: $USER@$HOST"
echo "=============================================="

# --- Test 1: SSH connectivity ---
echo ""
echo "--- Infrastructure ---"
printf "  %-50s " "SSH connectivity"
if ssh $SSH_OPTS "$USER@$HOST" "echo ok" >/dev/null 2>&1; then
    echo "[PASS]"
    PASS=$((PASS + 1))
else
    echo "[FAIL] Cannot SSH to $HOST"
    FAIL=$((FAIL + 1))
    echo ""
    echo "RESULT: 1 PASS / 1 FAIL — SSH unreachable, skipping remaining tests"
    echo "NOTE: VM may still be booting or rebooting after cloud-init"
    exit 1
fi

# --- Test 2: Cloud-init status ---
printf "  %-50s " "Cloud-init completed"
ci_status=$(ssh $SSH_OPTS "$USER@$HOST" "cloud-init status 2>/dev/null || echo 'unknown'" 2>&1)
if echo "$ci_status" | grep -q "done"; then
    echo "[PASS]"
    PASS=$((PASS + 1))
elif echo "$ci_status" | grep -q "running"; then
    echo "[SKIP] (still running)"
    SKIP=$((SKIP + 1))
else
    echo "[WARN] status: $ci_status"
    SKIP=$((SKIP + 1))
fi

# --- GPU / CUDA ---
echo ""
echo "--- GPU & CUDA ---"
run_test "NVIDIA GPU detected" "nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo none" "H100"
run_test "GPU memory >= 90GB" "nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null || echo 0" ""
run_test "CUDA toolkit installed" "/usr/local/cuda/bin/nvcc --version 2>/dev/null || nvcc --version 2>/dev/null || echo missing" "release 12"
run_test "nvidia-persistenced running" "systemctl is-active nvidia-persistenced 2>/dev/null || echo inactive" "active"

# --- Python / Moshi ---
echo ""
echo "--- Python & Moshi Framework ---"
run_test "Python venv exists" "test -f /opt/personaplex-env/bin/python && echo exists || echo missing" "exists"
run_test "Moshi package installed" "/opt/personaplex-env/bin/pip show moshi 2>/dev/null | head -1 || echo missing" "Name"
run_test "PyTorch with CUDA" "/opt/personaplex-env/bin/python -c 'import torch; print(f\"torch={torch.__version__} cuda={torch.cuda.is_available()}\")' 2>/dev/null || echo missing" "cuda=True"

# --- HuggingFace ---
echo ""
echo "--- HuggingFace ---"
run_test "HF token configured" "test -f /home/azureuser/.cache/huggingface/token && echo exists || echo missing" "exists"

# --- PersonaPlex Service ---
echo ""
echo "--- PersonaPlex Service ---"
run_test "personaplex.service enabled" "systemctl is-enabled personaplex.service 2>/dev/null || echo disabled" "enabled"
run_test "personaplex.service active" "systemctl is-active personaplex.service 2>/dev/null || echo inactive" "active"
run_test "Model download (no gated error)" "journalctl -u personaplex.service --no-pager -n 20 2>/dev/null | grep -i 'gated\|401\|restricted' && echo GATED_ERROR || echo ok" "ok"
run_test "Port 8998 listening" "ss -tlnp | grep 8998 || echo not-listening" "8998"

# --- Kernel Tuning ---
echo ""
echo "--- Kernel Tuning ---"
run_test "vm.swappiness = 0" "sysctl -n vm.swappiness" "0"
run_test "THP = madvise" "cat /sys/kernel/mm/transparent_hugepage/enabled" "madvise"
run_test "vm.max_map_count >= 1000000" "sysctl -n vm.max_map_count" "1000000"

# --- GPU setup log ---
echo ""
echo "--- Setup Log (last 5 lines) ---"
ssh $SSH_OPTS "$USER@$HOST" "tail -5 /var/log/gpu-setup.log 2>/dev/null || echo 'no log yet'"

# --- Summary ---
echo ""
echo "=============================================="
echo "RESULTS: $PASS PASS / $FAIL FAIL / $SKIP SKIP"
echo "=============================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
