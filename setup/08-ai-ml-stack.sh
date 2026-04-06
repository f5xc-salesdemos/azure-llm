#!/bin/bash
# ==============================================================================
# SECTION 8: AI/ML STACK (vLLM + transformers)
# ==============================================================================

export PATH="/root/.local/bin:$PATH"

# Python venv for vLLM
python3 -m venv /opt/vllm-env
/opt/vllm-env/bin/pip install --upgrade pip

# vLLM nightly (required for Gemma 4 gemma4 architecture support)
uv pip install --python /opt/vllm-env/bin/python -U vllm --pre \
  --extra-index-url https://wheels.vllm.ai/nightly/cu129 \
  --extra-index-url https://download.pytorch.org/whl/cu129 \
  --index-strategy unsafe-best-match

# Transformers 5.5.0 (Gemma 4 architecture)
uv pip install --python /opt/vllm-env/bin/python transformers==5.5.0

# Benchmark dependencies
/opt/vllm-env/bin/pip install aiohttp tabulate

echo "AI/ML stack installed: vLLM nightly + transformers 5.5.0"
