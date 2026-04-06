#!/usr/bin/env python3
"""Quick test of all 5 GitHub operations task types against the sub-agent."""

import json
import sys
import urllib.request

BASE_URL = "http://localhost:8001/v1/chat/completions"
MODEL = "phi-4-mini"

TESTS = [
    {
        "name": "COMMIT MESSAGE",
        "system": "You are writing a git commit message following Conventional Commits. Format: type(scope): description. Types: feat, fix, docs, refactor, chore. Keep first line under 72 chars. Respond ONLY with the commit message.",
        "user": "Generate a commit message for this diff:\n\ndiff --git a/setup/12-shell-environment.sh\n-curl -Lo /usr/local/bin/nvim AppImage-URL\n+# Neovim (apt preferred -- AppImage fails on Ubuntu 24.04)\n+apt-get install -y neovim",
    },
    {
        "name": "PR DESCRIPTION",
        "system": "You are a developer writing a pull request. Given a git diff, write a concise PR title on the first line, then a blank line, then a markdown description explaining what changed and why.",
        "user": "Here is the git diff:\n\ndiff --git a/variables.tf\n+variable \"hf_token\" {\n+  description = \"HuggingFace API token for gated models\"\n+  type = string\n+  sensitive = true\n+}",
    },
    {
        "name": "CODE REVIEW",
        "system": "You are a senior code reviewer. For each issue: state bug type, severity (critical/high/medium/low), and suggested fix.",
        "user": "Review this python code:\n\ndef get_user(uid):\n    q = f\"SELECT * FROM users WHERE id = '{uid}'\"\n    cursor.execute(q)\n    return cursor.fetchone()",
    },
    {
        "name": "ISSUE TRIAGE",
        "system": "You are a project maintainer triaging an issue. Respond with JSON: {\"labels\": [...], \"priority\": \"high|medium|low\", \"category\": \"infrastructure|feature|docs|security\"}. Respond ONLY with JSON.",
        "user": "Title: vLLM OOM when loading Llama 4 Scout on single A100\n\nBody: CUDA OOM error loading 109B MoE model on 80GB GPU. Needs TP=2 or quantization.",
    },
    {
        "name": "GH CLI",
        "system": "You are a GitHub CLI expert. Respond ONLY with the gh command, no explanation.",
        "user": "Create a draft pull request from current branch to main with title 'Fix vLLM startup race condition'",
    },
]


def run_test(test):
    payload = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": test["system"]},
            {"role": "user", "content": test["user"]},
        ],
        "max_tokens": 300,
        "temperature": 0.3,
    }).encode()

    req = urllib.request.Request(BASE_URL, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read())
            content = data["choices"][0]["message"]["content"]
            return content
    except Exception as e:
        return f"ERROR: {e}"


print("=" * 70)
print("Sub-Agent Task Validation (Phi-4-mini on port 8001)")
print("=" * 70)

all_pass = True
for test in TESTS:
    print(f"\n--- {test['name']} ---")
    result = run_test(test)
    print(result[:500])
    if result.startswith("ERROR"):
        all_pass = False
    print()

print("=" * 70)
if all_pass:
    print("ALL 5 TASK TYPES: PASSED")
else:
    print("SOME TASKS FAILED")
    sys.exit(1)
