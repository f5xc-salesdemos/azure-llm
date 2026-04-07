#!/usr/bin/env python3
"""
A/B benchmark: Devstral-Small-2-24B vs Gemma-4-31B on F5 XC API tasks.

Sends identical F5 XC API prompts to both models via streaming chat completions,
measures TTFT / tokens-per-second / latency, and scores response quality using
deterministic heuristics (correct API path, auth header, HTTP method, env vars).

Usage:
    export F5XC_API_URL=https://...  F5XC_API_TOKEN=...
    python benchmark_f5xc_ab.py --iterations 5 --output results/f5xc_ab_run/
"""

import argparse
import asyncio
import json
import os
import re
import statistics
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import aiohttp
from tabulate import tabulate

# ---------------------------------------------------------------------------
# Models under test
# ---------------------------------------------------------------------------
MODEL_CONFIGS = {
    "devstral-24b": {
        "base_url": "http://10.0.0.11:8002/v1",
        "model": "devstral-24b",
        "label": "Devstral-Small-2-24B",
    },
    "gemma4-31b": {
        "base_url": "http://10.0.0.10:8000/v1",
        "model": "gemma-4-31b",
        "label": "Gemma-4-31B",
    },
}

# ---------------------------------------------------------------------------
# System prompt — mirrors the f5xc-api agent definition
# ---------------------------------------------------------------------------
F5XC_SYSTEM_PROMPT = """\
You are an F5 Distributed Cloud API operations agent. You MUST generate \
curl commands to interact with the F5 XC REST API.

## Authentication
All API calls use:
  curl -s "$F5XC_API_URL/..." -H "Authorization: APIToken $F5XC_API_TOKEN" | jq .

Required env vars: F5XC_API_URL, F5XC_API_TOKEN, F5XC_NAMESPACE

## CRUD Pattern
- List:    GET    /api/config/namespaces/{ns}/{resources}
- Create:  POST   /api/config/namespaces/{ns}/{resources}
- Get:     GET    /api/config/namespaces/{ns}/{resources}/{name}
- Replace: PUT    /api/config/namespaces/{ns}/{resources}/{name}
- Delete:  DELETE /api/config/namespaces/{ns}/{resources}/{name}

Request body: {"metadata": {"name": "...", "namespace": "..."}, "spec": {...}}

## Rules
1. Always use curl -s with the APIToken header
2. Always pipe through jq
3. Use env vars ($F5XC_API_URL, $F5XC_NAMESPACE, $F5XC_API_TOKEN) — never hardcode
4. For create/replace, include a JSON body with metadata.name, metadata.namespace, and spec
"""

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------
TEST_CASES = [
    {
        "id": "list_http_lb",
        "category": "list_resources",
        "prompt": "List all HTTP load balancers in my namespace.",
        "expected_method": "GET",
        "expected_path_re": r"/api/config/namespaces/[^/]+/http_loadbalancers",
        "max_tokens": 512,
        "needs_body": False,
    },
    {
        "id": "list_origin_pools",
        "category": "list_resources",
        "prompt": "List all origin pools in my namespace.",
        "expected_method": "GET",
        "expected_path_re": r"/api/config/namespaces/[^/]+/origin_pools",
        "max_tokens": 512,
        "needs_body": False,
    },
    {
        "id": "get_lb_by_name",
        "category": "get_resource",
        "prompt": "Get the details of the HTTP load balancer named 'frontend-lb'.",
        "expected_method": "GET",
        "expected_path_re": r"/api/config/namespaces/[^/]+/http_loadbalancers/frontend-lb",
        "max_tokens": 512,
        "needs_body": False,
    },
    {
        "id": "create_healthcheck",
        "category": "create_resource",
        "prompt": (
            "Create a health check named 'web-hc' with an HTTP probe on "
            "path /healthz port 8080."
        ),
        "expected_method": "POST",
        "expected_path_re": r"/api/config/namespaces/[^/]+/healthchecks",
        "max_tokens": 1024,
        "needs_body": True,
    },
    {
        "id": "delete_origin_pool",
        "category": "delete_resource",
        "prompt": "Delete the origin pool named 'old-backend'.",
        "expected_method": "DELETE",
        "expected_path_re": r"/api/config/namespaces/[^/]+/origin_pools/old-backend",
        "max_tokens": 512,
        "needs_body": False,
    },
]

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class RequestResult:
    test_id: str
    model_key: str
    iteration: int
    ttft_ms: float = 0.0
    total_latency_ms: float = 0.0
    tokens_generated: int = 0
    tokens_per_second: float = 0.0
    content: str = ""
    quality_score: float = 0.0
    subscores: dict = field(default_factory=dict)
    error: str | None = None


# ---------------------------------------------------------------------------
# Quality scoring
# ---------------------------------------------------------------------------

def score_response(content: str, test_case: dict) -> tuple[float, dict]:
    """Score model output against expected F5 XC API patterns. Returns (total, subscores)."""
    text = content.lower()
    subscores = {}

    # 1. Correct API path (25 pts)
    pattern = test_case["expected_path_re"]
    subscores["api_path"] = 25.0 if re.search(pattern, content, re.IGNORECASE) else 0.0

    # 2. Auth header (20 pts)
    has_auth = (
        "authorization: apitoken" in text
        or "authorization:apitoken" in text
        or '"authorization: apitoken' in text
    )
    subscores["auth_header"] = 20.0 if has_auth else 0.0

    # 3. Correct HTTP method (15 pts)
    method = test_case["expected_method"]
    method_patterns = {
        "GET": [r"curl\s+(-[sS]\s+)?.*\$F5XC_API_URL", r"curl\s"],
        "POST": [r"curl\s.*-X\s*POST", r"curl\s.*--request\s*POST", r'-d\s'],
        "DELETE": [r"curl\s.*-X\s*DELETE", r"curl\s.*--request\s*DELETE"],
        "PUT": [r"curl\s.*-X\s*PUT", r"curl\s.*--request\s*PUT"],
    }
    if method == "GET":
        # GET is default for curl, just check curl is present and no other method
        has_method = bool(re.search(r"curl\s", content, re.IGNORECASE))
        has_other = bool(
            re.search(r"-X\s*(POST|PUT|DELETE|PATCH)", content, re.IGNORECASE)
        )
        subscores["http_method"] = 15.0 if (has_method and not has_other) else 0.0
    else:
        found = any(
            re.search(p, content, re.IGNORECASE)
            for p in method_patterns.get(method, [])
        )
        subscores["http_method"] = 15.0 if found else 0.0

    # 4. Uses env vars (15 pts) — $F5XC_API_URL, $F5XC_API_TOKEN, $F5XC_NAMESPACE
    env_hits = 0
    for var in ["F5XC_API_URL", "F5XC_API_TOKEN"]:
        if f"${var}" in content or f"${{{var}}}" in content:
            env_hits += 1
    # namespace usage is optional for some prompts but good practice
    for var in ["F5XC_NAMESPACE"]:
        if f"${var}" in content or f"${{{var}}}" in content:
            env_hits += 1
    subscores["env_vars"] = min(15.0, env_hits * 5.0)

    # 5. jq usage (10 pts)
    subscores["jq_usage"] = 10.0 if "jq" in text else 0.0

    # 6. Correct body structure for create/update (15 pts)
    if test_case["needs_body"]:
        has_metadata = "metadata" in text and "name" in text
        has_spec = "spec" in text
        body_score = 0.0
        if has_metadata:
            body_score += 10.0
        if has_spec:
            body_score += 5.0
        subscores["request_body"] = body_score
    else:
        subscores["request_body"] = 15.0  # full marks — no body needed

    total = sum(subscores.values())
    return round(total, 1), subscores


# ---------------------------------------------------------------------------
# Streaming request (adapted from benchmark_client.py)
# ---------------------------------------------------------------------------

async def send_request(
    session: aiohttp.ClientSession,
    base_url: str,
    model: str,
    test_case: dict,
    model_key: str,
    iteration: int,
    timeout: int,
) -> RequestResult:
    """Send a streaming chat completion and measure TTFT / TPS / quality."""
    url = f"{base_url}/chat/completions"
    messages = [
        {"role": "system", "content": F5XC_SYSTEM_PROMPT},
        {"role": "user", "content": test_case["prompt"]},
    ]
    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": test_case["max_tokens"],
        "stream": True,
        "temperature": 0.1,
    }

    t_start = time.perf_counter()
    t_first_token = None
    token_count = 0
    usage_tokens = None
    chunks: list[str] = []

    try:
        async with session.post(
            url,
            json=payload,
            timeout=aiohttp.ClientTimeout(total=timeout),
        ) as resp:
            if resp.status != 200:
                body = await resp.text()
                return RequestResult(
                    test_id=test_case["id"],
                    model_key=model_key,
                    iteration=iteration,
                    error=f"HTTP {resp.status}: {body[:300]}",
                )

            async for line in resp.content:
                decoded = line.decode("utf-8").strip()
                if not decoded.startswith("data:"):
                    continue
                data_str = decoded[5:].strip()
                if data_str == "[DONE]":
                    break
                try:
                    chunk = json.loads(data_str)
                except json.JSONDecodeError:
                    continue

                choices = chunk.get("choices", [])
                if choices:
                    delta = choices[0].get("delta", {})
                    content = delta.get("content", "")
                    if content:
                        if t_first_token is None:
                            t_first_token = time.perf_counter()
                        token_count += 1
                        chunks.append(content)

                usage = chunk.get("usage")
                if usage and "completion_tokens" in usage:
                    usage_tokens = usage["completion_tokens"]

    except asyncio.TimeoutError:
        return RequestResult(
            test_id=test_case["id"], model_key=model_key,
            iteration=iteration, error="timeout",
        )
    except aiohttp.ClientError as e:
        return RequestResult(
            test_id=test_case["id"], model_key=model_key,
            iteration=iteration, error=str(e),
        )

    t_end = time.perf_counter()
    final_tokens = usage_tokens if usage_tokens is not None else token_count

    if t_first_token is None:
        return RequestResult(
            test_id=test_case["id"], model_key=model_key,
            iteration=iteration, error="no tokens received",
        )

    ttft = (t_first_token - t_start) * 1000
    total_latency = (t_end - t_start) * 1000
    elapsed = t_end - t_start
    tps = (final_tokens / elapsed) if elapsed > 0 else 0

    full_content = "".join(chunks)
    quality, subscores = score_response(full_content, test_case)

    return RequestResult(
        test_id=test_case["id"],
        model_key=model_key,
        iteration=iteration,
        ttft_ms=round(ttft, 2),
        total_latency_ms=round(total_latency, 2),
        tokens_generated=final_tokens,
        tokens_per_second=round(tps, 2),
        content=full_content,
        quality_score=quality,
        subscores=subscores,
    )


# ---------------------------------------------------------------------------
# Statistics helpers (from benchmark_client.py)
# ---------------------------------------------------------------------------

def pct(data: list[float], p: float) -> float:
    if not data:
        return 0.0
    s = sorted(data)
    k = (len(s) - 1) * (p / 100)
    f = int(k)
    c = min(f + 1, len(s) - 1)
    return s[f] + (s[c] - s[f]) * (k - f)


def compute_stats(values: list[float]) -> dict:
    if not values:
        return {"mean": 0, "p50": 0, "p95": 0, "min": 0, "max": 0}
    return {
        "mean": round(statistics.mean(values), 2),
        "p50": round(pct(values, 50), 2),
        "p95": round(pct(values, 95), 2),
        "min": round(min(values), 2),
        "max": round(max(values), 2),
    }


# ---------------------------------------------------------------------------
# Main benchmark loop
# ---------------------------------------------------------------------------

async def run_benchmark(
    iterations: int, warmup: int, timeout: int, output_dir: Path | None,
) -> dict:
    results: dict[str, list[RequestResult]] = {k: [] for k in MODEL_CONFIGS}
    model_keys = list(MODEL_CONFIGS.keys())

    async with aiohttp.ClientSession() as session:
        # Warmup
        if warmup > 0:
            print(f"\n--- Warmup ({warmup} request(s) per model) ---")
            for mk in model_keys:
                cfg = MODEL_CONFIGS[mk]
                for w in range(warmup):
                    tc = TEST_CASES[w % len(TEST_CASES)]
                    r = await send_request(
                        session, cfg["base_url"], cfg["model"],
                        tc, mk, -1, timeout,
                    )
                    status = "OK" if r.error is None else r.error
                    print(f"  {cfg['label']:25s}  warmup {w+1}  {status}")

        # Measurement iterations — interleaved
        print(f"\n--- Benchmark ({iterations} iterations x {len(TEST_CASES)} tests x {len(model_keys)} models) ---")
        for it in range(iterations):
            for mk in model_keys:
                cfg = MODEL_CONFIGS[mk]
                for tc in TEST_CASES:
                    r = await send_request(
                        session, cfg["base_url"], cfg["model"],
                        tc, mk, it, timeout,
                    )
                    results[mk].append(r)
                    if r.error:
                        print(f"  iter={it+1} {cfg['label']:25s} {tc['id']:20s}  ERROR: {r.error}")
                    else:
                        print(
                            f"  iter={it+1} {cfg['label']:25s} {tc['id']:20s}  "
                            f"TTFT={r.ttft_ms:7.1f}ms  TPS={r.tokens_per_second:6.1f}  "
                            f"quality={r.quality_score:5.1f}"
                        )

    # Build summary
    summary = {}
    for mk in model_keys:
        ok = [r for r in results[mk] if r.error is None]
        summary[mk] = {
            "label": MODEL_CONFIGS[mk]["label"],
            "total_requests": len(results[mk]),
            "failed": sum(1 for r in results[mk] if r.error is not None),
            "ttft_ms": compute_stats([r.ttft_ms for r in ok]),
            "tokens_per_second": compute_stats([r.tokens_per_second for r in ok]),
            "total_latency_ms": compute_stats([r.total_latency_ms for r in ok]),
            "quality": compute_stats([r.quality_score for r in ok]),
        }

    # Print comparison table
    print("\n" + "=" * 72)
    print("F5 XC API A/B Benchmark — Side-by-Side Comparison")
    print("=" * 72)

    headers = ["Metric"] + [MODEL_CONFIGS[mk]["label"] for mk in model_keys]
    rows = []
    for metric, key in [
        ("TTFT p50 (ms)", "ttft_ms"),
        ("TTFT p95 (ms)", "ttft_ms"),
        ("TPS mean", "tokens_per_second"),
        ("TPS p50", "tokens_per_second"),
        ("Latency p50 (ms)", "total_latency_ms"),
        ("Latency p95 (ms)", "total_latency_ms"),
        ("Quality mean", "quality"),
    ]:
        stat_key = "p95" if "p95" in metric else ("p50" if "p50" in metric else "mean")
        row = [metric]
        for mk in model_keys:
            row.append(summary[mk][key][stat_key])
        rows.append(row)

    rows.append(["Requests (ok/total)"] + [
        f"{summary[mk]['total_requests'] - summary[mk]['failed']}/{summary[mk]['total_requests']}"
        for mk in model_keys
    ])

    print(tabulate(rows, headers=headers, tablefmt="simple", floatfmt=".1f"))

    # Determine winners
    print("\n--- Winners ---")
    for metric, key, lower_better in [
        ("TTFT", "ttft_ms", True),
        ("Tokens/sec", "tokens_per_second", False),
        ("Latency", "total_latency_ms", True),
        ("Quality", "quality", False),
    ]:
        vals = {mk: summary[mk][key]["mean"] for mk in model_keys}
        if lower_better:
            winner = min(vals, key=lambda k: vals[k])
        else:
            winner = max(vals, key=lambda k: vals[k])
        other = [mk for mk in model_keys if mk != winner][0]
        v_w, v_o = vals[winner], vals[other]
        if v_o != 0:
            delta = abs(v_w - v_o) / v_o * 100
        else:
            delta = 0
        print(f"  {metric:15s}  {MODEL_CONFIGS[winner]['label']}  ({delta:+.1f}%)")

    # Save JSON
    output = {
        "metadata": {
            "benchmark": "f5xc_api_ab",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "iterations": iterations,
            "warmup": warmup,
            "timeout": timeout,
            "test_cases": len(TEST_CASES),
            "models": {
                mk: {
                    "label": MODEL_CONFIGS[mk]["label"],
                    "base_url": MODEL_CONFIGS[mk]["base_url"],
                    "model": MODEL_CONFIGS[mk]["model"],
                }
                for mk in model_keys
            },
        },
        "summary": summary,
        "results": {
            mk: [asdict(r) for r in results[mk]]
            for mk in model_keys
        },
    }

    if output_dir:
        output_dir.mkdir(parents=True, exist_ok=True)
        out_file = output_dir / "results.json"
        out_file.write_text(json.dumps(output, indent=2, default=str))
        print(f"\nResults saved to {out_file}")

    return output


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="A/B benchmark: Devstral vs Gemma on F5 XC API tasks",
    )
    parser.add_argument("--iterations", type=int, default=5)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--output", type=str, default=None,
                        help="Output directory for results JSON")
    args = parser.parse_args()

    # Verify env vars are set (not used by script, but inform the user)
    for var in ["F5XC_API_URL", "F5XC_API_TOKEN"]:
        if not os.environ.get(var):
            print(f"WARNING: {var} not set — model responses may reference unset vars")

    out = Path(args.output) if args.output else None
    asyncio.run(run_benchmark(args.iterations, args.warmup, args.timeout, out))


if __name__ == "__main__":
    main()
