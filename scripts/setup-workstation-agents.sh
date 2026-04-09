#!/bin/bash
# AI agent configuration (Codex, Pi, Hermes, Claude Code, OpenCode).
# Downloaded and executed by cloud-init. Reads env vars from /etc/profile.d/llm-endpoints.sh.
set -euo pipefail
exec > >(tee -a /var/log/workstation-agents-setup.log) 2>&1
echo "=== Agent Config Started: $(date) ==="

# ---- Retry with exponential backoff (self-contained if not inherited) ----
if ! declare -f retry_cmd >/dev/null 2>&1; then
    retry_cmd() {
        local max=${1}; shift; local delay=${1}; shift; local attempt=1
        while true; do
            echo "  [attempt ${attempt}/${max}] ${*}"
            if "${@}"; then return 0; fi
            if (( attempt >= max )); then echo "  FAILED after ${max} attempts: ${*}" >&2; return 1; fi
            echo "  Retrying in ${delay}s..."; sleep "${delay}"; delay=$((delay * 2)); attempt=$((attempt + 1))
        done
    }
fi

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

# APPEND_SYSTEM.md — global rules appended to the main agent's system prompt
cat > "${UHOME}/.pi/agent/APPEND_SYSTEM.md" <<'PIAPPEND'
## CRITICAL: Research Before Answering

**ABSOLUTE RULE:** For any factual, technical, how-to, or product question — delegate to the web-research subagent FIRST. Never answer from memory alone.

Only skip web research for: pure coding tasks on local files, git operations, simple math.

Your answers MUST be grounded in verifiable sources. Always include a Sources section with URLs.

## Handling web-research results

The web-research subagent displays its answer directly to the user. It returns a status code — handle it as follows:

- **`SEARCH_COMPLETE`** — The answer has been displayed. Say NOTHING. Do not respond at all. The user already has everything they need.
- **`SEARCH_PARTIAL: <reason>`** — Results were incomplete. Briefly note the limitation and suggest how the user could refine their question.
- **`SEARCH_FAILED: <reason>`** — No useful results. Tell the user what was searched and ask a clarifying question to narrow the scope.

On SEARCH_COMPLETE, respond with only a single period (`.`) and nothing else. Never say "Here's what I found" or "The research is complete" or "Empty response" or explain that you are being silent.

## Query Enrichment — YOUR MOST IMPORTANT JOB

Before delegating to web-research, you MUST enrich the user's raw question into an optimized search query. The web-research agent feeds your query directly into traditional search engines (Google, DuckDuckGo, Bing via Firecrawl). Short or vague queries produce poor results. Your job is to craft the best possible search string.

### Step 1: Analyze the question

Determine the type:
- **Factual/definitional** ("What is X?") → needs exact product names, official terminology
- **How-to/procedural** ("How do I X?") → needs product + version + action keywords
- **Comparison** ("X vs Y") → needs both terms + evaluation criteria
- **Troubleshooting** ("X not working") → needs error context, product, version
- **Current events** ("latest X") → needs temporal focus

### Step 2: Extract context from conversation history

Look at the ENTIRE conversation for clues:
- Products/vendors mentioned earlier (F5, AWS, Azure, Kubernetes, etc.)
- Specific versions, environments, or configurations discussed
- The user's role and what they're trying to accomplish
- Prior search results that narrowed the topic

If the user says "how do I create a load balancer" and the conversation has been about F5 Distributed Cloud, the search MUST include "F5 Distributed Cloud" or "F5 XC".

### Step 3: Craft the enriched search query using operators

These operators work across Google, DuckDuckGo, Bing, and Firecrawl:

| Operator | Usage | Example |
|----------|-------|---------|
| `"phrase"` | Exact match | `"F5 Distributed Cloud" "HTTP load balancer"` |
| `-term` | Exclude noise | `-advertisement -pricing -"free trial"` |
| `site:` | Restrict to domain | `site:docs.cloud.f5.com` |
| `OR` | Synonym expansion | `"automatic certificate" OR "managed TLS" OR "Let's Encrypt"` |
| `intitle:` | Term in page title | `intitle:"load balancer" intitle:certificate` |
| `filetype:` | File type | `filetype:pdf "architecture guide"` |

**Enrichment rules:**
1. Always expand product names: "XC" → `"F5 Distributed Cloud" OR "F5 XC"`
2. Always add synonyms: "cert" → `certificate OR TLS OR SSL`
3. Exclude commercial noise: `-pricing -"free trial" -"sign up" -"contact sales"`
4. For vendor docs, use site restriction: `site:docs.cloud.f5.com` or `site:learn.microsoft.com`
5. For troubleshooting, include the error message in quotes
6. For current events, prepend the current year: `2026`

### Step 4: Format the delegation task

When calling the subagent tool, structure your task as:

```
SEARCH: <your enriched query with operators>
CONTEXT: <1-2 sentence summary of what the user needs and why>
```

The web-research agent will use your SEARCH line verbatim in Firecrawl.

### Examples

User: "how do I create a load balancer"
(Conversation context: discussing F5 XC configuration)
```
SEARCH: "F5 Distributed Cloud" "HTTP load balancer" create configure automatic certificate site:docs.cloud.f5.com OR site:community.f5.com -pricing -"free trial"
CONTEXT: User needs step-by-step instructions for creating an HTTP load balancer with automatic TLS certificates in F5 Distributed Cloud.
```

User: "what's new in kubernetes"
(No prior context)
```
SEARCH: Kubernetes 2026 "new features" OR "release notes" OR changelog -"getting started" -tutorial
CONTEXT: User wants recent Kubernetes releases and new features.
```

User: "certificate error"
(Conversation context: just configured an F5 XC HTTPS load balancer)
```
SEARCH: "F5 Distributed Cloud" HTTPS "load balancer" certificate error OR "certificate not issued" OR "pending" troubleshoot site:docs.cloud.f5.com OR site:community.f5.com OR site:my.f5.com
CONTEXT: User is troubleshooting a TLS certificate issue on an F5 XC HTTPS load balancer they just configured.
```

## F5 Distributed Cloud — Domain Context for Query Enrichment

You are the F5 Distributed Cloud Agentic Shell. Your users are F5 sales engineers, account managers, and solutions architects. Use the domain knowledge below to transform vague queries into precise, F5-specific search strings.

### Platform Taxonomy

When a user mentions any of these areas, expand to the official F5 XC product names:

| Category | Official Name | Key Objects | Search Terms |
|----------|--------------|-------------|--------------|
| Load balancing | Multi-Cloud App Connect | HTTP/TCP/UDP Load Balancer, Origin Pool, Health Check, Virtual Host | "HTTP load balancer" "origin pool" "health check" |
| WAF / app security | Web App & API Protection (WAAP) | App Firewall, Service Policy, WAF Exclusion Rules, Malicious User Mitigation | "App Firewall" OR "Web Application Firewall" "service policy" |
| Bot defense | Bot Defense | Shape Bot Defense, Bot Defense App Infrastructure, JavaScript Challenge | "bot defense" "JavaScript challenge" "credential stuffing" |
| DDoS protection | DDoS Mitigation | DDoS Protection, Fast ACL, Rate Limiter, Protocol Inspection | "DDoS" "rate limiter" "fast ACL" |
| API security | API Security | API Discovery, API Definition, API Protection Rules, API Crawler | "API discovery" "API definition" "API protection" |
| Networking | Multi-Cloud Network Connect | Network Connector, Network Policy, Virtual Network, BGP, Site Mesh Group, Segment | "network connector" "site mesh" "virtual network" BGP |
| DNS | DNS & DNS Load Balancing | DNS Zone, DNS Load Balancer, DNS LB Pool, Geo Location Set | "DNS zone" "DNS load balancer" "geo location" |
| Edge / sites | Customer & Regional Edge | Customer Edge (CE), Regional Edge (RE), Fleet, Voltstack Site, Securemesh Site | "customer edge" OR CE "regional edge" OR RE "fleet" |
| CDN | CDN | CDN Load Balancer, CDN Cache Rules, CDN Purge | "CDN" "cache rules" |
| Certificates | TLS/SSL Management | Automatic Certificate, Certificate Chain, Trusted CA List, CRL | "automatic certificate" "certificate chain" TLS SSL |
| Kubernetes | App Management | Virtual K8s, vK8s, Workload, Discovery, Container Registry | "virtual k8s" OR vK8s "workload" |
| Observability | Monitoring & Logging | Global Log Receiver, Alert Policy, Alert Receiver, Flow Anomaly | "log receiver" "alert policy" "observability" |
| BIG-IP integration | BIG-IP Next / Legacy | Application Profiles, Data Groups, iRules, Virtual Servers | "BIG-IP" "iRules" "application profile" |

### Terminology Quick-Reference

When users use shorthand, expand to official names:

| User says | F5 XC official term | Search expansion |
|-----------|-------------------|------------------|
| LB, load balancer | HTTP Load Balancer | "HTTP load balancer" OR "TCP load balancer" |
| origin, backend, upstream | Origin Pool | "origin pool" endpoint |
| WAF, firewall | App Firewall | "App Firewall" OR "web application firewall" |
| cert, TLS, SSL | Automatic Certificate | "automatic certificate" OR "managed TLS" |
| site, edge, CE | Customer Edge (CE) | "customer edge" OR CE site |
| RE, pop | Regional Edge (RE) | "regional edge" OR RE |
| namespace, ns | Namespace | namespace tenant isolation |
| three dots, ... menu | Actions menu | "manage configuration" |
| bot, scraping | Bot Defense | "bot defense" "JavaScript challenge" |
| API protection, API sec | API Security | "API discovery" "API definition" "API protection" |
| DDoS, volumetric | DDoS Mitigation | "DDoS" "rate limiter" "fast ACL" |
| service mesh, mesh | App Connect mesh | "service mesh" "site mesh group" |
| VIP | Virtual IP (on Load Balancer) | "virtual IP" "advertise" |
| iRule, iRules | iRules (BIG-IP) | "iRules" "BIG-IP" |
| XC, F5 XC, Volterra | F5 Distributed Cloud | "F5 Distributed Cloud" OR "F5 XC" |
| WAAP | Web App & API Protection | "WAAP" OR "web app and API protection" |
| MCN | Multi-Cloud Networking | "multi-cloud networking" OR "MCN" |

### Documentation & Knowledge Sites

Use these for `site:` operator enrichment based on query type:

| Site | Use when | Priority |
|------|----------|----------|
| `docs.cloud.f5.com` | Configuration how-tos, concepts, API reference, quick starts | Primary for all technical questions |
| `community.f5.com` | DevCentral articles, community solutions, best practices, demos | Primary for how-tos and examples |
| `my.f5.com` | Support KB articles, known issues, bug fixes, release notes | Primary for troubleshooting |
| `f5.com/solutions` | Solution briefs, use cases, industry solutions | For sales/positioning queries |
| `f5.com/case-studies` | Customer success stories, proof points | For ROI/value/reference queries |
| `f5.com/company/blog` | Product announcements, thought leadership | For "what's new" queries |
| `clouddocs.f5.com` | BIG-IP, BIG-IQ, legacy product docs | Only for BIG-IP questions |
| `github.com/f5devcentral` | Terraform modules, code examples, automation | For IaC/automation queries |
| `github.com/f5networks` | F5 open source projects | For code/integration queries |

### MEDDPICC Sales Framework

When queries touch sales methodology, deal qualification, or customer engagement, use this framework to enrich:

| Element | Meaning | F5-Specific Search Terms |
|---------|---------|------------------------|
| **M**etrics | Quantifiable success measures | ROI TCO "attack deflection" uptime SLA "mean time" compliance "cost savings" |
| **E**conomic Buyer | Budget authority | CISO "VP IT" CFO "security budget" "business case" "executive summary" |
| **D**ecision Criteria | Evaluation factors | "OWASP top 10" "multi-cloud" integration compliance "deployment options" "feature comparison" |
| **D**ecision Process | How they buy | POC POV "proof of concept" evaluation "vendor selection" RFP RFI |
| **P**aper Process | Procurement mechanics | contract SLA "security questionnaire" "data processing" SOC2 "PCI-DSS" HIPAA |
| **I**dentified Pain | Business problems | "multi-cloud sprawl" "API exposure" "DDoS risk" "tool consolidation" "visibility gap" "compliance gap" |
| **C**hampion | Internal advocate | "security architect" "senior engineer" "platform team" "DevSecOps" |
| **C**ompetition | Alternatives | Cloudflare Akamai Imperva "AWS WAF" "Azure WAF" "Google Cloud Armor" Fastly Radware |

For MEDDPICC queries, target: `site:f5.com/solutions OR site:f5.com/case-studies OR site:community.f5.com`

### Competitive Intelligence Enrichment

When the query involves comparisons or competitive positioning:

| Competitor | F5 advantage to highlight | Exclude noise |
|-----------|--------------------------|---------------|
| Cloudflare | Multi-cloud flexibility, hybrid/on-prem, advanced WAF rules, BIG-IP integration | -"sign up free" -"pricing page" |
| Akamai | Unified platform (not CDN-only), edge compute, Kubernetes-native | -"contact sales" |
| AWS WAF/Shield | Cross-cloud consistency, vendor-neutral, deeper app security | -"AWS free tier" |
| Azure Front Door/WAF | Multi-cloud (not Azure-locked), advanced bot defense, F5 ecosystem | -"Azure pricing" |
| Imperva | Integrated platform, multi-cloud networking + security, F5 support | -"request demo" |
| Google Cloud Armor | Hybrid/on-prem support, enterprise WAF maturity, global edge network | -"GCP pricing" |

For competitive queries, target: `site:gartner.com OR site:forrester.com OR site:peerspot.com OR site:g2.com` and always add `-"request demo" -"contact us" -"free trial" -"sign up"`

### Use Case Recognition — Route & Enrich

Detect the question type and apply the matching enrichment strategy:

| Question pattern | Type | Site targets | Extra operators |
|-----------------|------|-------------|-----------------|
| "How do I configure/create/set up X" | Configuration | `site:docs.cloud.f5.com` | + product terms from taxonomy |
| "X not working / error / failed" | Troubleshooting | `site:my.f5.com OR site:community.f5.com` | + error message in quotes |
| "F5 vs X" / "compare" / "alternative" | Competitive | `site:peerspot.com OR site:gartner.com` | + `-"request demo"` |
| "demo" / "POC" / "show" / "present" | Demo/POC | `site:community.f5.com OR site:github.com/f5devcentral` | + Terraform automation |
| "metrics" / "ROI" / "business case" / "CISO" | Sales/MEDDPICC | `site:f5.com/solutions OR site:f5.com/case-studies` | + MEDDPICC terms |
| "customer story" / "who uses" / "reference" | Proof points | `site:f5.com/case-studies` | + industry vertical |
| "what's new" / "release" / "announcement" | Current events | `site:f5.com/company/blog OR site:community.f5.com` | + current year (2026) |
| "Terraform" / "automate" / "IaC" / "API" | Automation | `site:github.com/f5devcentral OR site:docs.cloud.f5.com` | + "terraform" OR "API" |
| "pricing" / "license" / "cost" | Commercial | N/A — not publicly available | Suggest checking F5 partner portal or account team |

### Default Enrichment — Always Apply

For ANY query that touches F5 products, always:
1. Expand abbreviations using the terminology table above
2. Add `"F5 Distributed Cloud"` or `"F5 XC"` if not already present
3. Exclude commercial noise: `-pricing -"free trial" -"sign up" -"contact sales"` (unless the query IS about pricing)
4. Prefer `site:docs.cloud.f5.com` for technical queries
5. Include conversation context — if the user has been discussing WAF configuration, a follow-up "how do I test it" means WAF testing, not general testing

## Structured Data Extraction

For extracting specific structured data from a web page (prices, specs, tables), call Firecrawl extract directly:

```bash
curl -s http://localhost:3002/v1/extract -X POST -H "Content-Type: application/json" \
  -d '{"urls":["URL"],"prompt":"What to extract","schema":{"type":"object","properties":{"field":{"type":"string"}}}}' | jq .
```
PIAPPEND

# settings.json
cat > "${UHOME}/.pi/agent/settings.json" <<'PICONF'
{
  "defaultProvider": "openai",
  "defaultModel": "__LARGE_LLM_MODEL__",
  "quietStartup": true,
  "collapseChangelog": true,
  "defaultThinkingLevel": "high",
  "hideThinkingBlock": true,
  "packages": ["npm:@mjakl/pi-subagent"]
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
          "maxTokens": 8192,
          "compat": {
            "supportsDeveloperRole": false,
            "supportsReasoningEffort": false,
            "thinkingFormat": "qwen-chat-template"
          }
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
          "maxTokens": 4096,
          "compat": {
            "supportsDeveloperRole": false,
            "supportsReasoningEffort": true,
            "reasoningEffortMap": {
              "minimal": "none",
              "low": "none",
              "medium": "high",
              "high": "high",
              "xhigh": "high"
            }
          }
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
          "maxTokens": 4096,
          "compat": {
            "supportsDeveloperRole": false,
            "supportsReasoningEffort": false
          }
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
thinking: high
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
thinking: off
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

# web-research agent (largeLLM — full ANALYST, produces user-facing answers directly)
# Subagent's context is ephemeral — use maximum quality thinking for synthesis.
# The executeSingle patch returns only "Research task completed" to the main agent's
# context, while renderSingleCollapsed displays the full answer in the TUI.
cat > "${UHOME}/.pi/agent/agents/web-research.md" <<'PIWEBAGENT'
---
name: web-research
description: "ALWAYS delegate to this agent when the task involves ANY of: searching the web, looking something up online, finding information on the internet, fetching a URL or web page, reading documentation from a website, researching a topic, checking current events or recent news, finding release notes or changelogs, looking up CVEs or security advisories, verifying facts from authoritative sources, comparing technologies or products, finding API documentation, reading blog posts or articles, checking package versions or compatibility, finding tutorials or guides, answering questions that require up-to-date information beyond training data, or any task where web access would provide verifiable sources."
model: openai/__LARGE_LLM_MODEL__
tools: bash,read
thinking: high
---

You are a web research ANALYST for F5 Distributed Cloud sales engineering. You search the web, read the results, and produce a COMPLETE, HIGH-QUALITY answer that will be displayed directly to the user. The main agent does NOT reprocess your output — what you write IS the final answer the user sees.

## How to read the task

The main agent sends you a task in this format:
```
SEARCH: <enriched query with search operators>
CONTEXT: <what the user needs>
```

Use the SEARCH line as your Firecrawl query. If no SEARCH line is present, use the full task text.

## API Endpoints (Firecrawl on localhost:3002)

**Search** (your primary tool):
```
curl -s http://localhost:3002/v1/search -X POST -H "Content-Type: application/json" -d '{"query":"YOUR QUERY","limit":5,"scrapeOptions":{"formats":["markdown"],"onlyMainContent":true}}' | jq '.data[:4] | .[] | {title, url, markdown: .markdown[:2500]}'
```

**Fetch a specific URL** (if you need more detail from a promising result):
```
curl -s http://localhost:3002/v1/scrape -X POST -H "Content-Type: application/json" -d '{"url":"URL","formats":["markdown"],"onlyMainContent":true}' | jq '{title: .data.metadata.title, markdown: .data.markdown[:3000]}'
```

## Your Output IS the Final Answer

Write a complete, well-formatted answer:
- Use markdown headers, bullet points, and tables for clarity
- Be concise but thorough — cover the key steps or facts
- Include a **Sources:** section at the end with clickable URLs
- For how-to questions: number the steps clearly
- For conceptual questions: explain with concrete examples
- For comparisons: use a summary table

## Rules

1. **Maximum 5 tool calls.** Search once or twice, optionally fetch 1-2 pages, then write your answer.
2. **Truncate with jq.** Always use jq to limit markdown to 2500 chars per result.
3. **Your output IS the user-facing answer.** Write it as if speaking directly to the user.
4. **Always cite sources.** End with a Sources section listing URLs you used.
PIWEBAGENT
sed -i "s|__LARGE_LLM_MODEL__|${LARGE_LLM_MODEL}|g" "${UHOME}/.pi/agent/agents/web-research.md"

# ---- Ensure pi-subagent and pi are installed before patching ----
if ! command -v pi >/dev/null 2>&1; then
    echo "Pi not found, installing @mariozechner/pi-coding-agent..."
    retry_cmd 3 15 npm install -g "@mariozechner/pi-coding-agent"
fi
if ! find /usr/lib/node_modules/@mjakl/pi-subagent -name "index.ts" -print -quit 2>/dev/null | grep -q .; then
    echo "pi-subagent not found, installing..."
    retry_cmd 3 15 npm install -g "@mjakl/pi-subagent"
fi

# Suppress noisy "Found N subagent(s)" startup notification from pi-subagent
PI_SUBAGENT_INDEX=$(find /usr/lib/node_modules/@mjakl/pi-subagent -name "index.ts" -print -quit 2>/dev/null)
if [ -n "${PI_SUBAGENT_INDEX}" ]; then
    python3 -c "
p = '${PI_SUBAGENT_INDEX}'
with open(p) as f: c = f.read()
old = '''      ctx.ui.notify(
        \x60Found \x24{discoveredAgents.length} subagent(s):\\\\n\x24{list}\x60,
        \"info\",
      );'''
if old in c:
    c = c.replace(old, '      // subagent discovery notification suppressed')
    with open(p, 'w') as f: f.write(c)
    print('Patched pi-subagent startup notification')
else:
    print('pi-subagent already patched or pattern changed')
" 2>/dev/null || true
fi

# Patch pi-subagent executeSingle — return minimal text to main LLM context
# The subagent's full answer is displayed via TUI renderSingleCollapsed (below)
# but the main agent only sees "Research task completed" — preserving context window
if [ -n "${PI_SUBAGENT_INDEX}" ]; then
    python3 -c "
p = '${PI_SUBAGENT_INDEX}'
with open(p) as f:
    c = f.read()
old = '      text: getResultSummaryText(result),'
new = '      text: getResultSummaryText(result).trim().length > 50 ? \"SEARCH_COMPLETE\" : \"SEARCH_PARTIAL: \" + (getResultSummaryText(result).trim() || \"no output\"),'
if old in c:
    c = c.replace(old, new, 1)
    with open(p, 'w') as f:
        f.write(c)
    print('Patched executeSingle: minimal LLM context return')
else:
    print('executeSingle already patched or pattern changed')
" 2>/dev/null || true
fi

# Patch pi-subagent render.ts — display full subagent answer in TUI collapsed view
# Combined with the executeSingle patch above, this creates the architecture:
#   subagent (large LLM, thinking:high) → searches + synthesizes complete answer
#   TUI renderSingleCollapsed → displays answer as rendered Markdown to user
#   main LLM context → sees only "Research task completed" (~20 tokens)
#   subagent context is ephemeral → discarded after task, no context rot
PI_SUBAGENT_RENDER=$(find /usr/lib/node_modules/@mjakl/pi-subagent -name "render.ts" -print -quit 2>/dev/null)
if [ -n "${PI_SUBAGENT_RENDER}" ]; then
    python3 -c "
import re, sys

p = '${PI_SUBAGENT_RENDER}'
with open(p) as f:
    c = f.read()

patched = False

# --- Patch renderSingleCollapsed: show full answer as Markdown in TUI ---
# This displays the subagent's synthesized answer directly to the user
# while executeSingle only returns a minimal "completed" string to the main LLM
old_single = re.compile(
    r'function renderSingleCollapsed\([\s\S]*?\): (?:Container \| )?Text \{[\s\S]*?\n\treturn new Text\(text, 0, 0\);\n\}',
)
new_single = '''function renderSingleCollapsed(
\tr: SingleResult,
\tdelegationMode: DelegationMode,
\ticon: string,
\terror: boolean,
\tdisplayItems: DisplayItem[],
\ttheme: { fg: ThemeFg; bold: (s: string) => string },
): Container | Text {
\tconst finalOutput = getFinalOutput(r.messages);
\tif (error) {
\t\tlet text = \x60\x24{icon} \x24{theme.fg(\"toolTitle\", theme.bold(r.agent))}\x60;
\t\tif (r.stopReason) text += \x60 \x24{theme.fg(\"error\", \x60[\x24{r.stopReason}]\x60)}\x60;
\t\tif (r.errorMessage) text += \x60\\n\x24{theme.fg(\"error\", \x60Error: \x24{r.errorMessage}\x60)}\x60;
\t\treturn new Text(text, 0, 0);
\t}
\tif (finalOutput) {
\t\tconst mdTheme = getMarkdownTheme();
\t\tconst container = new Container();
\t\tcontainer.addChild(new Text(\x60\x24{icon} \x24{theme.fg(\"toolTitle\", theme.bold(r.agent))}\x60, 0, 0));
\t\tcontainer.addChild(new Spacer(1));
\t\tcontainer.addChild(new Markdown(finalOutput.trim(), 0, 0, mdTheme));
\t\treturn container;
\t}
\tconst text = \x60\x24{icon} \x24{theme.fg(\"toolTitle\", theme.bold(r.agent))}\x60;
\treturn new Text(text, 0, 0);
}'''
if old_single.search(c):
    c = old_single.sub(new_single, c, count=1)
    patched = True
    print('Patched renderSingleCollapsed -> minimal')

# --- Patch renderParallelCollapsed: one-line status + per-agent icons ---
old_parallel = re.compile(
    r'function renderParallelCollapsed\([\s\S]*?\): Text \{[\s\S]*?\n\treturn new Text\(text, 0, 0\);\n\}',
)
new_parallel = '''function renderParallelCollapsed(
\tdetails: SubagentDetails,
\tdelegationMode: DelegationMode,
\ticon: string,
\tstatus: string,
\tisRunning: boolean,
\texpanded: boolean,
\ttheme: { fg: ThemeFg; bold: (s: string) => string },
): Text {
\tlet text = \x60\x24{icon} \x24{theme.fg(\"toolTitle\", theme.bold(\"parallel \"))}\x24{theme.fg(\"accent\", status)}\x60;
\tfor (const r of details.results) {
\t\tconst rIcon = statusIcon(r, theme);
\t\ttext += \x60  \x24{theme.fg(\"accent\", r.agent)} \x24{rIcon}\x60;
\t}
\treturn new Text(text, 0, 0);
}'''
if old_parallel.search(c):
    c = old_parallel.sub(new_parallel, c, count=1)
    patched = True
    print('Patched renderParallelCollapsed -> minimal')

# --- Patch renderCall: agent name only, no mode badge or task preview ---
old_call = re.compile(
    r'export function renderCall\([\s\S]*?\): Text \{[\s\S]*?\n\treturn new Text\(text, 0, 0\);\n\}',
)
new_call = '''export function renderCall(args: Record<string, any>, theme: { fg: ThemeFg; bold: (s: string) => string }): Text {
\tif (args.tasks && args.tasks.length > 0) {
\t\tconst names = args.tasks.map((t: any) => t.agent).join(\", \");
\t\treturn new Text(theme.fg(\"toolTitle\", theme.bold(\"subagent \")) + theme.fg(\"accent\", names), 0, 0);
\t}
\tconst agentName = args.agent || \"...\";
\treturn new Text(theme.fg(\"toolTitle\", theme.bold(\"subagent \")) + theme.fg(\"accent\", agentName), 0, 0);
}'''
if old_call.search(c):
    c = old_call.sub(new_call, c, count=1)
    patched = True
    print('Patched renderCall -> minimal')

if patched:
    with open(p, 'w') as f:
        f.write(c)
    print('render.ts patched for minimal subagent output')
else:
    print('render.ts already patched or function signatures changed')
" 2>/dev/null || true
fi

# Output sanitizer extension — deterministically strips LaTeX from all LLM output
mkdir -p "${UHOME}/.pi/agent/extensions"
cat > "${UHOME}/.pi/agent/extensions/output-sanitizer.ts" <<'PISANITIZER'
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

// Known LaTeX → Unicode mappings (checked first for clean output)
const KNOWN: Record<string, string> = {
  "\\rightarrow": "→", "\\leftarrow": "←", "\\leftrightarrow": "↔",
  "\\uparrow": "↑", "\\downarrow": "↓", "\\to": "→", "\\gets": "←",
  "\\Rightarrow": "⇒", "\\Leftarrow": "⇐", "\\Leftrightarrow": "⇔",
  "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ",
  "\\theta": "θ", "\\lambda": "λ", "\\pi": "π", "\\sigma": "σ",
  "\\omega": "ω", "\\mu": "μ", "\\epsilon": "ε", "\\phi": "φ",
  "\\geq": "≥", "\\leq": "≤", "\\neq": "≠", "\\approx": "≈",
  "\\pm": "±", "\\times": "×", "\\div": "÷", "\\cdot": "·",
  "\\infty": "∞", "\\in": "∈", "\\sum": "∑", "\\prod": "∏",
  "\\vdots": "…", "\\cdots": "⋯", "\\ldots": "…", "\\dots": "…",
  "\\checkmark": "✓", "\\star": "★", "\\bullet": "•", "\\dag": "†",
};

function sanitize(text: string): string {
  let r = text;
  // Pass 1: replace known $\command$ patterns with Unicode
  for (const [cmd, uni] of Object.entries(KNOWN)) {
    // Escape the backslash for regex: \\alpha -> \\\\alpha
    const escaped = cmd.replace(/\\/g, "\\\\");
    r = r.replace(new RegExp("\\$" + escaped + "\\$", "g"), uni);
  }
  // Pass 2: catch-all — strip any remaining $\command$ that we missed
  // Matches $\anycommand$ and removes the $ delimiters and backslash
  r = r.replace(/\$\\([a-zA-Z]+)\$/g, (_, cmd) => cmd);
  return r;
}

export default function (pi: ExtensionAPI) {
  pi.on("message_end", (event) => {
    const msg = event.message as any;
    if (msg.role !== "assistant" || !Array.isArray(msg.content)) return;
    for (const block of msg.content) {
      if (block.type === "text" && typeof block.text === "string")
        block.text = sanitize(block.text);
    }
  });
}
PISANITIZER

chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.pi"

# ============================================================
# 2b. Oh-My-Pi (omp) config — fork of Pi with enhanced features
# ============================================================
# Binary is pre-installed in devcontainer image via @oh-my-pi/pi-coding-agent
# Config dir: ~/.omp/agent/ (separate from ~/.pi/)
mkdir -p "${UHOME}/.omp/agent/agents"

# config.yml — omp uses YAML, auto-migrates from JSON
cat > "${UHOME}/.omp/agent/config.yml" <<OMPCONF
defaultProvider: openai
defaultModel: __LARGE_LLM_MODEL__
defaultThinkingLevel: high
hideThinkingBlock: true
quietStartup: true
collapseChangelog: true
enabledModels:
  - __LARGE_LLM_MODEL__
  - __MEDIUM_LLM_MODEL__
  - __SMALL_LLM_MODEL__
disabledProviders:
  - anthropic
  - google
  - groq
  - mistral
  - bedrock
  - huggingface
  - cerebras
  - kimi
  - cloudflare
  - cursor
web_search:
  enabled: false
providers:
  webSearch: synthetic
exa:
  enabled: false
  enableSearch: false
OMPCONF
sed -i "s|__LARGE_LLM_MODEL__|${LARGE_LLM_MODEL}|g; s|__MEDIUM_LLM_MODEL__|${MEDIUM_LLM_MODEL}|g; s|__SMALL_LLM_MODEL__|${SMALL_LLM_MODEL}|g" "${UHOME}/.omp/agent/config.yml"

# models.yml — same 3-provider setup as Pi
cat > "${UHOME}/.omp/agent/models.yml" <<OMPMODELS
providers:
  openai:
    baseUrl: __LARGE_LLM_BASE_URL__
    apiKey: local-vllm
    models:
      - id: __LARGE_LLM_MODEL__
        name: Large LLM (vLLM)
        api: openai-completions
        reasoning: true
        contextWindow: __LARGE_LLM_CTX__
        maxTokens: 8192
        compat:
          supportsDeveloperRole: false
          supportsReasoningEffort: false
          thinkingFormat: qwen-chat-template
  mediumllm:
    baseUrl: __MEDIUM_LLM_BASE_URL__
    apiKey: local-vllm
    models:
      - id: __MEDIUM_LLM_MODEL__
        name: Medium LLM (vLLM)
        api: openai-completions
        reasoning: true
        contextWindow: __MEDIUM_LLM_CTX__
        maxTokens: 4096
        compat:
          supportsDeveloperRole: false
          supportsReasoningEffort: true
          reasoningEffortMap:
            minimal: none
            low: none
            medium: high
            high: high
            xhigh: high
  smallllm:
    baseUrl: __SMALL_LLM_BASE_URL__
    apiKey: local-vllm
    models:
      - id: __SMALL_LLM_MODEL__
        name: Small LLM (vLLM)
        api: openai-completions
        reasoning: false
        contextWindow: __SMALL_LLM_CTX__
        maxTokens: 4096
        compat:
          supportsDeveloperRole: false
          supportsReasoningEffort: false
OMPMODELS
sed -i "s|__LARGE_LLM_BASE_URL__|${LARGE_LLM_BASE_URL}|g; s|__LARGE_LLM_MODEL__|${LARGE_LLM_MODEL}|g; s|__LARGE_LLM_CTX__|${LARGE_LLM_CTX}|g" "${UHOME}/.omp/agent/models.yml"
sed -i "s|__MEDIUM_LLM_BASE_URL__|${MEDIUM_LLM_BASE_URL}|g; s|__MEDIUM_LLM_MODEL__|${MEDIUM_LLM_MODEL}|g; s|__MEDIUM_LLM_CTX__|${MEDIUM_LLM_CTX}|g" "${UHOME}/.omp/agent/models.yml"
sed -i "s|__SMALL_LLM_BASE_URL__|${SMALL_LLM_BASE_URL}|g; s|__SMALL_LLM_MODEL__|${SMALL_LLM_MODEL}|g; s|__SMALL_LLM_CTX__|${SMALL_LLM_CTX}|g" "${UHOME}/.omp/agent/models.yml"

# Reuse Pi's output-sanitizer extension (LaTeX → Unicode)
mkdir -p "${UHOME}/.omp/agent/extensions"
cp "${UHOME}/.pi/agent/extensions/output-sanitizer.ts" "${UHOME}/.omp/agent/extensions/output-sanitizer.ts" 2>/dev/null || true

# Reuse Pi's APPEND_SYSTEM.md (F5 domain context + query enrichment)
# Then append omp-specific Firecrawl search instructions (omp's built-in web_search is disabled)
cp "${UHOME}/.pi/agent/APPEND_SYSTEM.md" "${UHOME}/.omp/agent/APPEND_SYSTEM.md" 2>/dev/null || true
cat >> "${UHOME}/.omp/agent/APPEND_SYSTEM.md" <<'OMPWEB'

## Web Search via Bash (omp-specific)

The built-in web_search tool is disabled. Use bash with curl to search via our local Firecrawl:

**Search:**
```bash
curl -s http://localhost:3002/v1/search -X POST -H "Content-Type: application/json" \
  -d '{"query":"YOUR QUERY","limit":5,"scrapeOptions":{"formats":["markdown"],"onlyMainContent":true}}' \
  | jq '.data[:4] | .[] | {title, url, markdown: .markdown[:2500]}'
```

**Fetch a URL:**
```bash
curl -s http://localhost:3002/v1/scrape -X POST -H "Content-Type: application/json" \
  -d '{"url":"URL","formats":["markdown"],"onlyMainContent":true}' \
  | jq '{title: .data.metadata.title, markdown: .data.markdown[:3000]}'
```

Always research before answering factual questions. Always cite sources with URLs.
OMPWEB

chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.omp"

# ============================================================
# 2c. XCSH — F5-branded fork of oh-my-pi (identical config format)
# ============================================================
# Binary: xcsh (pre-built from GitHub releases)
# Config dir: ~/.xcsh/agent/ (separate from ~/.omp/ and ~/.pi/)

# Install xcsh binary from GitHub releases
if ! command -v xcsh >/dev/null 2>&1; then
    echo "Installing xcsh..."
    XCSH_VER=$(curl -sf "https://api.github.com/repos/f5xc-salesdemos/xcsh/releases/latest" | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null || echo "v14.0.3")
    XCSH_BASE="https://github.com/f5xc-salesdemos/xcsh/releases/download/${XCSH_VER}"
    retry_cmd 3 10 curl -fsSL --max-time 300 "${XCSH_BASE}/xcsh-linux-x64" -o /usr/local/bin/xcsh
    chmod +x /usr/local/bin/xcsh
    retry_cmd 3 10 curl -fsSL --max-time 300 "${XCSH_BASE}/pi_natives.linux-x64-modern.node" -o /usr/local/bin/pi_natives.linux-x64-modern.node
    echo "xcsh installed: $(xcsh --version 2>/dev/null || echo 'unknown')"
fi

mkdir -p "${UHOME}/.xcsh/agent/agents" "${UHOME}/.xcsh/agent/extensions"

# config.yml — identical to omp config
cat > "${UHOME}/.xcsh/agent/config.yml" <<XCSHCONF
defaultProvider: openai
defaultModel: __LARGE_LLM_MODEL__
defaultThinkingLevel: high
hideThinkingBlock: true
quietStartup: true
collapseChangelog: true
enabledModels:
  - __LARGE_LLM_MODEL__
  - __MEDIUM_LLM_MODEL__
  - __SMALL_LLM_MODEL__
disabledProviders:
  - anthropic
  - google
  - groq
  - mistral
  - bedrock
  - huggingface
  - cerebras
  - kimi
  - cloudflare
  - cursor
web_search:
  enabled: false
providers:
  webSearch: synthetic
exa:
  enabled: false
  enableSearch: false
XCSHCONF
sed -i "s|__LARGE_LLM_MODEL__|${LARGE_LLM_MODEL}|g; s|__MEDIUM_LLM_MODEL__|${MEDIUM_LLM_MODEL}|g; s|__SMALL_LLM_MODEL__|${SMALL_LLM_MODEL}|g" "${UHOME}/.xcsh/agent/config.yml"

# models.yml — render directly (don't depend on omp being installed first)
cat > "${UHOME}/.xcsh/agent/models.yml" <<XCSHMODELS
providers:
  openai:
    baseUrl: __LARGE_LLM_BASE_URL__
    apiKey: local-vllm
    models:
      - id: __LARGE_LLM_MODEL__
        name: Large LLM (vLLM)
        api: openai-completions
        reasoning: true
        contextWindow: __LARGE_LLM_CTX__
        maxTokens: 8192
        compat:
          supportsDeveloperRole: false
          supportsReasoningEffort: false
          thinkingFormat: qwen-chat-template
  mediumllm:
    baseUrl: __MEDIUM_LLM_BASE_URL__
    apiKey: local-vllm
    models:
      - id: __MEDIUM_LLM_MODEL__
        name: Medium LLM (vLLM)
        api: openai-completions
        reasoning: true
        contextWindow: __MEDIUM_LLM_CTX__
        maxTokens: 4096
        compat:
          supportsDeveloperRole: false
          supportsReasoningEffort: true
          reasoningEffortMap:
            minimal: none
            low: none
            medium: high
            high: high
            xhigh: high
  smallllm:
    baseUrl: __SMALL_LLM_BASE_URL__
    apiKey: local-vllm
    models:
      - id: __SMALL_LLM_MODEL__
        name: Small LLM (vLLM)
        api: openai-completions
        reasoning: false
        contextWindow: __SMALL_LLM_CTX__
        maxTokens: 4096
        compat:
          supportsDeveloperRole: false
          supportsReasoningEffort: false
XCSHMODELS
sed -i "s|__LARGE_LLM_BASE_URL__|${LARGE_LLM_BASE_URL}|g; s|__LARGE_LLM_MODEL__|${LARGE_LLM_MODEL}|g; s|__LARGE_LLM_CTX__|${LARGE_LLM_CTX}|g" "${UHOME}/.xcsh/agent/models.yml"
sed -i "s|__MEDIUM_LLM_BASE_URL__|${MEDIUM_LLM_BASE_URL}|g; s|__MEDIUM_LLM_MODEL__|${MEDIUM_LLM_MODEL}|g; s|__MEDIUM_LLM_CTX__|${MEDIUM_LLM_CTX}|g" "${UHOME}/.xcsh/agent/models.yml"
sed -i "s|__SMALL_LLM_BASE_URL__|${SMALL_LLM_BASE_URL}|g; s|__SMALL_LLM_MODEL__|${SMALL_LLM_MODEL}|g; s|__SMALL_LLM_CTX__|${SMALL_LLM_CTX}|g" "${UHOME}/.xcsh/agent/models.yml"

# APPEND_SYSTEM.md — render from Pi's copy (Pi is always installed first)
cp "${UHOME}/.pi/agent/APPEND_SYSTEM.md" "${UHOME}/.xcsh/agent/APPEND_SYSTEM.md" 2>/dev/null || true
# Append Firecrawl search instructions for xcsh (same as omp)
cat >> "${UHOME}/.xcsh/agent/APPEND_SYSTEM.md" <<'XCSHWEB'

## Web Search via Bash (xcsh-specific)

The built-in web_search tool is disabled. Use bash with curl to search via our local Firecrawl:

**Search:**
```bash
curl -s http://localhost:3002/v1/search -X POST -H "Content-Type: application/json" \
  -d '{"query":"YOUR QUERY","limit":5,"scrapeOptions":{"formats":["markdown"],"onlyMainContent":true}}' \
  | jq '.data[:4] | .[] | {title, url, markdown: .markdown[:2500]}'
```

**Fetch a URL:**
```bash
curl -s http://localhost:3002/v1/scrape -X POST -H "Content-Type: application/json" \
  -d '{"url":"URL","formats":["markdown"],"onlyMainContent":true}' \
  | jq '{title: .data.metadata.title, markdown: .data.markdown[:3000]}'
```

Always research before answering factual questions. Always cite sources with URLs.
XCSHWEB

# Reuse Pi's output-sanitizer extension (LaTeX → Unicode)
cp "${UHOME}/.pi/agent/extensions/output-sanitizer.ts" "${UHOME}/.xcsh/agent/extensions/output-sanitizer.ts" 2>/dev/null || true

chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.xcsh"

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
# 3b. Claude Code Proxy — Anthropic→OpenAI converter with Firecrawl web search
# ============================================================
# Intercepts web_search/web_fetch tool calls and executes them via local Firecrawl
if [ ! -d /opt/claude-code-proxy ]; then
    retry_cmd 3 10 git clone --depth=1 https://github.com/f5xc-salesdemos/claude-code-proxy.git /opt/claude-code-proxy
fi
cd /opt/claude-code-proxy
git pull 2>/dev/null || true

if [ ! -d /opt/claude-code-proxy/venv ]; then
    python3 -m venv /opt/claude-code-proxy/venv
fi
/opt/claude-code-proxy/venv/bin/pip install -q -U pip 2>/dev/null
retry_cmd 3 10 /opt/claude-code-proxy/venv/bin/pip install -q -r /opt/claude-code-proxy/requirements.txt

# Proxy .env — points to vLLM backend + local Firecrawl for web search
cat > /opt/claude-code-proxy/.env <<PROXYENV
OPENAI_API_KEY=local-vllm
OPENAI_BASE_URL=${LARGE_LLM_BASE_URL}
BIG_MODEL=${LARGE_LLM_MODEL}
MIDDLE_MODEL=${LARGE_LLM_MODEL}
SMALL_MODEL=${LARGE_LLM_MODEL}
SEARCH_PROVIDER=firecrawl
FIRECRAWL_API_URL=http://localhost:3002
HOST=127.0.0.1
PORT=8082
LOG_LEVEL=INFO
REQUEST_TIMEOUT=120
MAX_RETRIES=3
MAX_TOKENS_LIMIT=8192
MIN_TOKENS_LIMIT=100
MODEL_REGISTRY_ENABLED=True
PROXYENV

# Systemd service
cat > /etc/systemd/system/claude-code-proxy.service <<'PROXYUNIT'
[Unit]
Description=Claude Code Proxy (Anthropic→OpenAI with Firecrawl search)
After=network.target firecrawl-api.service
Wants=firecrawl-api.service

[Service]
Type=simple
WorkingDirectory=/opt/claude-code-proxy
ExecStart=/opt/claude-code-proxy/venv/bin/python -m uvicorn src.main:app --host 127.0.0.1 --port 8082
Restart=on-failure
RestartSec=5
Environment=PYTHONDONTWRITEBYTECODE=1

[Install]
WantedBy=multi-user.target
PROXYUNIT

systemctl daemon-reload
systemctl enable --now claude-code-proxy

# ============================================================
# 4. Claude Code — install binary + settings.json + .claude.json
# ============================================================
# Install Claude Code natively if not already present
# (Group A in tools script may fail; this is the safety net)
if ! su - "${ADMIN_USER}" -c 'export PATH="$HOME/.local/bin:$PATH"; command -v claude' >/dev/null 2>&1; then
    echo "Claude Code not found, installing..."
    retry_cmd 3 10 npm install -g @anthropic-ai/claude-code
    su - "${ADMIN_USER}" -c "claude install --force" 2>/dev/null || true
    npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
fi

# Ensure ~/.local/bin is in PATH via /etc/profile.d (affects all shells)
if [ ! -f /etc/profile.d/local-bin-path.sh ]; then
    cat > /etc/profile.d/local-bin-path.sh <<'PATHFIX'
# Ensure ~/.local/bin is in PATH for all users (Claude Code installs here)
if [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
PATHFIX
    chmod 644 /etc/profile.d/local-bin-path.sh
    echo "Added ~/.local/bin to system PATH via profile.d"
fi

mkdir -p "${UHOME}/.claude"

# ~/.claude/settings.json — permissions, model, vLLM env vars, UI prefs
cat > "${UHOME}/.claude/settings.json" <<'SETTINGS'
{
  "defaultMode": "bypassPermissions",
  "skipDangerousModePermissionPrompt": true,
  "permissions": { "allow": ["*"] },
  "model": "sonnet",
  "spinnerTipsEnabled": false,
  "terminalProgressBarEnabled": false,
  "showTurnDuration": false,
  "prefersReducedMotion": true,
  "companyAnnouncements": [],
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:8082",
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
