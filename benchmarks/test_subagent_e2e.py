#!/usr/bin/env python3
"""
End-to-end sub-agent test against the live repo.

Runs real GitHub operations tasks using:
  - actual git diff from this repo
  - actual gh CLI on authenticated session
  - actual issue data
"""

import json
import subprocess
import urllib.request

BASE_URL = "http://localhost:8001/v1/chat/completions"
MODEL = "phi-4-mini"


def call_subagent(system: str, user: str, max_tokens: int = 400) -> str:
    payload = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "max_tokens": max_tokens,
        "temperature": 0.3,
    }).encode()
    req = urllib.request.Request(BASE_URL, data=payload, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read())
        return data["choices"][0]["message"]["content"]


def run(cmd: str) -> str:
    return subprocess.check_output(cmd, shell=True, text=True, timeout=15).strip()


print("=" * 70)
print("End-to-End Sub-Agent Test (live repo + gh auth)")
print("=" * 70)

# --- Test 1: Real commit message from actual repo diff ---
print("\n[1/5] COMMIT MESSAGE from real repo diff")
try:
    diff = run("cd ~/azure-llm 2>/dev/null && git log -1 --format=%B HEAD || echo 'no repo'")
    real_diff = run("cd ~/azure-llm 2>/dev/null && git diff HEAD~1 --stat || echo 'no diff'")
    if "no repo" in diff:
        print("  SKIP: ~/azure-llm repo not found")
    else:
        result = call_subagent(
            "You are writing a git commit message following Conventional Commits. Format: type(scope): description. Respond ONLY with the commit message.",
            f"Generate a commit message for these changes:\n\n{real_diff}"
        )
        print(f"  OUTPUT: {result[:200]}")
        print("  PASS" if any(t in result.lower() for t in ["feat", "fix", "docs", "refactor", "chore"]) else "  WARN: no conventional type")
except Exception as e:
    print(f"  ERROR: {e}")

# --- Test 2: PR description from actual diff ---
print("\n[2/5] PR DESCRIPTION from real diff")
try:
    stat = run("cd ~/azure-llm 2>/dev/null && git diff HEAD~3 --stat | head -20 || echo 'no diff'")
    result = call_subagent(
        "You are a developer writing a pull request. Write a concise PR title on the first line, then a blank line, then a markdown description explaining what changed and why.",
        f"Write a PR description for these changes:\n\n{stat}"
    )
    lines = result.strip().split("\n")
    has_title = len(lines[0]) > 5
    has_body = len(result) > 100
    print(f"  TITLE: {lines[0][:80]}")
    print(f"  BODY: {len(result)} chars, {'has markdown' if '#' in result or '-' in result or '*' in result else 'plain text'}")
    print(f"  PASS" if has_title and has_body else "  WARN: missing title or body")
except Exception as e:
    print(f"  ERROR: {e}")

# --- Test 3: Code review on real file ---
print("\n[3/5] CODE REVIEW on real setup script")
try:
    code = run("head -30 ~/benchmarks/run_github_ops.sh 2>/dev/null || echo 'file not found'")
    result = call_subagent(
        "You are a senior code reviewer. Analyze the code for bugs, security issues, and improvements. Be specific.",
        f"Review this bash script:\n\n{code}"
    )
    print(f"  OUTPUT: {result[:300]}")
    print("  PASS" if len(result) > 50 else "  WARN: too short")
except Exception as e:
    print(f"  ERROR: {e}")

# --- Test 4: gh CLI with real repo ---
print("\n[4/5] GH CLI - list real issues")
try:
    result = call_subagent(
        "You are a GitHub CLI expert. Respond ONLY with the gh command.",
        "List the 5 most recent open issues in the current repository, showing their number, title, and labels"
    )
    print(f"  COMMAND: {result[:200]}")
    is_gh = result.strip().startswith("gh ")
    print(f"  PASS" if is_gh else "  WARN: not a gh command")
    if is_gh:
        # Actually run it
        cmd = result.strip().split("\n")[0]
        for line in cmd.split("\n"):
            if line.strip().startswith("gh "):
                cmd = line.strip()
                break
        try:
            gh_output = run(f"cd ~/azure-llm 2>/dev/null && {cmd} 2>&1 | head -10")
            print(f"  EXECUTED: {gh_output[:200]}")
        except Exception as ex:
            print(f"  EXEC WARN: {ex}")
except Exception as e:
    print(f"  ERROR: {e}")

# --- Test 5: Issue triage ---
print("\n[5/5] ISSUE TRIAGE")
try:
    result = call_subagent(
        'Respond with JSON: {"labels": [...], "priority": "high|medium|low", "category": "infrastructure|feature|docs|security"}. ONLY JSON.',
        "Title: HF token exposed in cloud-init user-data\n\nBody: The HuggingFace token is injected via Terraform templatefile into cloud-init.yaml and ends up in the VM user-data metadata. Anyone with VM metadata access can read it."
    )
    print(f"  OUTPUT: {result[:300]}")
    # Try to parse JSON
    try:
        parsed = json.loads(result.strip().strip("`").strip())
        has_security = "security" in [l.lower() for l in parsed.get("labels", [])]
        is_high = parsed.get("priority", "").lower() == "high"
        print(f"  LABELS: {parsed.get('labels')}")
        print(f"  PRIORITY: {parsed.get('priority')}")
        print(f"  PASS" if has_security and is_high else "  WARN: expected security + high priority")
    except json.JSONDecodeError:
        # Check for JSON in markdown
        import re
        m = re.search(r'\{[^}]+\}', result, re.DOTALL)
        if m:
            parsed = json.loads(m.group())
            print(f"  LABELS: {parsed.get('labels')}")
            print(f"  PASS (extracted from markdown)")
        else:
            print("  WARN: could not parse JSON")
except Exception as e:
    print(f"  ERROR: {e}")

print("\n" + "=" * 70)
print("End-to-end test complete.")
