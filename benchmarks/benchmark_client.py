#!/usr/bin/env python3
"""
Async benchmark client for comparing Ollama and vLLM inference engines.

Sends concurrent streaming chat completion requests via the OpenAI-compatible
API and measures TTFT, latency, throughput at configurable concurrency levels.
"""

import argparse
import asyncio
import json
import statistics
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

import aiohttp
from tabulate import tabulate


@dataclass
class RequestResult:
    prompt_id: str
    ttft_ms: float = 0.0
    total_latency_ms: float = 0.0
    tokens_generated: int = 0
    tokens_per_second: float = 0.0
    error: str | None = None


@dataclass
class ConcurrencyStats:
    concurrency: int
    ttft_ms: dict = field(default_factory=dict)
    total_latency_ms: dict = field(default_factory=dict)
    tokens_per_second: dict = field(default_factory=dict)
    aggregate_throughput_tps: float = 0.0
    total_requests: int = 0
    failed_requests: int = 0


def percentile(data: list[float], p: float) -> float:
    """Compute the p-th percentile of a list of values."""
    if not data:
        return 0.0
    sorted_data = sorted(data)
    k = (len(sorted_data) - 1) * (p / 100)
    f = int(k)
    c = f + 1
    if c >= len(sorted_data):
        return sorted_data[f]
    return sorted_data[f] + (k - f) * (sorted_data[c] - sorted_data[f])


def compute_stats(values: list[float]) -> dict:
    """Compute summary statistics for a list of values."""
    if not values:
        return {"mean": 0, "p50": 0, "p95": 0, "p99": 0, "min": 0, "max": 0}
    return {
        "mean": round(statistics.mean(values), 2),
        "p50": round(percentile(values, 50), 2),
        "p95": round(percentile(values, 95), 2),
        "p99": round(percentile(values, 99), 2),
        "min": round(min(values), 2),
        "max": round(max(values), 2),
    }


async def send_streaming_request(
    session: aiohttp.ClientSession,
    base_url: str,
    model: str,
    messages: list[dict],
    max_tokens: int,
    timeout: int,
    prompt_id: str,
) -> RequestResult:
    """Send a single streaming chat completion request and measure performance."""
    url = f"{base_url}/chat/completions"
    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "stream": True,
        "temperature": 0.7,
    }

    t_start = time.perf_counter()
    t_first_token = None
    token_count = 0
    usage_tokens = None

    try:
        async with session.post(
            url,
            json=payload,
            timeout=aiohttp.ClientTimeout(total=timeout),
        ) as resp:
            if resp.status != 200:
                body = await resp.text()
                return RequestResult(
                    prompt_id=prompt_id,
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

                # Check for content in the delta
                choices = chunk.get("choices", [])
                if choices:
                    delta = choices[0].get("delta", {})
                    content = delta.get("content", "")
                    if content and t_first_token is None:
                        t_first_token = time.perf_counter()
                    if content:
                        token_count += 1

                # Check for usage in final chunk
                usage = chunk.get("usage")
                if usage and "completion_tokens" in usage:
                    usage_tokens = usage["completion_tokens"]

    except asyncio.TimeoutError:
        return RequestResult(prompt_id=prompt_id, error="timeout")
    except aiohttp.ClientError as e:
        return RequestResult(prompt_id=prompt_id, error=str(e))
    except Exception as e:
        return RequestResult(prompt_id=prompt_id, error=f"unexpected: {e}")

    t_end = time.perf_counter()

    # Use usage field if available, otherwise fall back to chunk count
    final_tokens = usage_tokens if usage_tokens is not None else token_count

    if t_first_token is None:
        return RequestResult(prompt_id=prompt_id, error="no tokens received")

    ttft = (t_first_token - t_start) * 1000
    total_latency = (t_end - t_start) * 1000
    tps = (final_tokens / (t_end - t_start)) if (t_end - t_start) > 0 else 0

    return RequestResult(
        prompt_id=prompt_id,
        ttft_ms=round(ttft, 2),
        total_latency_ms=round(total_latency, 2),
        tokens_generated=final_tokens,
        tokens_per_second=round(tps, 2),
    )


async def run_concurrency_level(
    base_url: str,
    model: str,
    prompts: list[dict],
    concurrency: int,
    iterations: int,
    warmup: int,
    timeout: int,
) -> tuple[list[RequestResult], float]:
    """Run benchmark at a specific concurrency level with warm-up."""
    connector = aiohttp.TCPConnector(limit=concurrency + 10)
    async with aiohttp.ClientSession(connector=connector) as session:
        # Warm-up phase (discarded)
        if warmup > 0:
            warmup_tasks = []
            for i in range(warmup):
                p = prompts[i % len(prompts)]
                warmup_tasks.append(
                    send_streaming_request(
                        session, base_url, model,
                        p["messages"], p.get("max_tokens", 256),
                        timeout, f"warmup_{i}",
                    )
                )
            await asyncio.gather(*warmup_tasks)

        # Measurement phase
        all_results = []
        total_wall_time = 0.0

        for iteration in range(iterations):
            tasks = []
            for i in range(concurrency):
                p = prompts[i % len(prompts)]
                tasks.append(
                    send_streaming_request(
                        session, base_url, model,
                        p["messages"], p.get("max_tokens", 256),
                        timeout, p["id"],
                    )
                )

            wall_start = time.perf_counter()
            results = await asyncio.gather(*tasks)
            wall_end = time.perf_counter()

            total_wall_time += wall_end - wall_start
            all_results.extend(results)

        avg_wall_time = total_wall_time / iterations if iterations > 0 else 0
        return all_results, avg_wall_time


def aggregate_results(
    results: list[RequestResult], wall_time: float
) -> ConcurrencyStats:
    """Compute aggregate statistics from a list of request results."""
    successful = [r for r in results if r.error is None]
    failed = [r for r in results if r.error is not None]

    ttft_values = [r.ttft_ms for r in successful]
    latency_values = [r.total_latency_ms for r in successful]
    tps_values = [r.tokens_per_second for r in successful]
    total_tokens = sum(r.tokens_generated for r in successful)

    agg_throughput = total_tokens / wall_time if wall_time > 0 else 0

    return ConcurrencyStats(
        concurrency=0,  # filled by caller
        ttft_ms=compute_stats(ttft_values),
        total_latency_ms=compute_stats(latency_values),
        tokens_per_second=compute_stats(tps_values),
        aggregate_throughput_tps=round(agg_throughput, 2),
        total_requests=len(results),
        failed_requests=len(failed),
    )


def print_summary_table(
    engine: str, model: str, all_stats: dict[int, ConcurrencyStats]
) -> str:
    """Print a formatted summary table and return it as a string."""
    headers = [
        "Concurrency",
        "TTFT p50\n(ms)",
        "TTFT p99\n(ms)",
        "Latency p50\n(ms)",
        "Latency p99\n(ms)",
        "Agg Throughput\n(tok/s)",
        "Errors",
    ]
    rows = []
    for c in sorted(all_stats.keys()):
        s = all_stats[c]
        rows.append([
            c,
            f"{s.ttft_ms.get('p50', 0):.0f}",
            f"{s.ttft_ms.get('p99', 0):.0f}",
            f"{s.total_latency_ms.get('p50', 0):.0f}",
            f"{s.total_latency_ms.get('p99', 0):.0f}",
            f"{s.aggregate_throughput_tps:.1f}",
            s.failed_requests,
        ])

    table = tabulate(rows, headers=headers, tablefmt="grid")
    header = f"\nEngine: {engine} | Model: {model}"
    output = f"{header}\n{table}\n"
    print(output)
    return output


async def main():
    parser = argparse.ArgumentParser(
        description="Benchmark LLM inference engines (Ollama / vLLM)"
    )
    parser.add_argument(
        "--base-url", required=True,
        help="Base URL for OpenAI-compatible API (e.g., http://localhost:8000/v1)",
    )
    parser.add_argument("--model", required=True, help="Model name/ID")
    parser.add_argument(
        "--engine", required=True, choices=["ollama", "vllm"],
        help="Engine name (for labeling output)",
    )
    parser.add_argument(
        "--concurrency", default="1,2,4,8,16,32",
        help="Comma-separated concurrency levels (default: 1,2,4,8,16,32)",
    )
    parser.add_argument(
        "--prompts", default="prompts.json",
        help="Path to prompts JSON file",
    )
    parser.add_argument("--output", required=True, help="Output JSON file path")
    parser.add_argument(
        "--warmup", type=int, default=2,
        help="Warm-up requests per concurrency level (default: 2)",
    )
    parser.add_argument(
        "--iterations", type=int, default=3,
        help="Measurement iterations per concurrency level (default: 3)",
    )
    parser.add_argument(
        "--timeout", type=int, default=120,
        help="Per-request timeout in seconds (default: 120)",
    )
    args = parser.parse_args()

    # Load prompts
    prompts_path = Path(args.prompts)
    if not prompts_path.exists():
        print(f"ERROR: Prompts file not found: {prompts_path}", file=sys.stderr)
        sys.exit(1)
    with open(prompts_path) as f:
        prompts = json.load(f)

    concurrency_levels = [int(c) for c in args.concurrency.split(",")]

    print(f"Benchmark: {args.engine} / {args.model}")
    print(f"Concurrency levels: {concurrency_levels}")
    print(f"Iterations: {args.iterations}, Warmup: {args.warmup}")
    print(f"API: {args.base_url}")
    print("-" * 60)

    all_stats: dict[int, ConcurrencyStats] = {}
    all_raw_results: dict[str, list[dict]] = {}

    for level in concurrency_levels:
        print(f"\nRunning concurrency={level}...", end=" ", flush=True)
        results, wall_time = await run_concurrency_level(
            base_url=args.base_url,
            model=args.model,
            prompts=prompts,
            concurrency=level,
            iterations=args.iterations,
            warmup=args.warmup,
            timeout=args.timeout,
        )

        stats = aggregate_results(results, wall_time)
        stats.concurrency = level
        all_stats[level] = stats

        successful = sum(1 for r in results if r.error is None)
        failed = sum(1 for r in results if r.error is not None)
        print(f"done ({successful} ok, {failed} errors)")

        # Log errors
        for r in results:
            if r.error:
                print(f"  ERROR [{r.prompt_id}]: {r.error}")

        all_raw_results[str(level)] = [asdict(r) for r in results]

    # Print summary table
    table_str = print_summary_table(args.engine, args.model, all_stats)

    # Build output JSON
    output_data = {
        "metadata": {
            "engine": args.engine,
            "model": args.model,
            "base_url": args.base_url,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "concurrency_levels": concurrency_levels,
            "iterations": args.iterations,
            "warmup_requests": args.warmup,
            "timeout_seconds": args.timeout,
            "prompt_count": len(prompts),
        },
        "concurrency_results": {
            str(level): asdict(stats) for level, stats in all_stats.items()
        },
        "raw_results": all_raw_results,
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"\nResults saved to: {output_path}")

    # Also save the table as text
    table_path = output_path.with_suffix(".txt")
    with open(table_path, "w") as f:
        f.write(table_str)


if __name__ == "__main__":
    asyncio.run(main())
