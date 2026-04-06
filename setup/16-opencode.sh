#!/bin/bash
# ==============================================================================
# SECTION 16: OPENCODE (AI coding agent with local vLLM backend)
#   Uses environment variables: ADMIN_USERNAME, VLLM_PORT, SERVED_MODEL_NAME,
#   SUBAGENT_PORT, SUBAGENT_SERVED_NAME, SUBAGENT_MODEL_ID, SUBAGENT_MAX_MODEL_LEN
# ==============================================================================

ADMIN_USERNAME="${ADMIN_USERNAME:-azureuser}"
VLLM_PORT="${VLLM_PORT:-8000}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-gemma-4-31b}"
SUBAGENT_PORT="${SUBAGENT_PORT:-8001}"
SUBAGENT_SERVED_NAME="${SUBAGENT_SERVED_NAME:-phi-4-mini}"
SUBAGENT_MODEL_ID="${SUBAGENT_MODEL_ID:-microsoft/Phi-4-mini-instruct}"
SUBAGENT_MAX_MODEL_LEN="${SUBAGENT_MAX_MODEL_LEN:-16384}"

# ---- Install OpenCode CLI ----
npm install -g opencode-ai 2>/dev/null || true

# ---- Create config directories ----
OPENCODE_DIR="/home/${ADMIN_USERNAME}/.opencode"
mkdir -p "${OPENCODE_DIR}/agents"
mkdir -p "${OPENCODE_DIR}/skills/github-ops"

# ---- OpenCode configuration (dual provider: main + sub-agent) ----
cat > "${OPENCODE_DIR}/opencode.json" <<OCCONF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "vllm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "vLLM Main (${SERVED_MODEL_NAME})",
      "options": {
        "baseURL": "http://localhost:${VLLM_PORT}/v1",
        "apiKey": "local-vllm"
      },
      "models": {
        "${SERVED_MODEL_NAME}": {
          "name": "${SERVED_MODEL_NAME}",
          "limit": { "context": 131072, "output": 8192 }
        }
      }
    },
    "vllm-subagent": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "vLLM Sub-Agent (${SUBAGENT_SERVED_NAME})",
      "options": {
        "baseURL": "http://localhost:${SUBAGENT_PORT}/v1",
        "apiKey": "local-vllm"
      },
      "models": {
        "${SUBAGENT_SERVED_NAME}": {
          "name": "${SUBAGENT_SERVED_NAME} (GitHub Ops)",
          "limit": { "context": ${SUBAGENT_MAX_MODEL_LEN}, "output": 4096 }
        }
      }
    }
  },
  "model": "vllm/${SERVED_MODEL_NAME}"
}
OCCONF

# ---- GitHub operations sub-agent (routes to Phi-4-mini on port 8001) ----
cat > "${OPENCODE_DIR}/agents/github-ops.md" <<AGENT
---
description: GitHub operations specialist — PR descriptions, code review, issue triage, commit messages, gh CLI commands
mode: subagent
model: vllm-subagent/${SUBAGENT_SERVED_NAME}
temperature: 0.3
permission:
  bash:
    "gh *": allow
    "git log *": allow
    "git diff *": allow
    "git status": allow
    "*": deny
  edit: deny
  webfetch: deny
---

You are a specialized GitHub operations agent running on a local ${SUBAGENT_SERVED_NAME} model. Your expertise:

- **PR descriptions**: Given a git diff, write a title and markdown description explaining what changed and why
- **Code review**: Analyze code for bugs, security vulnerabilities, and suggest specific fixes with severity ratings
- **Issue triage**: Classify issues with labels, priority, and category. Respond with JSON.
- **Commit messages**: Generate conventional commit messages (type(scope): description) from diffs
- **gh CLI**: Generate correct gh commands for any GitHub operation

## Rules

- Use gh CLI exclusively — never curl or raw API calls
- Follow Conventional Commits: feat|fix|docs|refactor|chore|test(scope): description
- Prioritize security issues over style in reviews
- Keep commit message first lines under 72 characters
AGENT

# ---- GitHub operations skill ----
cat > "${OPENCODE_DIR}/skills/github-ops/SKILL.md" <<'SKILL'
---
name: github-ops
description: GitHub operations toolkit — PR descriptions, code review, issue triage, commit messages, and gh CLI command generation
compatibility: opencode
metadata:
  model: phi-4-mini
  port: "8001"
---

# GitHub Operations Skill

Use this skill for any GitHub-related operation.

## When to use

- Writing PR titles and descriptions from diffs
- Reviewing code for bugs and security issues
- Triaging issues with labels and priority
- Generating conventional commit messages
- Constructing gh CLI commands

## PR Description Workflow

1. Run git diff to get the changes
2. Identify the files and purpose of the change
3. Write a concise title (under 70 chars)
4. Write a markdown body: what changed, why, and testing notes

## Code Review Workflow

1. Read the code carefully
2. Check for: injection vulnerabilities, auth issues, resource leaks, race conditions, error handling
3. For each issue: state the bug type, severity (critical/high/medium/low), and a specific fix

## Issue Triage

Respond with JSON: {"labels": [...], "priority": "high|medium|low", "category": "..."}

## Commit Messages

Follow Conventional Commits: type(scope): short description

Types: feat, fix, docs, refactor, chore, test, style, perf, ci, build
SKILL

# ---- Fix ownership ----
chown -R "${ADMIN_USERNAME}:${ADMIN_USERNAME}" "${OPENCODE_DIR}"

echo "OpenCode installed and configured:"
echo "  Main model:  vllm/${SERVED_MODEL_NAME} (port ${VLLM_PORT})"
echo "  Sub-agent:   vllm-subagent/${SUBAGENT_SERVED_NAME} (port ${SUBAGENT_PORT})"
echo "  Agent:       github-ops (mode: subagent)"
echo "  Skill:       github-ops"
