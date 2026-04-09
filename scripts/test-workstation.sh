#!/bin/bash
# Functional tests for workstation AI tools and web search stack
# Verifies: infrastructure health, LLM ping-pong, Firecrawl/SearXNG web search
# Downloaded and executed by cloud-init after all setup scripts complete.
#
# Usage: test-workstation.sh <admin_username>
set -uo pipefail

ADMIN_USER="${1:?Usage: test-workstation.sh <admin_username>}"

LOG_DIR="/var/log"
exec > >(tee -a "${LOG_DIR}/workstation-test.log") \
     2> >(tee -a "${LOG_DIR}/workstation-test.log" >&2)

source /etc/profile.d/llm-endpoints.sh

PASS=0
FAIL=0
TIMEOUT=90

echo "=== Workstation Functional Tests: $(date) ==="

# ---- Test helper ----
# Usage: run_test <name> <command> <grep_pattern>
# Runs command with timeout, greps output for pattern (case-insensitive).
run_test() {
    local name="$1" cmd="$2" pattern="$3"
    local result exit_code=0
    result=$(timeout "${TIMEOUT}" bash -c "$cmd" 2>&1) || exit_code=$?
    if [ "${exit_code}" -eq 124 ]; then
        echo "  [FAIL] ${name}: timed out (${TIMEOUT}s)"
        FAIL=$((FAIL + 1))
        return
    fi
    if echo "${result}" | grep -qiE "${pattern}"; then
        echo "  [PASS] ${name}"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] ${name}"
        echo "         output: $(echo "${result}" | head -3 | tr '\n' ' ')"
        FAIL=$((FAIL + 1))
    fi
}

# Variant for tests that must run as the admin user (user-local tools)
run_test_as_user() {
    local name="$1" cmd="$2" pattern="$3"
    run_test "${name}" "sudo -u ${ADMIN_USER} bash -c 'export HOME=/home/${ADMIN_USER} && export PATH=/home/${ADMIN_USER}/.local/bin:/home/${ADMIN_USER}/.cargo/bin:/usr/local/bin:/usr/bin:/bin && source /etc/profile.d/llm-endpoints.sh && ${cmd}'" "${pattern}"
}

# ============================================================
# SECTION 1: Infrastructure health checks
# ============================================================
echo "--- Infrastructure ---"

run_test "searxng" \
    "curl -sf http://localhost:8888/healthz" \
    "."

run_test "firecrawl-search" \
    'curl -sf http://localhost:3002/v1/search -X POST -H "Content-Type: application/json" -d "{\"query\":\"ping\",\"limit\":1}" | jq -r .success' \
    "true"

run_test "claude-code-proxy" \
    "systemctl is-active claude-code-proxy" \
    "^active"

LARGE_HEALTH="${LARGE_LLM_BASE_URL%/v1}/health"
SMALL_HEALTH="${SMALL_LLM_BASE_URL%/v1}/health"
VISION_HEALTH="${VISION_LLM_BASE_URL%/v1}/health"
MEDIUM_HEALTH="${MEDIUM_LLM_BASE_URL%/v1}/health"

run_test "vllm-large" \
    "curl -so /dev/null -w '%{http_code}' ${LARGE_HEALTH}" \
    "200"

run_test "vllm-small" \
    "curl -so /dev/null -w '%{http_code}' ${SMALL_HEALTH}" \
    "200"

run_test "vllm-vision" \
    "curl -so /dev/null -w '%{http_code}' ${VISION_HEALTH}" \
    "200"

run_test "vllm-medium" \
    "curl -so /dev/null -w '%{http_code}' ${MEDIUM_HEALTH}" \
    "200"

# ============================================================
# SECTION 2: Ping-pong (LLM backend connectivity)
# ============================================================
echo "--- Ping-pong ---"

run_test_as_user "claude-ping" \
    'claude -p "respond with exactly one word: pong" --max-turns 1 --allowedTools "" 2>&1' \
    "pong"

run_test_as_user "pi-ping" \
    'pi -p "respond with exactly one word: pong" --no-tools --provider openai 2>&1' \
    "pong"

run_test_as_user "opencode-ping" \
    'opencode run "respond with exactly one word: pong" 2>&1' \
    "pong"

run_test_as_user "omp-ping" \
    'omp -p "respond with exactly one word: pong" --no-tools --provider openai 2>&1' \
    "pong"

# ============================================================
# SECTION 3: Web search (Firecrawl/SearXNG end-to-end)
# ============================================================
echo "--- Web search ---"

run_test_as_user "claude-websearch" \
    'claude -p "Use web_search to find: what is the current latest stable Python version number? Reply with ONLY the version number." --dangerously-skip-permissions --max-turns 5 2>&1' \
    "3\.[0-9]"

run_test_as_user "pi-websearch" \
    'pi -p "Search the web for: what is the latest stable Python version number? Reply with ONLY the version." --provider openai 2>&1' \
    "3\.[0-9]|\."

run_test_as_user "omp-websearch" \
    'omp -p "Search the web for: what is the latest stable Python version number? Reply with ONLY the version." --provider openai 2>&1' \
    "3\.[0-9]|\."

# ============================================================
# Summary
# ============================================================
TOTAL=$((PASS + FAIL))
echo "---"
echo "Tests: ${PASS} passed, ${FAIL} failed (${TOTAL} total)"
echo "=== Workstation Functional Tests Complete: $(date) ==="

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
exit 0
