#!/usr/bin/env python3
"""
Head-to-head sub-agent model comparison.

Runs the exact same GitHub operations workload against two models at multiple
concurrency levels, measuring quality, TTFT, latency, and throughput.
"""

import argparse
import asyncio
import json
import statistics
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import aiohttp

# Import scoring functions from the quality benchmark
sys.path.insert(0, str(Path(__file__).parent))
from github_ops_benchmark import SCORERS, SYSTEM_PROMPTS


@dataclass
class RequestMetrics:
    test_id: str
    category: str
    ttft_ms: float = 0.0
    latency_ms: float = 0.0
    tokens: int = 0
    tps: float = 0.0
    score: float = 0.0
    error: str | None = None


@dataclass
class ConcurrencyResult:
    concurrency: int
    ttft_p50: float = 0.0
    ttft_p99: float = 0.0
    latency_p50: float = 0.0
    latency_p99: float = 0.0
    agg_throughput: float = 0.0
    mean_score: float = 0.0
    total: int = 0
    failed: int = 0


def percentile(data: list[float], p: float) -> float:
    if not data:
        return 0.0
    s = sorted(data)
    k = (len(s) - 1) * (p / 100)
    f = int(k)
    c = min(f + 1, len(s) - 1)
    return s[f] + (k - f) * (s[c] - s[f])


def build_messages(test_case: dict) -> list[dict]:
    """Build chat messages from a test case."""
    cat = test_case["category"]
    inp = test_case["input"]
    system = SYSTEM_PROMPTS.get(cat, "")

    if cat == "pr_description":
        user = f"Here is the git diff:\n\n{inp['diff']}"
    elif cat == "code_review":
        user = f"Review this {inp.get('language', 'code')} code from {inp.get('file_path', 'unknown')}:\n\n{inp['code']}"
    elif cat == "issue_triage":
        user = f"Title: {inp['title']}\n\nBody: {inp['body']}"
    elif cat == "commit_message":
        user = f"Generate a commit message for this diff:\n\n{inp['diff']}"
    elif cat == "gh_cli":
        user = inp["task"]
    else:
        user = json.dumps(inp)

    return [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ]


async def send_request(
    session: aiohttp.ClientSession,
    url: str,
    model: str,
    test_case: dict,
    timeout: int,
) -> RequestMetrics:
    """Send a streaming request, measure TTFT and latency, then score."""
    messages = build_messages(test_case)
    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": test_case.get("max_tokens", 500),
        "temperature": 0.3,
        "stream": True,
    }

    t_start = time.perf_counter()
    t_first = None
    token_count = 0
    chunks = []

    try:
        async with session.post(
            url, json=payload, timeout=aiohttp.ClientTimeout(total=timeout)
        ) as resp:
            if resp.status != 200:
                body = await resp.text()
                return RequestMetrics(
                    test_id=test_case["id"], category=test_case["category"],
                    error=f"HTTP {resp.status}: {body[:120]}"
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
                    content = choices[0].get("delta", {}).get("content", "")
                    if content:
                        if t_first is None:
                            t_first = time.perf_counter()
                        token_count += 1
                        chunks.append(content)

    except asyncio.TimeoutError:
        return RequestMetrics(
            test_id=test_case["id"], category=test_case["category"], error="timeout"
        )
    except Exception as e:
        return RequestMetrics(
            test_id=test_case["id"], category=test_case["category"], error=str(e)
        )

    t_end = time.perf_counter()
    if t_first is None:
        return RequestMetrics(
            test_id=test_case["id"], category=test_case["category"], error="no tokens"
        )

    full_text = "".join(chunks)
    ttft = (t_first - t_start) * 1000
    latency = (t_end - t_start) * 1000
    tps = token_count / (t_end - t_start) if (t_end - t_start) > 0 else 0

    # Score
    scorer = SCORERS.get(test_case["category"])
    score = 0.0
    if scorer:
        score, _ = scorer(full_text, test_case.get("expected", {}))

    return RequestMetrics(
        test_id=test_case["id"],
        category=test_case["category"],
        ttft_ms=round(ttft, 1),
        latency_ms=round(latency, 1),
        tokens=token_count,
        tps=round(tps, 1),
        score=score,
    )


async def run_concurrency_level(
    base_url: str, model: str, cases: list[dict], concurrency: int, timeout: int
) -> ConcurrencyResult:
    """Run all test cases at a given concurrency level."""
    url = f"{base_url}/chat/completions"
    sem = asyncio.Semaphore(concurrency)
    connector = aiohttp.TCPConnector(limit=concurrency + 5)

    async def bounded(session, case):
        async with sem:
            return await send_request(session, url, model, case, timeout)

    wall_start = time.perf_counter()
    async with aiohttp.ClientSession(connector=connector) as session:
        tasks = [bounded(session, c) for c in cases]
        results = await asyncio.gather(*tasks)
    wall_end = time.perf_counter()
    wall_time = wall_end - wall_start

    ok = [r for r in results if r.error is None]
    failed = [r for r in results if r.error is not None]

    ttfts = [r.ttft_ms for r in ok]
    lats = [r.latency_ms for r in ok]
    scores = [r.score for r in ok]
    total_tokens = sum(r.tokens for r in ok)

    return ConcurrencyResult(
        concurrency=concurrency,
        ttft_p50=round(percentile(ttfts, 50), 1),
        ttft_p99=round(percentile(ttfts, 99), 1),
        latency_p50=round(percentile(lats, 50), 1),
        latency_p99=round(percentile(lats, 99), 1),
        agg_throughput=round(total_tokens / wall_time, 1) if wall_time > 0 else 0,
        mean_score=round(statistics.mean(scores), 1) if scores else 0,
        total=len(results),
        failed=len(failed),
    )


async def benchmark_model(
    name: str, base_url: str, model: str, cases: list[dict],
    concurrency_levels: list[int], timeout: int
) -> dict:
    """Run full benchmark for one model."""
    print(f"\n{'='*60}")
    print(f"Model: {name} ({model})")
    print(f"API:   {base_url}")
    print(f"Cases: {len(cases)}, Concurrency: {concurrency_levels}")
    print(f"{'='*60}")

    results = {}
    for c in concurrency_levels:
        print(f"  c={c:>2}...", end=" ", flush=True)
        r = await run_concurrency_level(base_url, model, cases, c, timeout)
        results[c] = r
        print(
            f"TTFT p50={r.ttft_p50:>6.0f}ms  "
            f"Latency p50={r.latency_p50:>7.0f}ms  "
            f"Throughput={r.agg_throughput:>7.1f} tok/s  "
            f"Quality={r.mean_score:>5.1f}  "
            f"Errors={r.failed}"
        )
    return results


def print_comparison(model_a: str, results_a: dict, model_b: str, results_b: dict) -> str:
    """Print side-by-side comparison table."""
    lines = []
    lines.append("")
    lines.append("=" * 90)
    lines.append(f"HEAD-TO-HEAD: {model_a} vs {model_b}")
    lines.append("=" * 90)

    # TTFT comparison
    lines.append("")
    lines.append("TTFT p50 (ms) — lower is better")
    header = f"{'Concurrency':>12} | {model_a:>18} | {model_b:>18} | {'Winner':>18}"
    lines.append(header)
    lines.append("-" * len(header))
    for c in sorted(results_a.keys()):
        a = results_a[c].ttft_p50
        b = results_b[c].ttft_p50
        winner = model_a if a < b else model_b if b < a else "TIE"
        delta = abs(a - b) / max(a, b) * 100 if max(a, b) > 0 else 0
        lines.append(f"{c:>12} | {a:>15.0f} ms | {b:>15.0f} ms | {winner} ({delta:.0f}%)")

    # Latency comparison
    lines.append("")
    lines.append("Latency p50 (ms) — lower is better")
    header = f"{'Concurrency':>12} | {model_a:>18} | {model_b:>18} | {'Winner':>18}"
    lines.append(header)
    lines.append("-" * len(header))
    for c in sorted(results_a.keys()):
        a = results_a[c].latency_p50
        b = results_b[c].latency_p50
        winner = model_a if a < b else model_b if b < a else "TIE"
        ratio = a / b if b > 0 else 0
        lines.append(f"{c:>12} | {a:>15.0f} ms | {b:>15.0f} ms | {winner} ({ratio:.1f}x)")

    # Throughput comparison
    lines.append("")
    lines.append("Aggregate Throughput (tok/s) — higher is better")
    header = f"{'Concurrency':>12} | {model_a:>18} | {model_b:>18} | {'Winner':>18}"
    lines.append(header)
    lines.append("-" * len(header))
    for c in sorted(results_a.keys()):
        a = results_a[c].agg_throughput
        b = results_b[c].agg_throughput
        winner = model_a if a > b else model_b if b > a else "TIE"
        ratio = a / b if b > 0 else 0
        lines.append(f"{c:>12} | {a:>14.1f} t/s | {b:>14.1f} t/s | {winner} ({ratio:.1f}x)")

    # Quality comparison
    lines.append("")
    lines.append("Quality Score (0-100) — higher is better")
    header = f"{'Concurrency':>12} | {model_a:>18} | {model_b:>18} | {'Winner':>18}"
    lines.append(header)
    lines.append("-" * len(header))
    for c in sorted(results_a.keys()):
        a = results_a[c].mean_score
        b = results_b[c].mean_score
        winner = model_a if a > b else model_b if b > a else "TIE"
        lines.append(f"{c:>12} | {a:>16.1f}/100 | {b:>16.1f}/100 | {winner} (+{abs(a-b):.1f})")

    # Tail latency
    lines.append("")
    lines.append("Latency p99 (ms) — lower is better (tail latency, what users feel)")
    header = f"{'Concurrency':>12} | {model_a:>18} | {model_b:>18} | {'Winner':>18}"
    lines.append(header)
    lines.append("-" * len(header))
    for c in sorted(results_a.keys()):
        a = results_a[c].latency_p99
        b = results_b[c].latency_p99
        winner = model_a if a < b else model_b if b < a else "TIE"
        lines.append(f"{c:>12} | {a:>15.0f} ms | {b:>15.0f} ms | {winner}")

    output = "\n".join(lines)
    print(output)
    return output


async def main():
    parser = argparse.ArgumentParser(description="Head-to-head sub-agent model comparison")
    parser.add_argument("--model-a-url", required=True, help="Base URL for model A (e.g., http://localhost:8001/v1)")
    parser.add_argument("--model-a-name", required=True, help="Display name for model A")
    parser.add_argument("--model-a-id", required=True, help="Model ID for model A API calls")
    parser.add_argument("--model-b-url", required=True, help="Base URL for model B")
    parser.add_argument("--model-b-name", required=True, help="Display name for model B")
    parser.add_argument("--model-b-id", required=True, help="Model ID for model B API calls")
    parser.add_argument("--testdata-dir", default="github_ops_testdata", help="Test data directory")
    parser.add_argument("--output", required=True, help="Output JSON file")
    parser.add_argument("--concurrency", default="1,4,8,16", help="Concurrency levels (default: 1,4,8,16)")
    parser.add_argument("--timeout", type=int, default=180, help="Per-request timeout (default: 180)")
    args = parser.parse_args()

    concurrency_levels = [int(c) for c in args.concurrency.split(",")]
    testdata_dir = Path(args.testdata_dir)

    # Load all test cases
    cases = []
    for cat in ["pr_description", "code_review", "issue_triage", "commit_message", "gh_cli"]:
        f = testdata_dir / f"{cat}.json"
        if f.exists():
            with open(f) as fh:
                cases.extend(json.load(fh))
            print(f"Loaded {cat}: {sum(1 for c in cases if c['category'] == cat)} cases")

    print(f"\nTotal: {len(cases)} test cases")

    # Benchmark both models
    results_a = await benchmark_model(
        args.model_a_name, args.model_a_url, args.model_a_id,
        cases, concurrency_levels, args.timeout
    )
    results_b = await benchmark_model(
        args.model_b_name, args.model_b_url, args.model_b_id,
        cases, concurrency_levels, args.timeout
    )

    # Print comparison
    report = print_comparison(args.model_a_name, results_a, args.model_b_name, results_b)

    # Save results
    output_data = {
        "metadata": {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "test_cases": len(cases),
            "concurrency_levels": concurrency_levels,
        },
        "model_a": {
            "name": args.model_a_name,
            "model_id": args.model_a_id,
            "url": args.model_a_url,
            "results": {
                str(c): {
                    "ttft_p50": r.ttft_p50, "ttft_p99": r.ttft_p99,
                    "latency_p50": r.latency_p50, "latency_p99": r.latency_p99,
                    "agg_throughput": r.agg_throughput,
                    "mean_score": r.mean_score,
                    "total": r.total, "failed": r.failed,
                } for c, r in results_a.items()
            },
        },
        "model_b": {
            "name": args.model_b_name,
            "model_id": args.model_b_id,
            "url": args.model_b_url,
            "results": {
                str(c): {
                    "ttft_p50": r.ttft_p50, "ttft_p99": r.ttft_p99,
                    "latency_p50": r.latency_p50, "latency_p99": r.latency_p99,
                    "agg_throughput": r.agg_throughput,
                    "mean_score": r.mean_score,
                    "total": r.total, "failed": r.failed,
                } for c, r in results_b.items()
            },
        },
    }

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w") as f:
        json.dump(output_data, f, indent=2)

    txt = out.with_suffix(".txt")
    with open(txt, "w") as f:
        f.write(report)

    print(f"\nResults: {out}")
    print(f"Report:  {txt}")


if __name__ == "__main__":
    asyncio.run(main())
