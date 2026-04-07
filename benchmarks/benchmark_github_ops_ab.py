#!/usr/bin/env python3
"""
A/B benchmark: Gemma-4-31B vs Phi-4-mini on GitHub operations tasks.

Tests TTFT, tokens/sec, latency, and quality at multiple concurrency levels
using the existing 56 GitHub ops test cases (5 categories).

Usage:
    python benchmark_github_ops_ab.py --iterations 3 --output results/ghops_ab/
"""

import argparse
import asyncio
import json
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
    "gemma4-31b": {
        "base_url": "http://10.0.0.10:8000/v1",
        "model": "gemma-4-31b",
        "label": "Gemma-4-31B",
    },
    "phi4-mini": {
        "base_url": "http://10.0.0.11:8000/v1",
        "model": "phi-4-mini",
        "label": "Phi-4-mini",
    },
}

# ---------------------------------------------------------------------------
# System prompt (GitHub ops specialist)
# ---------------------------------------------------------------------------
GITHUB_OPS_SYSTEM_PROMPT = """\
You are a specialized GitHub operations agent. Your expertise:
- Writing PR titles and descriptions from diffs
- Reviewing code for bugs and security issues
- Triaging issues with labels and priority
- Generating conventional commit messages
- Constructing gh CLI commands

Respond concisely and accurately. For PR descriptions, use markdown.
For code review, identify specific bugs with severity.
For issue triage, respond with JSON: {"labels": [...], "priority": "high|medium|low", "category": "..."}.
For commit messages, use conventional commits: type(scope): description.
For gh CLI, output the exact command.
"""

# ---------------------------------------------------------------------------
# Test case loading
# ---------------------------------------------------------------------------
TESTDATA_DIR = Path(__file__).parent / "github_ops_testdata"

CATEGORY_PROMPTS = {
    "pr_description": "Write a PR title and description for the following diff:\n\n{diff}\n\nContext: {context}",
    "code_review": "Review the following code for bugs and security issues:\n\n{code}\n\nContext: {context}",
    "issue_triage": "Triage the following issue and respond with JSON (labels, priority, category):\n\nTitle: {title}\nBody: {body}",
    "commit_message": "Write a conventional commit message for the following diff:\n\n{diff}\n\nContext: {context}",
    "gh_cli": "Generate the gh CLI command for: {task}",
}


def load_test_cases() -> list[dict]:
    """Load all test cases from the github_ops_testdata directory."""
    cases = []
    for json_file in sorted(TESTDATA_DIR.glob("*.json")):
        with open(json_file) as f:
            data = json.load(f)
        for tc in data:
            category = tc["category"]
            template = CATEGORY_PROMPTS.get(category, "{input}")
            inp = tc.get("input", {})
            if isinstance(inp, dict):
                prompt = template.format_map(
                    {k: inp.get(k, "") for k in re.findall(r"\{(\w+)\}", template)}
                )
            else:
                prompt = str(inp)
            cases.append({
                "id": tc["id"],
                "category": category,
                "prompt": prompt,
                "expected": tc.get("expected", {}),
                "max_tokens": tc.get("max_tokens", 512),
            })
    return cases


# ---------------------------------------------------------------------------
# Quality scoring (lightweight — adapted from github_ops_benchmark.py)
# ---------------------------------------------------------------------------

def score_response(content: str, test_case: dict) -> float:
    """Quick quality score 0-100 based on expected keywords/format."""
    expected = test_case.get("expected", {})
    category = test_case["category"]
    text = content.lower()
    score = 0.0

    if category == "pr_description":
        # Title present (20), keywords (30), markdown (20), mentions changes (30)
        if any(line.strip() for line in content.split("\n")[:3]):
            score += 20
        keywords = expected.get("title_keywords", [])
        hits = sum(1 for k in keywords if k.lower() in text)
        score += 30 * (hits / max(len(keywords), 1))
        if "#" in content or "**" in content or "- " in content:
            score += 20
        mentions = expected.get("description_must_mention", [])
        hits = sum(1 for m in mentions if m.lower() in text)
        score += 30 * (hits / max(len(mentions), 1))

    elif category == "code_review":
        bugs = expected.get("bugs", [])
        hits = sum(1 for b in bugs if b.lower() in text)
        score += 60 * (hits / max(len(bugs), 1))
        if any(w in text for w in ["critical", "high", "medium", "low"]):
            score += 20
        if any(w in text for w in ["fix", "recommend", "should", "instead"]):
            score += 20

    elif category == "issue_triage":
        try:
            parsed = json.loads(content.strip().strip("```json").strip("```").strip())
            if "labels" in parsed:
                score += 40
            if "priority" in parsed:
                score += 30
            if "category" in parsed:
                score += 30
        except (json.JSONDecodeError, ValueError):
            if "label" in text:
                score += 20
            if "priority" in text:
                score += 15

    elif category == "commit_message":
        if re.match(r"(feat|fix|docs|refactor|chore|test|style|perf|ci|build)", content.strip()):
            score += 40
        if "(" in content and ")" in content:
            score += 20
        if ":" in content:
            score += 20
        if len(content.strip().split("\n")[0]) <= 72:
            score += 20

    elif category == "gh_cli":
        if "gh " in text:
            score += 50
        expected_flags = expected.get("required_flags", [])
        hits = sum(1 for f in expected_flags if f.lower() in text)
        score += 50 * (hits / max(len(expected_flags), 1))

    return min(round(score, 1), 100.0)


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class RequestResult:
    test_id: str
    category: str
    model_key: str
    concurrency: int
    ttft_ms: float = 0.0
    total_latency_ms: float = 0.0
    tokens_generated: int = 0
    tokens_per_second: float = 0.0
    quality_score: float = 0.0
    error: str | None = None


# ---------------------------------------------------------------------------
# Streaming request
# ---------------------------------------------------------------------------

async def send_request(
    session: aiohttp.ClientSession,
    base_url: str,
    model: str,
    test_case: dict,
    model_key: str,
    concurrency: int,
    timeout: int,
) -> RequestResult:
    url = f"{base_url}/chat/completions"
    messages = [
        {"role": "system", "content": GITHUB_OPS_SYSTEM_PROMPT},
        {"role": "user", "content": test_case["prompt"]},
    ]
    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": test_case["max_tokens"],
        "stream": True,
        "temperature": 0.3,
    }

    t_start = time.perf_counter()
    t_first_token = None
    token_count = 0
    usage_tokens = None
    chunks: list[str] = []

    try:
        async with session.post(
            url, json=payload,
            timeout=aiohttp.ClientTimeout(total=timeout),
        ) as resp:
            if resp.status != 200:
                body = await resp.text()
                return RequestResult(
                    test_id=test_case["id"], category=test_case["category"],
                    model_key=model_key, concurrency=concurrency,
                    error=f"HTTP {resp.status}: {body[:200]}",
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
            test_id=test_case["id"], category=test_case["category"],
            model_key=model_key, concurrency=concurrency, error="timeout",
        )
    except aiohttp.ClientError as e:
        return RequestResult(
            test_id=test_case["id"], category=test_case["category"],
            model_key=model_key, concurrency=concurrency, error=str(e),
        )

    t_end = time.perf_counter()
    final_tokens = usage_tokens if usage_tokens is not None else token_count

    if t_first_token is None:
        return RequestResult(
            test_id=test_case["id"], category=test_case["category"],
            model_key=model_key, concurrency=concurrency, error="no tokens",
        )

    ttft = (t_first_token - t_start) * 1000
    total_latency = (t_end - t_start) * 1000
    elapsed = t_end - t_start
    tps = (final_tokens / elapsed) if elapsed > 0 else 0
    full_content = "".join(chunks)
    quality = score_response(full_content, test_case)

    return RequestResult(
        test_id=test_case["id"], category=test_case["category"],
        model_key=model_key, concurrency=concurrency,
        ttft_ms=round(ttft, 2), total_latency_ms=round(total_latency, 2),
        tokens_generated=final_tokens, tokens_per_second=round(tps, 2),
        quality_score=quality,
    )


# ---------------------------------------------------------------------------
# Stats helpers
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
# Benchmark runner
# ---------------------------------------------------------------------------

async def run_concurrent_batch(
    session: aiohttp.ClientSession,
    model_key: str,
    test_cases: list[dict],
    concurrency: int,
    timeout: int,
) -> list[RequestResult]:
    """Run test cases at a given concurrency level."""
    cfg = MODEL_CONFIGS[model_key]
    sem = asyncio.Semaphore(concurrency)
    results = []

    async def run_one(tc):
        async with sem:
            return await send_request(
                session, cfg["base_url"], cfg["model"],
                tc, model_key, concurrency, timeout,
            )

    tasks = [run_one(tc) for tc in test_cases]
    results = await asyncio.gather(*tasks)
    return list(results)


async def run_benchmark(
    iterations: int, concurrency_levels: list[int],
    warmup: int, timeout: int, output_dir: Path | None,
) -> dict:
    test_cases = load_test_cases()
    if not test_cases:
        print("ERROR: No test cases found in github_ops_testdata/")
        return {}

    print(f"Loaded {len(test_cases)} test cases across {len(set(tc['category'] for tc in test_cases))} categories")

    model_keys = list(MODEL_CONFIGS.keys())
    all_results: dict[str, dict[int, list[RequestResult]]] = {
        mk: {c: [] for c in concurrency_levels} for mk in model_keys
    }

    async with aiohttp.ClientSession() as session:
        # Warmup
        if warmup > 0:
            print(f"\n--- Warmup ({warmup} requests per model) ---")
            for mk in model_keys:
                cfg = MODEL_CONFIGS[mk]
                for w in range(warmup):
                    tc = test_cases[w % len(test_cases)]
                    r = await send_request(
                        session, cfg["base_url"], cfg["model"],
                        tc, mk, 1, timeout,
                    )
                    status = "OK" if r.error is None else r.error
                    print(f"  {cfg['label']:20s}  warmup {w+1}  {status}")

        # Measurement
        for conc in concurrency_levels:
            print(f"\n--- Concurrency={conc} ({iterations} iterations x {len(test_cases)} tests x {len(model_keys)} models) ---")
            for it in range(iterations):
                for mk in model_keys:
                    cfg = MODEL_CONFIGS[mk]
                    t_start = time.perf_counter()
                    batch_results = await run_concurrent_batch(
                        session, mk, test_cases, conc, timeout,
                    )
                    wall_time = time.perf_counter() - t_start
                    ok = [r for r in batch_results if r.error is None]
                    errs = [r for r in batch_results if r.error is not None]
                    total_tokens = sum(r.tokens_generated for r in ok)
                    agg_tps = total_tokens / wall_time if wall_time > 0 else 0

                    all_results[mk][conc].extend(batch_results)

                    print(
                        f"  iter={it+1} {cfg['label']:20s} c={conc:2d}  "
                        f"ok={len(ok):2d} err={len(errs):2d}  "
                        f"TTFT_p50={pct([r.ttft_ms for r in ok], 50):7.0f}ms  "
                        f"TPS_agg={agg_tps:6.0f}  "
                        f"quality={statistics.mean([r.quality_score for r in ok]):5.1f}" if ok else
                        f"  iter={it+1} {cfg['label']:20s} c={conc:2d}  ALL FAILED"
                    )

    # Build summary
    summary = {}
    for mk in model_keys:
        summary[mk] = {"label": MODEL_CONFIGS[mk]["label"], "concurrency": {}}
        for conc in concurrency_levels:
            ok = [r for r in all_results[mk][conc] if r.error is None]
            summary[mk]["concurrency"][conc] = {
                "total": len(all_results[mk][conc]),
                "ok": len(ok),
                "failed": len(all_results[mk][conc]) - len(ok),
                "ttft_ms": compute_stats([r.ttft_ms for r in ok]),
                "tps": compute_stats([r.tokens_per_second for r in ok]),
                "latency_ms": compute_stats([r.total_latency_ms for r in ok]),
                "quality": compute_stats([r.quality_score for r in ok]),
            }

    # Print comparison table
    print("\n" + "=" * 90)
    print("GitHub Ops A/B Benchmark — Gemma-4-31B vs Phi-4-mini")
    print("=" * 90)

    for conc in concurrency_levels:
        headers = ["Metric"] + [MODEL_CONFIGS[mk]["label"] for mk in model_keys]
        rows = [
            ["TTFT p50 (ms)"] + [summary[mk]["concurrency"][conc]["ttft_ms"]["p50"] for mk in model_keys],
            ["TTFT p95 (ms)"] + [summary[mk]["concurrency"][conc]["ttft_ms"]["p95"] for mk in model_keys],
            ["TPS mean"] + [summary[mk]["concurrency"][conc]["tps"]["mean"] for mk in model_keys],
            ["Latency p50 (ms)"] + [summary[mk]["concurrency"][conc]["latency_ms"]["p50"] for mk in model_keys],
            ["Quality mean"] + [summary[mk]["concurrency"][conc]["quality"]["mean"] for mk in model_keys],
            ["Requests ok/total"] + [
                f"{summary[mk]['concurrency'][conc]['ok']}/{summary[mk]['concurrency'][conc]['total']}"
                for mk in model_keys
            ],
        ]
        print(f"\n  Concurrency = {conc}")
        print(tabulate(rows, headers=headers, tablefmt="simple", floatfmt=".1f"))

    # Save JSON
    output = {
        "metadata": {
            "benchmark": "github_ops_ab",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "iterations": iterations,
            "concurrency_levels": concurrency_levels,
            "test_cases": len(test_cases),
            "categories": sorted(set(tc["category"] for tc in test_cases)),
            "models": {mk: MODEL_CONFIGS[mk] for mk in model_keys},
        },
        "summary": summary,
        "results": {
            mk: {
                str(conc): [asdict(r) for r in all_results[mk][conc]]
                for conc in concurrency_levels
            }
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
        description="A/B benchmark: Gemma-4 vs Phi-4-mini on GitHub ops tasks",
    )
    parser.add_argument("--iterations", type=int, default=3)
    parser.add_argument("--concurrency", type=str, default="1,2,4,8,12",
                        help="Comma-separated concurrency levels (default: 1,2,4,8,12)")
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--output", type=str, default=None)
    args = parser.parse_args()

    conc_levels = [int(c.strip()) for c in args.concurrency.split(",")]
    out = Path(args.output) if args.output else None
    asyncio.run(run_benchmark(args.iterations, conc_levels, args.warmup, args.timeout, out))


if __name__ == "__main__":
    main()
