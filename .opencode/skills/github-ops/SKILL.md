---
name: github-ops
description: GitHub operations toolkit — PR descriptions, code review, issue triage, commit messages, and gh CLI command generation
compatibility: opencode
metadata:
  model: phi-4-mini
  port: "8001"
---

# GitHub Operations Skill

Use this skill for any GitHub-related operation. It provides structured workflows for common tasks.

## When to use

- Writing PR titles and descriptions from diffs
- Reviewing code for bugs and security issues
- Triaging issues with labels and priority
- Generating conventional commit messages
- Constructing gh CLI commands

## PR Description Workflow

1. Run `git diff` to get the changes
2. Identify the files and purpose of the change
3. Write a concise title (under 70 chars)
4. Write a markdown body: what changed, why, and testing notes

## Code Review Workflow

1. Read the code carefully
2. Check for: injection vulnerabilities, auth issues, resource leaks, race conditions, error handling
3. For each issue: state the bug type, severity (critical/high/medium/low), and a specific fix
4. If no issues found, confirm the code is clean

## Issue Triage Workflow

Respond with JSON:
```json
{
  "labels": ["bug", "security"],
  "priority": "high",
  "category": "infrastructure"
}
```

Labels: bug, enhancement, documentation, security, question, performance
Priority: high, medium, low
Category: infrastructure, feature, docs, security, performance, question

## Commit Message Workflow

Follow Conventional Commits:
```
type(scope): short description

Optional body explaining why the change was made.
```

Types: feat, fix, docs, refactor, chore, test, style, perf, ci, build

## gh CLI Reference

Common patterns:
- `gh pr create --draft --title "..." --body "..."`
- `gh issue create --title "..." --label bug --label security`
- `gh pr merge 42 --squash --delete-branch`
- `gh issue close 7 --comment "Fixed in #12"`
- `gh run list --limit 5`
- `gh release create v1.0.0 --generate-notes`
