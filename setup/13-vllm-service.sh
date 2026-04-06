#!/bin/bash
# ==============================================================================
# SECTION 13: vLLM SERVICE & CONVENIENCE SCRIPTS
#   Uses environment variables: MODEL_ID, SERVED_MODEL_NAME, MAX_MODEL_LEN,
#   GPU_MEMORY_UTILIZATION, TOOL_CALL_PARSER, VLLM_PORT, HF_TOKEN, ADMIN_USERNAME
# ==============================================================================

MODEL_ID="${MODEL_ID:-google/gemma-4-31B-it}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-gemma-4-31b}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-131072}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.95}"
TOOL_CALL_PARSER="${TOOL_CALL_PARSER:-gemma4}"
VLLM_PORT="${VLLM_PORT:-8000}"

# ---- Primary vLLM start script ----
cat > /usr/local/bin/start-vllm <<SCRIPT
#!/bin/bash
echo "Starting vLLM with ${MODEL_ID} (${TOOL_CALL_PARSER} tool parser)..."
echo "Model download may take 5-10 minutes on first run."
export HF_TOKEN="\${HF_TOKEN:-\$(cat /home/${ADMIN_USERNAME}/.cache/huggingface/token 2>/dev/null)}"
exec /opt/vllm-env/bin/python -m vllm.entrypoints.openai.api_server \\
  --model ${MODEL_ID} \\
  --served-model-name ${SERVED_MODEL_NAME} \\
  --tensor-parallel-size 2 \\
  --max-model-len ${MAX_MODEL_LEN} \\
  --gpu-memory-utilization ${GPU_MEMORY_UTILIZATION} \\
  --enable-auto-tool-choice \\
  --tool-call-parser ${TOOL_CALL_PARSER} \\
  --reasoning-parser gemma4 \\
  --async-scheduling \\
  --mm-processor-kwargs '{"max_soft_tokens": 560}' \\
  --limit-mm-per-prompt '{"image": 4}' \\
  --host 0.0.0.0 \\
  --port ${VLLM_PORT}
SCRIPT
chmod +x /usr/local/bin/start-vllm

# ---- Hermes fallback (if native parser has issues) ----
cat > /usr/local/bin/start-vllm-hermes <<SCRIPT
#!/bin/bash
echo "Starting vLLM with ${MODEL_ID} (hermes tool parser fallback)..."
export HF_TOKEN="\${HF_TOKEN:-\$(cat /home/${ADMIN_USERNAME}/.cache/huggingface/token 2>/dev/null)}"
exec /opt/vllm-env/bin/python -m vllm.entrypoints.openai.api_server \\
  --model ${MODEL_ID} \\
  --served-model-name ${SERVED_MODEL_NAME} \\
  --tensor-parallel-size 2 \\
  --max-model-len ${MAX_MODEL_LEN} \\
  --gpu-memory-utilization ${GPU_MEMORY_UTILIZATION} \\
  --enable-auto-tool-choice \\
  --tool-call-parser hermes \\
  --async-scheduling \\
  --mm-processor-kwargs '{"max_soft_tokens": 560}' \\
  --limit-mm-per-prompt '{"image": 4}' \\
  --host 0.0.0.0 \\
  --port ${VLLM_PORT}
SCRIPT
chmod +x /usr/local/bin/start-vllm-hermes

# ---- Claude Code launcher ----
cat > /usr/local/bin/start-claude-code <<'SCRIPT'
#!/bin/bash
echo "Waiting for vLLM to be ready..."
for i in $(seq 1 120); do
  if curl -sf http://localhost:${VLLM_PORT:-8000}/health > /dev/null 2>&1; then
    echo "vLLM is ready. Launching Claude Code..."
    exec claude
  fi
  sleep 5
done
echo "ERROR: vLLM not ready after 10 minutes. Start it with: start-vllm"
exit 1
SCRIPT
chmod +x /usr/local/bin/start-claude-code

# ---- Systemd service (auto-start on boot) ----
cat > /etc/systemd/system/vllm.service <<SYSTEMD
[Unit]
Description=vLLM Inference Server (${SERVED_MODEL_NAME})
After=network.target nvidia-persistenced.service

[Service]
Type=simple
User=${ADMIN_USERNAME}
Environment=HF_TOKEN=${HF_TOKEN:-}
ExecStart=/usr/local/bin/start-vllm
Restart=on-failure
RestartSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
SYSTEMD
systemctl daemon-reload
systemctl enable vllm.service

echo "vLLM service configured: start-vllm, start-vllm-hermes, start-claude-code"
