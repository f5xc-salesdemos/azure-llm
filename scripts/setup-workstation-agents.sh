#!/bin/bash
# AI agent configuration (Codex, Pi, Hermes, Claude Code, OpenCode).
# Downloaded and executed by cloud-init. Reads env vars from /etc/profile.d/llm-endpoints.sh.
set -euo pipefail
exec > >(tee -a /var/log/workstation-agents-setup.log) 2>&1
echo "=== Agent Config Started: $(date) ==="

# Validate required env vars
ADMIN_USER="${LLM_ADMIN_USER:?LLM_ADMIN_USER not set}"
UHOME="/home/${ADMIN_USER}"
: "${LARGE_LLM_BASE_URL:?}" "${LARGE_LLM_MODEL:?}" "${LARGE_LLM_CTX:?}"
: "${SMALL_LLM_BASE_URL:?}" "${SMALL_LLM_MODEL:?}" "${SMALL_LLM_CTX:?}"
: "${MEDIUM_LLM_BASE_URL:?}" "${MEDIUM_LLM_MODEL:?}" "${MEDIUM_LLM_CTX:?}"
: "${VISION_LLM_BASE_URL:?}" "${VISION_LLM_MODEL:?}" "${VISION_LLM_CTX:?}"

# Strip /v1 suffix for ANTHROPIC_BASE_URL (Claude Code expects no /v1)
LARGE_LLM_BASE_URL_NOPATH="${LARGE_LLM_BASE_URL%/v1}"

# ============================================================
# 1. Codex config (~/.codex/config.toml)
# ============================================================
mkdir -p "${UHOME}/.codex"
cat > "${UHOME}/.codex/config.toml" <<'CODEX'
model = "__LARGE_LLM_MODEL__"
model_provider = "vllm-local"
sandbox_mode = "danger-full-access"
approval_policy = "never"
model_reasoning_effort = "high"
personality = "pragmatic"
hide_agent_reasoning = true
[model_providers.vllm-local]
name = "vLLM Primary"
base_url = "__LARGE_LLM_BASE_URL__"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
query_params = {}
[features]
multi_agent = true
shell_tool = true
fast_mode = true
[projects."__UHOME__"]
trust_level = "trusted"
CODEX
sed -i "s|__LARGE_LLM_MODEL__|${LARGE_LLM_MODEL}|g; s|__LARGE_LLM_BASE_URL__|${LARGE_LLM_BASE_URL}|g; s|__UHOME__|${UHOME}|g" "${UHOME}/.codex/config.toml"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.codex"

# ============================================================
# 2. Pi config (vLLM multi-model + subagents)
# ============================================================
mkdir -p "${UHOME}/.pi/agent/agents"

# settings.json
cat > "${UHOME}/.pi/agent/settings.json" <<'PICONF'
{
  "defaultProvider": "openai",
  "defaultModel": "__LARGE_LLM_MODEL__",
  "quietStartup": true,
  "defaultThinkingLevel": "off",
  "hideThinkingBlock": true,
  "packages": []
}
PICONF
sed -i "s|__LARGE_LLM_MODEL__|${LARGE_LLM_MODEL}|g" "${UHOME}/.pi/agent/settings.json"

# models.json — 3 providers (openai=largeLLM, mediumLLM, smallLLM)
cat > "${UHOME}/.pi/agent/models.json" <<'PIMODELS'
{
  "providers": {
    "openai": {
      "baseUrl": "__LARGE_LLM_BASE_URL__",
      "apiKey": "local-vllm",
      "models": [
        {
          "id": "__LARGE_LLM_MODEL__",
          "name": "Large LLM (vLLM)",
          "api": "openai-completions",
          "reasoning": true,
          "contextWindow": __LARGE_LLM_CTX__,
          "maxTokens": 8192
        }
      ]
    },
    "mediumllm": {
      "baseUrl": "__MEDIUM_LLM_BASE_URL__",
      "apiKey": "local-vllm",
      "models": [
        {
          "id": "__MEDIUM_LLM_MODEL__",
          "name": "Medium LLM (vLLM)",
          "api": "openai-completions",
          "reasoning": true,
          "contextWindow": __MEDIUM_LLM_CTX__,
          "maxTokens": 4096
        }
      ]
    },
    "smallllm": {
      "baseUrl": "__SMALL_LLM_BASE_URL__",
      "apiKey": "local-vllm",
      "models": [
        {
          "id": "__SMALL_LLM_MODEL__",
          "name": "Small LLM (vLLM)",
          "api": "openai-completions",
          "reasoning": false,
          "contextWindow": __SMALL_LLM_CTX__,
          "maxTokens": 4096
        }
      ]
    }
  }
}
PIMODELS
sed -i "s|__LARGE_LLM_BASE_URL__|${LARGE_LLM_BASE_URL}|g; s|__LARGE_LLM_MODEL__|${LARGE_LLM_MODEL}|g; s|__LARGE_LLM_CTX__|${LARGE_LLM_CTX}|g" "${UHOME}/.pi/agent/models.json"
sed -i "s|__MEDIUM_LLM_BASE_URL__|${MEDIUM_LLM_BASE_URL}|g; s|__MEDIUM_LLM_MODEL__|${MEDIUM_LLM_MODEL}|g; s|__MEDIUM_LLM_CTX__|${MEDIUM_LLM_CTX}|g" "${UHOME}/.pi/agent/models.json"
sed -i "s|__SMALL_LLM_BASE_URL__|${SMALL_LLM_BASE_URL}|g; s|__SMALL_LLM_MODEL__|${SMALL_LLM_MODEL}|g; s|__SMALL_LLM_CTX__|${SMALL_LLM_CTX}|g" "${UHOME}/.pi/agent/models.json"

# f5xc-api agent (mediumLLM — model name placeholder, rest is literal)
cat > "${UHOME}/.pi/agent/agents/f5xc-api.md" <<'PIF5XC'
---
name: f5xc-api
description: "ALWAYS delegate to this agent for any F5 Distributed Cloud, F5 XC, Volterra, load balancer, origin pool, WAF, DNS, or API platform operation. This agent executes curl commands against the F5 XC REST API using environment variables F5XC_API_URL, F5XC_API_TOKEN, and F5XC_NAMESPACE."
model: mediumllm/__MEDIUM_LLM_MODEL__
tools: bash
---

You are an F5 Distributed Cloud API operations agent. You MUST execute REST API calls using the bash tool with curl commands. NEVER output curl commands as text — always execute them.

## Authentication
All API calls use: curl -s "$F5XC_API_URL/..." -H "Authorization: APIToken $F5XC_API_TOKEN" | jq .
Required env vars: F5XC_API_URL, F5XC_API_TOKEN, F5XC_NAMESPACE

## CRUD Pattern
- List:    GET    /api/config/namespaces/{ns}/{resources}
- Create:  POST   /api/config/namespaces/{ns}/{resources}
- Get:     GET    /api/config/namespaces/{ns}/{resources}/{name}
- Replace: PUT    /api/config/namespaces/{ns}/{resources}/{name}
- Delete:  DELETE /api/config/namespaces/{ns}/{resources}/{name}

## Rules
1. Always use curl -s with APIToken header
2. Always pipe through jq
3. Use env vars — never hardcode URLs or tokens
PIF5XC
sed -i "s|__MEDIUM_LLM_MODEL__|${MEDIUM_LLM_MODEL}|g" "${UHOME}/.pi/agent/agents/f5xc-api.md"

# github-ops agent (smallLLM — model name placeholder, rest is literal)
cat > "${UHOME}/.pi/agent/agents/github-ops.md" <<'PIGHOPS'
---
name: github-ops
description: "ALWAYS delegate to this agent for ANY GitHub operation: pull requests, issues, branches, merges, forks, worktrees, workflow runs, code review, commit messages, release management, repository settings, and any gh CLI or GitHub API task."
model: smallllm/__SMALL_LLM_MODEL__
tools: bash,read
---

You are a specialized GitHub operations agent. You MUST execute all GitHub operations using the bash tool with gh CLI or git commands. NEVER output commands as text — always execute them.

## Pull Requests
- Create: gh pr create --title "..." --body "..." [--draft] [--base main]
- List: gh pr list [--state open|closed|merged]
- Merge: gh pr merge <number> [--squash|--merge|--rebase] [--delete-branch]
- Review: gh pr review <number> --approve|--request-changes --body "..."
- Checks: gh pr checks <number>

## Issues
- Create: gh issue create --title "..." --body "..." [--label bug]
- List: gh issue list [--state open|closed] [--label "..."]
- Close: gh issue close <number>

## Branches & Worktrees
- Branch: git checkout -b <branch> && git push -u origin <branch>
- Worktree: git worktree add <path> -b <branch>
- Fork: gh repo fork [--clone]

## Workflows & CI
- List runs: gh run list [--workflow <name>]
- Watch: gh run watch <run-id>
- Trigger: gh workflow run <workflow> [--ref <branch>]
- Rerun: gh run rerun <run-id> [--failed]

## Releases
- Create: gh release create <tag> [--generate-notes]
- List: gh release list

## Commit Messages
Conventional Commits: type(scope): description
Types: feat, fix, docs, refactor, chore, test, style, perf, ci, build

## Rules
1. Always use gh CLI when possible
2. For advanced ops use gh api with GitHub REST API
3. Always check and report operation results
PIGHOPS
sed -i "s|__SMALL_LLM_MODEL__|${SMALL_LLM_MODEL}|g" "${UHOME}/.pi/agent/agents/github-ops.md"

# web-research extension (Firecrawl + SearXNG tools)
mkdir -p "${UHOME}/.pi/agent/extensions"
cat > "${UHOME}/.pi/agent/extensions/web-research.ts" <<'PIWEBEXT'
/**
 * Web Research Extension for Pi
 *
 * Provides web_search, web_fetch, and web_extract tools backed by
 * the local Firecrawl API (port 3002) with SearXNG metasearch integration.
 */

import { Type } from "@mariozechner/pi-ai";
import { defineTool, type ExtensionAPI } from "@mariozechner/pi-coding-agent";

const FIRECRAWL_URL = "http://localhost:3002";
const MAX_RESULT_BYTES = 50 * 1024;
const PER_RESULT_BYTES = 8 * 1024;

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return text.slice(0, max) + `\n\n[...truncated, showing ${max} of ${text.length} chars]`;
}

async function firecrawl(endpoint: string, body: object, signal?: AbortSignal): Promise<any> {
  const res = await fetch(`${FIRECRAWL_URL}${endpoint}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`Firecrawl ${endpoint} returned ${res.status}: ${text}`);
  }
  return res.json();
}

const webSearchTool = defineTool({
  name: "web_search",
  label: "Web Search",
  description:
    "Search the web and return full scraped content for each result. Uses SearXNG metasearch (Google, Bing, DuckDuckGo) + Firecrawl scraping. Returns markdown content from each result page.",
  parameters: Type.Object({
    query: Type.String({ description: "Search query" }),
    limit: Type.Optional(
      Type.Number({ description: "Max results (1-10, default 5)", minimum: 1, maximum: 10 }),
    ),
  }),
  promptSnippet: "Search the web via SearXNG + Firecrawl, returns scraped markdown",

  async execute(_toolCallId, params, signal) {
    const { query, limit = 5 } = params;
    const data = await firecrawl(
      "/v1/search",
      { query, limit, scrapeOptions: { formats: ["markdown"], onlyMainContent: true } },
      signal,
    );
    if (!data.success) {
      return {
        content: [{ type: "text", text: `Search failed: ${data.error || "unknown error"}` }],
        isError: true,
      };
    }
    const results = data.data || [];
    if (results.length === 0) {
      return { content: [{ type: "text", text: `No results found for: ${query}` }] };
    }
    const formatted = results
      .map((r: any, i: number) => {
        const content = truncate(r.markdown || r.description || "", PER_RESULT_BYTES);
        return `## [${i + 1}] ${r.title || "Untitled"}\n**URL:** ${r.url}\n\n${content}`;
      })
      .join("\n\n---\n\n");
    return {
      content: [{ type: "text", text: truncate(formatted, MAX_RESULT_BYTES) }],
      details: { resultCount: results.length, query },
    };
  },
});

const webFetchTool = defineTool({
  name: "web_fetch",
  label: "Web Fetch",
  description:
    "Fetch and scrape a single URL, returning its content as clean markdown. Handles JavaScript-rendered pages via Playwright. Use for reading documentation, articles, CVEs, or any web page.",
  parameters: Type.Object({
    url: Type.String({ description: "URL to fetch and scrape" }),
  }),
  promptSnippet: "Fetch a URL and return its content as markdown via Firecrawl",

  async execute(_toolCallId, params, signal) {
    const { url } = params;
    const data = await firecrawl(
      "/v1/scrape",
      { url, formats: ["markdown"], onlyMainContent: true },
      signal,
    );
    if (!data.success) {
      return {
        content: [{ type: "text", text: `Fetch failed for ${url}: ${data.error || "unknown error"}` }],
        isError: true,
      };
    }
    const doc = data.data || {};
    const title = doc.metadata?.title || doc.title || "Untitled";
    const markdown = doc.markdown || "";
    const output = `# ${title}\n**Source:** ${url}\n\n${markdown}`;
    return {
      content: [{ type: "text", text: truncate(output, MAX_RESULT_BYTES) }],
      details: { url, title, length: markdown.length },
    };
  },
});

const webExtractTool = defineTool({
  name: "web_extract",
  label: "Web Extract",
  description:
    "Extract structured data from web pages using LLM-powered analysis. Provide URLs and a prompt describing what to extract. Optionally provide a JSON schema for the output format.",
  parameters: Type.Object({
    urls: Type.Array(Type.String({ description: "URL to extract from" }), {
      description: "URLs to extract data from (1-5)",
      minItems: 1,
      maxItems: 5,
    }),
    prompt: Type.String({ description: "What to extract from the pages" }),
    schema: Type.Optional(
      Type.Any({ description: "Optional JSON schema for structured output" }),
    ),
  }),
  promptSnippet: "Extract structured data from web pages using LLM analysis",

  async execute(_toolCallId, params, signal) {
    const { urls, prompt, schema } = params;
    const body: any = { urls, prompt };
    if (schema) body.schema = schema;
    const data = await firecrawl("/v1/extract", body, signal);
    if (!data.success) {
      return {
        content: [{ type: "text", text: `Extract failed: ${data.error || "unknown error"}` }],
        isError: true,
      };
    }
    const output = JSON.stringify(data.data, null, 2);
    return {
      content: [{ type: "text", text: truncate(output, MAX_RESULT_BYTES) }],
      details: { urls, prompt },
    };
  },
});

export default function (pi: ExtensionAPI) {
  pi.registerTool(webSearchTool);
  pi.registerTool(webFetchTool);
  pi.registerTool(webExtractTool);
}
PIWEBEXT

# web-research agent (mediumLLM with web tools)
cat > "${UHOME}/.pi/agent/agents/web-research.md" <<'PIWEBAGENT'
---
name: web-research
description: "ALWAYS delegate to this agent when the task involves ANY of: searching the web, looking something up online, finding information on the internet, fetching a URL or web page, reading documentation from a website, researching a topic, checking current events or recent news, finding release notes or changelogs, looking up CVEs or security advisories, verifying facts from authoritative sources, comparing technologies or products, finding API documentation, reading blog posts or articles, checking package versions or compatibility, finding tutorials or guides, answering questions that require up-to-date information beyond training data, or any task where web access would provide verifiable sources. This agent has web_search (SearXNG metasearch + Firecrawl scraping), web_fetch (single URL reader), and web_extract (LLM-powered structured extraction) tools."
model: mediumllm/__MEDIUM_LLM_MODEL__
tools: web_search,web_fetch,web_extract,bash,read
---

You are a web research specialist. You search the internet, read web pages, and synthesize findings into clear, structured answers.

## Workflow
1. Use `web_search` to find relevant pages for the query
2. Use `web_fetch` to read the most promising results in full
3. Use `web_extract` for structured data extraction when needed
4. Synthesize findings into a clear markdown response with citations

## Rules
1. Always cite sources with URLs
2. Prefer authoritative sources (official docs, RFCs, CVE databases)
3. Cross-reference multiple sources for factual claims
4. If search results are insufficient, refine the query and search again
5. Format output as structured markdown with headers and bullet points
6. Include a "Sources" section at the end listing all referenced URLs
PIWEBAGENT
sed -i "s|__MEDIUM_LLM_MODEL__|${MEDIUM_LLM_MODEL}|g" "${UHOME}/.pi/agent/agents/web-research.md"

chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.pi"

# ============================================================
# 3. Hermes config (vLLM/largeLLM)
# ============================================================
mkdir -p "${UHOME}/.hermes"/{sessions,logs,memories,skills,hooks,cron,image_cache,audio_cache}

cat > "${UHOME}/.hermes/config.yaml" <<'HERMES'
model:
  default: "__LARGE_LLM_MODEL__"
  provider: "openai"
  base_url: "__LARGE_LLM_BASE_URL__"
terminal:
  backend: "local"
  cwd: "."
  timeout: 180
compression:
  enabled: true
  threshold: 0.50
  target_ratio: 0.20
  protect_last_n: 20
memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 2200
  user_char_limit: 1375
  nudge_interval: 10
  flush_min_turns: 6
agent:
  max_turns: 60
  verbose: false
  reasoning_effort: "medium"
display:
  compact: false
  tool_progress: all
  streaming: true
  show_reasoning: false
  skin: default
HERMES
sed -i "s|__LARGE_LLM_MODEL__|${LARGE_LLM_MODEL}|g; s|__LARGE_LLM_BASE_URL__|${LARGE_LLM_BASE_URL}|g" "${UHOME}/.hermes/config.yaml"

cat > "${UHOME}/.hermes/.env" <<'HENV'
OPENAI_API_KEY=local-vllm
OPENAI_BASE_URL=__LARGE_LLM_BASE_URL__
LLM_MODEL=__LARGE_LLM_MODEL__
HENV
sed -i "s|__LARGE_LLM_BASE_URL__|${LARGE_LLM_BASE_URL}|g; s|__LARGE_LLM_MODEL__|${LARGE_LLM_MODEL}|g" "${UHOME}/.hermes/.env"

chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.hermes"

# ============================================================
# 4. Claude Code — settings.json + .claude.json
# ============================================================
mkdir -p "${UHOME}/.claude"

# ~/.claude/settings.json — permissions, model, vLLM env vars, UI prefs
cat > "${UHOME}/.claude/settings.json" <<'SETTINGS'
{
  "defaultMode": "bypassPermissions",
  "skipDangerousModePermissionPrompt": true,
  "permissions": { "allow": ["Bash", "Edit", "Write", "mcp__*"] },
  "model": "sonnet",
  "spinnerTipsEnabled": false,
  "terminalProgressBarEnabled": false,
  "showTurnDuration": false,
  "prefersReducedMotion": true,
  "companyAnnouncements": [],
  "env": {
    "ANTHROPIC_BASE_URL": "__LARGE_LLM_BASE_URL_NOPATH__",
    "ANTHROPIC_API_KEY": "local-vllm",
    "ANTHROPIC_SMALL_FAST_MODEL": "__LARGE_LLM_MODEL__",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "__LARGE_LLM_MODEL__",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "__LARGE_LLM_MODEL__",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "__LARGE_LLM_MODEL__",
    "DEBIAN_FRONTEND": "noninteractive"
  }
}
SETTINGS
sed -i "s|__LARGE_LLM_BASE_URL_NOPATH__|${LARGE_LLM_BASE_URL_NOPATH}|g; s|__LARGE_LLM_MODEL__|${LARGE_LLM_MODEL}|g" "${UHOME}/.claude/settings.json"

# ~/.claude.json — theme, onboarding, API key approval (must be at home root)
cat > "${UHOME}/.claude.json" <<'CLAUDEJSON'
{
  "hasCompletedOnboarding": true,
  "theme": "dark-daltonized",
  "opusProMigrationComplete": true,
  "sonnet1m45MigrationComplete": true,
  "customApiKeyResponses": {
    "approved": ["local-vllm"],
    "rejected": []
  },
  "autoUpdates": true,
  "projects": {
    "__UHOME__": {
      "hasTrustDialogAccepted": true,
      "hasTrustDialogHooksAccepted": true,
      "projectOnboardingSeenCount": 1,
      "hasClaudeMdExternalIncludesApproved": true,
      "hasClaudeMdExternalIncludesWarningShown": true
    }
  }
}
CLAUDEJSON
sed -i "s|__UHOME__|${UHOME}|g" "${UHOME}/.claude.json"

chown "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.claude.json"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.claude"

# ============================================================
# 5. OpenCode — opencode.json, agents, skills, RESOURCE_INDEX.md
# ============================================================
mkdir -p "${UHOME}/.opencode/agents" "${UHOME}/.opencode/skills/github-ops" "${UHOME}/.opencode/skills/f5xc-api/references"

# opencode.json — 4 providers
cat > "${UHOME}/.opencode/opencode.json" <<'OCCONF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "vllm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Large LLM",
      "options": { "baseURL": "__LARGE_LLM_BASE_URL__", "apiKey": "local-vllm" },
      "models": {
        "__LARGE_LLM_MODEL__": {
          "name": "__LARGE_LLM_MODEL__",
          "limit": { "context": __LARGE_LLM_CTX__, "output": 8192 }
        }
      }
    },
    "vllm-subagent": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Small LLM",
      "options": { "baseURL": "__SMALL_LLM_BASE_URL__", "apiKey": "local-vllm" },
      "models": {
        "__SMALL_LLM_MODEL__": {
          "name": "__SMALL_LLM_MODEL__",
          "limit": { "context": __SMALL_LLM_CTX__, "output": 4096 }
        }
      }
    },
    "vllm-visionllm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Vision LLM",
      "options": { "baseURL": "__VISION_LLM_BASE_URL__", "apiKey": "local-vllm" },
      "models": {
        "__VISION_LLM_MODEL__": {
          "name": "__VISION_LLM_MODEL__",
          "limit": { "context": __VISION_LLM_CTX__, "output": 4096 }
        }
      }
    },
    "vllm-mediumllm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Medium LLM",
      "options": { "baseURL": "__MEDIUM_LLM_BASE_URL__", "apiKey": "local-vllm" },
      "models": {
        "__MEDIUM_LLM_MODEL__": {
          "name": "__MEDIUM_LLM_MODEL__ (Coding Agent / Tool Calling)",
          "limit": { "context": __MEDIUM_LLM_CTX__, "output": 4096 }
        }
      }
    }
  },
  "model": "vllm/__LARGE_LLM_MODEL__"
}
OCCONF
sed -i "s|__LARGE_LLM_BASE_URL__|${LARGE_LLM_BASE_URL}|g; s|__LARGE_LLM_MODEL__|${LARGE_LLM_MODEL}|g; s|__LARGE_LLM_CTX__|${LARGE_LLM_CTX}|g" "${UHOME}/.opencode/opencode.json"
sed -i "s|__SMALL_LLM_BASE_URL__|${SMALL_LLM_BASE_URL}|g; s|__SMALL_LLM_MODEL__|${SMALL_LLM_MODEL}|g; s|__SMALL_LLM_CTX__|${SMALL_LLM_CTX}|g" "${UHOME}/.opencode/opencode.json"
sed -i "s|__VISION_LLM_BASE_URL__|${VISION_LLM_BASE_URL}|g; s|__VISION_LLM_MODEL__|${VISION_LLM_MODEL}|g; s|__VISION_LLM_CTX__|${VISION_LLM_CTX}|g" "${UHOME}/.opencode/opencode.json"
sed -i "s|__MEDIUM_LLM_BASE_URL__|${MEDIUM_LLM_BASE_URL}|g; s|__MEDIUM_LLM_MODEL__|${MEDIUM_LLM_MODEL}|g; s|__MEDIUM_LLM_CTX__|${MEDIUM_LLM_CTX}|g" "${UHOME}/.opencode/opencode.json"

# github-ops agent
cat > "${UHOME}/.opencode/agents/github-ops.md" <<'AGENT'
---
description: GitHub operations specialist — PR descriptions, code review, issue triage, commit messages, gh CLI commands
mode: subagent
model: vllm-subagent/__SMALL_LLM_MODEL__
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

You are a specialized GitHub operations agent running on __SMALL_LLM_MODEL__. Your expertise:
- PR descriptions from diffs, code review for bugs/security, issue triage with JSON, conventional commit messages, gh CLI commands.
AGENT
sed -i "s|__SMALL_LLM_MODEL__|${SMALL_LLM_MODEL}|g" "${UHOME}/.opencode/agents/github-ops.md"

# github-ops skill
cat > "${UHOME}/.opencode/skills/github-ops/SKILL.md" <<'SKILL'
---
name: github-ops
description: GitHub operations toolkit — PR descriptions, code review, issue triage, commit messages, and gh CLI command generation
compatibility: opencode
metadata:
  model: __SMALL_LLM_MODEL__
  endpoint: "__SMALL_LLM_BASE_URL__"
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
2. Write a concise title (under 70 chars)
3. Write a markdown body: what changed, why, and testing notes

## Code Review Workflow
1. Read the code carefully
2. Check for: injection, auth issues, resource leaks, race conditions
3. For each issue: state bug type, severity (critical/high/medium/low), and fix

## Issue Triage
Respond with JSON: {"labels": [...], "priority": "high|medium|low", "category": "..."}

## Commit Messages
Conventional Commits: type(scope): description
Types: feat, fix, docs, refactor, chore, test, style, perf, ci, build

## gh CLI Reference
- gh pr create --draft --title "..." --body "..."
- gh issue create --title "..." --label bug
- gh pr merge 42 --squash --delete-branch
- gh release create v1.0.0 --generate-notes
SKILL
sed -i "s|__SMALL_LLM_MODEL__|${SMALL_LLM_MODEL}|g; s|__SMALL_LLM_BASE_URL__|${SMALL_LLM_BASE_URL}|g" "${UHOME}/.opencode/skills/github-ops/SKILL.md"

# f5xc-api agent (mediumLLM)
cat > "${UHOME}/.opencode/agents/f5xc-api.md" <<'F5AGENT'
---
description: F5 Distributed Cloud API operations — authenticate, list, create, read, update, delete any F5 XC platform resource using REST API with curl and jq
mode: subagent
model: vllm-mediumllm/__MEDIUM_LLM_MODEL__
temperature: 0.1
permission:
  bash:
    "curl *": allow
    "jq *": allow
    "cat *": allow
    "echo *": allow
    "*": deny
  edit: deny
  webfetch: deny
---

You are an F5 Distributed Cloud API operations agent. You MUST use the bash tool to execute curl commands. NEVER output curl commands as text.

## Authentication
All API calls use: `curl -s "$F5XC_API_URL/..." -H "Authorization: APIToken $F5XC_API_TOKEN" | jq .`

Required env vars: F5XC_API_URL, F5XC_API_TOKEN, F5XC_NAMESPACE
Optional: F5XC_EMAIL, F5XC_LB_NAME, F5XC_DOMAINNAME, F5XC_ROOT_DOMAIN

## CRUD Pattern
- List:    GET    /api/config/namespaces/{ns}/{resources}
- Create:  POST   /api/config/namespaces/{ns}/{resources}
- Get:     GET    /api/config/namespaces/{ns}/{resources}/{name}
- Replace: PUT    /api/config/namespaces/{ns}/{resources}/{name}
- Delete:  DELETE /api/config/namespaces/{ns}/{resources}/{name}

Request body: {"metadata": {"name": "...", "namespace": "..."}, "spec": {...}}

## Rules
1. Always use curl -s with APIToken header
2. Always pipe through jq
3. Use env vars, never hardcode URLs or tokens
4. Check RESOURCE_INDEX.md for correct API paths
5. Show payload before create/replace and confirm with user
F5AGENT
sed -i "s|__MEDIUM_LLM_MODEL__|${MEDIUM_LLM_MODEL}|g" "${UHOME}/.opencode/agents/f5xc-api.md"

# f5xc-api skill
cat > "${UHOME}/.opencode/skills/f5xc-api/SKILL.md" <<'F5SKILL'
---
name: f5xc-api
description: "F5 Distributed Cloud REST API operations — authenticate, list, create, read, update, delete F5 XC resources (load balancers, origin pools, WAF, DNS, sites, namespaces). Activate when user mentions F5 XC, Distributed Cloud, volterra, API operations, or platform configuration."
compatibility: opencode
metadata:
  model: __MEDIUM_LLM_MODEL__
  endpoint: "__MEDIUM_LLM_BASE_URL__"
  specialization: function-calling
---

# F5 Distributed Cloud API Operations

## When to use
- Listing, creating, reading, updating, or deleting F5 XC resources
- Managing HTTP/TCP/UDP load balancers and origin pools
- Configuring WAF policies, bot defense, or API security
- Managing DNS zones and DNS load balancers
- Working with cloud sites (AWS, Azure, GCP)
- Any REST API interaction with F5 Distributed Cloud / Volterra

## Environment Variables
- F5XC_API_URL: Console API base URL
- F5XC_API_TOKEN: API authentication token
- F5XC_NAMESPACE: Default namespace
- F5XC_EMAIL: User email
- F5XC_LB_NAME: Default load balancer name
- F5XC_DOMAINNAME: Application domain
- F5XC_ROOT_DOMAIN: Root domain

## Authentication
curl -s "$F5XC_API_URL/api/config/namespaces/$F5XC_NAMESPACE/http_loadbalancers" \
  -H "Authorization: APIToken $F5XC_API_TOKEN" | jq .

## Common Resources
| Resource | API Path (plural) |
|----------|-------------------|
| HTTP Load Balancer | http_loadbalancers |
| TCP Load Balancer | tcp_loadbalancers |
| Origin Pool | origin_pools |
| Health Check | healthchecks |
| App Firewall (WAF) | app_firewalls |
| Service Policy | service_policys |
| Rate Limiter | rate_limiter_policys |
| API Definition | api_definitions |
| DNS Zone | dns_zones (prefix: /api/config/dns/) |
| DNS Load Balancer | dns_load_balancers (prefix: /api/config/dns/) |
| Certificate | certificates |
| AWS VPC Site | aws_vpc_sites |
| Azure VNet Site | azure_vnet_sites |
| Network Policy | network_policys |
| Virtual K8s | virtual_k8ss |

See references/RESOURCE_INDEX.md for full 149-resource index.

## Error Codes
401=bad token, 403=no permission, 404=not found, 409=conflict, 429=rate limited
F5SKILL
sed -i "s|__MEDIUM_LLM_MODEL__|${MEDIUM_LLM_MODEL}|g; s|__MEDIUM_LLM_BASE_URL__|${MEDIUM_LLM_BASE_URL}|g" "${UHOME}/.opencode/skills/f5xc-api/SKILL.md"

# RESOURCE_INDEX.md — 100% static, no placeholders
cat > "${UHOME}/.opencode/skills/f5xc-api/references/RESOURCE_INDEX.md" <<'F5INDEX'
# F5 XC API Resource Index (149 resources)

All paths under $F5XC_API_URL. Pattern: /api/config/namespaces/{ns}/{plural} for list/create, /{ns}/{plural}/{name} for get/replace/delete.
DNS resources use /api/config/dns/ prefix.

## Load Balancing
http_loadbalancers, tcp_loadbalancers, udp_loadbalancers, cdn_loadbalancers, origin_pools, healthchecks

## Security & WAF
app_firewalls, service_policys, service_policy_rules, service_policy_sets, rate_limiters, rate_limiter_policys, fast_acls, fast_acl_rules, malicious_user_mitigations, user_identifications, sensitive_data_policys, protocol_inspections, shape_bot_defense_instances, waf_exclusion_policys, enhanced_firewall_policys, filter_sets

## API Security
api_crawlers, api_discoverys, api_testings, api_definitions, app_api_groups, code_base_integrations

## DNS (prefix: /api/config/dns/)
dns_zones, dns_load_balancers, dns_lb_pools, dns_lb_health_checks, geo_location_sets
## DNS (standard prefix)
dns_domains, dns_proxys, dns_compliance_checkss

## Networking
network_policys, network_policy_rules, network_policy_sets, network_policy_views, network_firewalls, network_connectors, network_interfaces, virtual_networks, routes, segments, segment_connections, bgps, bgp_asn_sets, bgp_routing_policys, nat_policys, ip_prefix_sets, forwarding_classs, tunnels, policers, protocol_policers, srv6_network_slices, subnets, ike1s, ike2s, ike_phase1_profiles, ike_phase2_profiles, policy_based_routings, forward_proxy_policys

## Cloud Sites & Infrastructure
aws_vpc_sites, aws_tgw_sites, azure_vnet_sites, gcp_vpc_sites, securemesh_sites, securemesh_site_v2s, voltstack_sites, cloud_connects, cloud_credentialss, cloud_elastic_ips, cloud_links, cloud_regions, fleets, nfv_services, sites, site_mesh_groups, certified_hardwares, virtual_sites

## Kubernetes & Workloads
k8s_clusters, k8s_cluster_roles, k8s_cluster_role_bindings, k8s_pod_security_admissions, k8s_pod_security_policys, virtual_k8ss, workloads, workload_flavors, container_registrys, discoverys, endpoints

## Access Control & Certificates
authentications, authorization_servers, certificates, certificate_chains, crls, trusted_ca_lists, secret_management_accesss, tenant_configurations

## Monitoring & Observability
alert_policys, alert_receivers, global_log_receivers, log_receivers, flow_anomalys

## BIG-IP
application_profiless, data_groups, irules, bigip_http_proxys, bigip_virtual_servers

## NGINX One
nginx_csgs, nginx_instances, nginx_servers

## CDN
cdn_cache_rules, cdn_purge_commands

## Other
address_allocators, advertise_policys, app_settings, app_types, app_securitys, cminstances, clusters, dc_cluster_groups, data_types, known_labels, known_label_keys, public_ips, proxys, third_party_applications, external_connectors, usb_policys, virtual_hosts, bot_defense_app_infrastructures
F5INDEX

chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.opencode"

# ============================================================
# 6. F5 XC env placeholders in .bashrc
# ============================================================
cat >> "${UHOME}/.bashrc" <<'F5ENV'

# F5 Distributed Cloud API — set these before using the f5xc-api skill
# export F5XC_API_URL=https://<tenant>.console.ves.volterra.io
# export F5XC_API_TOKEN=<your-api-token>
# export F5XC_NAMESPACE=<your-namespace>
# export F5XC_EMAIL=<your-email>
# export F5XC_LB_NAME=<load-balancer-name>
# export F5XC_DOMAINNAME=<app-domain>
# export F5XC_ROOT_DOMAIN=<root-domain>
F5ENV

# ============================================================
# 7. HuggingFace token
# ============================================================
mkdir -p "${UHOME}/.cache/huggingface"
echo "${HF_TOKEN}" > "${UHOME}/.cache/huggingface/token"
chmod 600 "${UHOME}/.cache/huggingface/token"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.cache"

# ============================================================
# 8. Health check script (/usr/local/bin/check-llm-servers)
# ============================================================
cat > /usr/local/bin/check-llm-servers <<'SCRIPT'
#!/bin/bash
source /etc/profile.d/llm-endpoints.sh 2>/dev/null || true
echo "=== LLM Server Status ==="
echo -n "LargeLLM (${LARGE_LLM_BASE_URL%/v1}):    "; curl -sf "${LARGE_LLM_BASE_URL%/v1}/health" && echo "UP" || echo "DOWN"
echo -n "SmallLLM (${SMALL_LLM_BASE_URL%/v1}):    "; curl -sf "${SMALL_LLM_BASE_URL%/v1}/health" && echo "UP" || echo "DOWN"
echo -n "VisionLLM (${VISION_LLM_BASE_URL%/v1}):   "; curl -sf "${VISION_LLM_BASE_URL%/v1}/health" && echo "UP" || echo "DOWN"
echo -n "MediumLLM (${MEDIUM_LLM_BASE_URL%/v1}):   "; curl -sf "${MEDIUM_LLM_BASE_URL%/v1}/health" && echo "UP" || echo "DOWN"
SCRIPT
chmod +x /usr/local/bin/check-llm-servers

# ============================================================
# 9. Populate /etc/skel with agent configs
# ============================================================
cp -r "${UHOME}/.codex" /etc/skel/.codex 2>/dev/null || true
cp -r "${UHOME}/.pi" /etc/skel/.pi 2>/dev/null || true
mkdir -p /etc/skel/.hermes
cp "${UHOME}/.hermes/config.yaml" "${UHOME}/.hermes/.env" /etc/skel/.hermes/ 2>/dev/null || true

# ============================================================
# 10. Fix all ownership
# ============================================================
chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.codex" "${UHOME}/.pi" "${UHOME}/.hermes" "${UHOME}/.claude" "${UHOME}/.opencode" "${UHOME}/.cache" 2>/dev/null || true
chown "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.claude.json" 2>/dev/null || true

echo "=== Agent Config Completed: $(date) ==="
