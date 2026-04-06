#!/bin/bash
# ==============================================================================
# SECTION 11: CLAUDE CODE & AI ASSISTANTS
# ==============================================================================

# Claude Code CLI
npm install -g @anthropic-ai/claude-code

# HuggingFace token (from environment or Terraform)
if [ -n "${HF_TOKEN:-}" ]; then
  mkdir -p /home/${ADMIN_USERNAME}/.cache/huggingface
  echo "$HF_TOKEN" > /home/${ADMIN_USERNAME}/.cache/huggingface/token
  chmod 600 /home/${ADMIN_USERNAME}/.cache/huggingface/token
fi

# Copy /etc/skel to admin user (skel files written by cloud-init write_files)
cp -r /etc/skel/.claude /home/${ADMIN_USERNAME}/.claude 2>/dev/null || true
cp /etc/skel/.claude.json /home/${ADMIN_USERNAME}/.claude.json 2>/dev/null || true
chown -R ${ADMIN_USERNAME}:${ADMIN_USERNAME} /home/${ADMIN_USERNAME}/.claude /home/${ADMIN_USERNAME}/.claude.json /home/${ADMIN_USERNAME}/.cache 2>/dev/null || true

echo "Claude Code installed and configured"
