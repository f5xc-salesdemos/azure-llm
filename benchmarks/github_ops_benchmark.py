#!/usr/bin/env python3
"""
GitHub Operations Quality Benchmark

Evaluates LLM quality on GitHub-specific tasks: PR descriptions, code review,
issue triage, commit messages, and gh CLI command generation.

Sends chat completions to a vLLM OpenAI-compatible API, then scores responses
using deterministic heuristics (no external LLM judge needed).

NOTE: The code_review test cases contain INTENTIONALLY vulnerable code snippets.
These are benchmark fixtures for evaluating whether models can detect security
issues, NOT production code.
"""

import argparse
import asyncio
import json
import re
import statistics
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

import aiohttp
from tabulate import tabulate


# ==============================================================================
# Data structures
# ==============================================================================

@dataclass
class TestResult:
    test_case_id: str
    category: str
    score: float = 0.0
    subscores: dict = field(default_factory=dict)
    model_output: str = ""
    latency_ms: float = 0.0
    error: str | None = None


@dataclass
class CategorySummary:
    category: str
    mean_score: float = 0.0
    median_score: float = 0.0
    min_score: float = 0.0
    max_score: float = 0.0
    total_cases: int = 0
    failed_cases: int = 0


# ==============================================================================
# System prompts per category
# ==============================================================================

SYSTEM_PROMPTS = {
    "pr_description": (
        "You are a developer writing a pull request description. "
        "Given a git diff, write a concise PR title on the first line, "
        "then a blank line, then a markdown description explaining what changed and why. "
        "Focus on the purpose of the change, not just listing modified files."
    ),
    "code_review": (
        "You are a senior code reviewer. Analyze the provided code for bugs, "
        "security vulnerabilities, and issues. For each issue found, state: "
        "1) The bug type (e.g., SQL injection, race condition) "
        "2) The severity (critical/high/medium/low) "
        "3) A suggested fix. Be specific and actionable."
    ),
    "issue_triage": (
        "You are a project maintainer triaging an issue. "
        "Respond with a JSON object containing: "
        "\"labels\" (array of strings like bug/enhancement/documentation/security/question/performance), "
        "\"priority\" (high/medium/low), "
        "\"category\" (infrastructure/feature/docs/security/performance/question). "
        "Respond ONLY with the JSON object, no other text."
    ),
    "commit_message": (
        "You are writing a git commit message following the Conventional Commits specification. "
        "Given a diff, generate a commit message with format: type(scope): description "
        "where type is one of: feat, fix, docs, refactor, chore, test, style, perf, ci, build. "
        "Keep the first line under 72 characters. Add a body if the change is complex. "
        "Respond ONLY with the commit message, no other text."
    ),
    "gh_cli": (
        "You are a GitHub CLI expert. Given a task description, provide the exact "
        "gh CLI command to accomplish it. Use only the gh CLI (not curl, git, or other tools). "
        "Respond ONLY with the command, no explanation or markdown formatting."
    ),
}


# ==============================================================================
# Scoring functions (0-100 each)
# ==============================================================================

def score_pr_description(output: str, expected: dict) -> tuple[float, dict]:
    """Score a PR description response."""
    subscores = {}
    lines = output.strip().split("\n")

    # Title present and non-empty (10 pts)
    title = lines[0].strip() if lines else ""
    title_clean = re.sub(r'^#+\s*', '', title)  # strip markdown headers
    subscores["title_present"] = 10.0 if len(title_clean) > 5 else 0.0

    # Title contains relevant keywords (15 pts)
    title_lower = title_clean.lower()
    keywords = expected.get("title_keywords", [])
    if keywords:
        matches = sum(1 for kw in keywords if kw.lower() in title_lower)
        subscores["title_keywords"] = round(15.0 * matches / len(keywords), 1)
    else:
        subscores["title_keywords"] = 15.0

    # Description is markdown formatted (10 pts)
    body = "\n".join(lines[1:]) if len(lines) > 1 else ""
    has_markdown = bool(re.search(r'[#*`\-\[\]]', body))
    subscores["markdown_format"] = 10.0 if has_markdown else 0.0

    # Description mentions files changed (15 pts)
    must_mention = expected.get("description_must_mention", [])
    if must_mention:
        body_lower = body.lower()
        matches = sum(1 for term in must_mention if term.lower() in body_lower)
        subscores["mentions_changes"] = round(15.0 * matches / len(must_mention), 1)
    else:
        subscores["mentions_changes"] = 15.0

    # Description explains "what" changed (25 pts)
    what_score = 0.0
    if len(body) > 50:
        what_score += 15.0
    elif len(body) > 20:
        what_score += 8.0
    change_words = ["change", "update", "add", "remove", "fix", "move", "replace",
                    "install", "modify", "switch", "migrate", "refactor"]
    if any(w in body.lower() for w in change_words):
        what_score += 10.0
    subscores["explains_what"] = min(25.0, what_score)

    # Description explains "why" (25 pts)
    why_score = 0.0
    why_words = ["because", "since", "to avoid", "to fix", "to prevent", "to enable",
                 "so that", "in order to", "reason", "issue", "problem", "needed",
                 "required", "fails", "broken", "improve", "ensure"]
    if any(w in body.lower() for w in why_words):
        why_score += 15.0
    if len(body) > 100:
        why_score += 10.0
    subscores["explains_why"] = min(25.0, why_score)

    total = sum(subscores.values())
    return round(total, 1), subscores


def score_code_review(output: str, expected: dict) -> tuple[float, dict]:
    """Score a code review response."""
    subscores = {}
    output_lower = output.lower()

    # Bug detected (40 pts)
    expected_bugs = expected.get("bugs", [])
    bug_aliases = {
        "command_injection": ["command injection", "shell injection", "subprocess", "shell=true"],
        "sql_injection": ["sql injection", "sql inject", "string interpolation", "parameterized", "f-string"],
        "xss": ["xss", "cross-site", "unsanitized", "sanitize", "insertadjacenthtml"],
        "path_traversal": ["path traversal", "directory traversal", "../", "path.join"],
        "insecure_deserialization": ["yaml.load", "unsafe", "deserializ", "loader", "safe_load"],
        "resource_leak": ["resource leak", "connection.*close", "not closed", "never closed", "context manager"],
        "off_by_one": ["off.by.one", "boundary", "index", "range", "fence.?post"],
        "hardcoded_credentials": ["hardcod", "credential", "secret", "api.?key", "password.*source", "environment variable"],
        "race_condition": ["race condition", "thread.*safe", "lock", "synchroniz", "atomic", "mutex"],
        "missing_error_handling": ["error.*handl", "ignored.*error", "unchecked", "_ :=", "discard"],
        "nil_dereference": ["nil", "null", "panic", "type.*assert", "dereference"],
        "unhandled_exception": ["exception", "valueerror", "try.*except", "error.*handling", "crash"],
        "type_confusion": ["type.*confus", "none.*check", "null.*check", "type.*error"],
        "missing_auth": ["auth", "middleware", "permission", "access.*control", "unprotected"],
    }

    detected = 0
    for bug in expected_bugs:
        aliases = bug_aliases.get(bug, [bug])
        if any(re.search(a, output_lower) for a in aliases):
            detected += 1
    if expected_bugs:
        subscores["bug_detected"] = round(40.0 * detected / len(expected_bugs), 1)
    else:
        subscores["bug_detected"] = 40.0

    # Correct severity (15 pts)
    expected_severity = expected.get("severity", "").lower()
    severity_words = ["critical", "high", "medium", "low"]
    found_severity = None
    for s in severity_words:
        if s in output_lower:
            found_severity = s
            break
    if found_severity == expected_severity:
        subscores["severity"] = 15.0
    elif found_severity is not None:
        subscores["severity"] = 5.0
    else:
        subscores["severity"] = 0.0

    # Actionable fix suggested (25 pts)
    fix_words = ["instead", "should", "use", "replace", "fix", "recommend", "change to",
                 "parameterize", "sanitize", "validate", "escape", "safe_load"]
    fix_count = sum(1 for w in fix_words if w in output_lower)
    subscores["fix_suggested"] = min(25.0, fix_count * 5.0)

    # No false positives (10 pts) - check for claims of bugs not in expected list
    false_positive_count = 0
    all_bug_types = list(bug_aliases.keys())
    for bug_type in all_bug_types:
        if bug_type in expected_bugs:
            continue
        aliases = bug_aliases[bug_type]
        if any(re.search(a, output_lower) for a in aliases):
            false_positive_count += 1
    subscores["no_false_positives"] = max(0.0, 10.0 - 3.0 * false_positive_count)

    # Clear explanation (10 pts)
    subscores["clear_explanation"] = 10.0 if len(output) > 50 else 5.0

    total = sum(subscores.values())
    return round(min(100.0, total), 1), subscores


def score_issue_triage(output: str, expected: dict) -> tuple[float, dict]:
    """Score an issue triage response."""
    subscores = {}

    # Try to extract JSON from response (with proper bracket-depth matching)
    parsed = None
    try:
        parsed = json.loads(output.strip())
    except json.JSONDecodeError:
        # Find JSON with proper bracket matching (handles nested objects/arrays)
        depth = 0
        start = -1
        for i, ch in enumerate(output):
            if ch == '{':
                if depth == 0:
                    start = i
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0 and start >= 0:
                    try:
                        parsed = json.loads(output[start:i+1])
                        break
                    except json.JSONDecodeError:
                        start = -1

    if parsed is None:
        # Fall back to keyword matching
        output_lower = output.lower()
        expected_labels = [l.lower() for l in expected.get("labels", [])]
        matched = sum(1 for l in expected_labels if l in output_lower)
        subscores["correct_label"] = round(30.0 * min(1, matched), 1)
        subscores["all_labels"] = round(20.0 * matched / max(1, len(expected_labels)), 1)
        subscores["no_incorrect"] = 10.0
        subscores["priority_match"] = 15.0 if expected.get("priority", "").lower() in output_lower else 0.0
        subscores["category_match"] = 15.0 if expected.get("category", "").lower() in output_lower else 0.0
    else:
        response_labels = [l.lower() for l in parsed.get("labels", [])]
        expected_labels = [l.lower() for l in expected.get("labels", [])]

        correct = [l for l in response_labels if l in expected_labels]
        subscores["correct_label"] = 30.0 if correct else 0.0

        if expected_labels:
            subscores["all_labels"] = round(20.0 * len(correct) / len(expected_labels), 1)
        else:
            subscores["all_labels"] = 20.0

        incorrect = [l for l in response_labels if l not in expected_labels]
        subscores["no_incorrect"] = max(0.0, 20.0 - 5.0 * len(incorrect))

        resp_priority = parsed.get("priority", "").lower()
        subscores["priority_match"] = 15.0 if resp_priority == expected.get("priority", "").lower() else 0.0

        resp_category = parsed.get("category", "").lower()
        subscores["category_match"] = 15.0 if resp_category == expected.get("category", "").lower() else 0.0

    total = sum(subscores.values())
    return round(min(100.0, total), 1), subscores


def score_commit_message(output: str, expected: dict) -> tuple[float, dict]:
    """Score a commit message response."""
    subscores = {}
    output = output.strip()
    # Strip markdown code fences wrapping entire response
    fence_match = re.match(r'^```\w*\s*\n(.*?)```\s*$', output, re.DOTALL)
    if fence_match:
        output = fence_match.group(1).strip()
    first_line = output.split("\n")[0].strip()
    # Also strip inline code fences
    first_line = re.sub(r'^```\w*\s*', '', first_line)
    first_line = re.sub(r'```$', '', first_line).strip()
    if not first_line and len(output.split("\n")) > 1:
        first_line = output.split("\n")[1].strip()

    # Conventional commit format (25 pts)
    conv_pattern = r'^(feat|fix|docs|refactor|chore|test|style|perf|ci|build)(\(.+?\))?:\s*.+'
    is_conventional = bool(re.match(conv_pattern, first_line, re.IGNORECASE))
    subscores["conventional_format"] = 25.0 if is_conventional else 0.0

    # Correct type (25 pts)
    expected_type = expected.get("type", "").lower()
    type_match = re.match(r'^(\w+)', first_line.lower())
    if type_match and type_match.group(1) == expected_type:
        subscores["correct_type"] = 25.0
    elif type_match and type_match.group(1) in ["feat", "fix", "docs", "refactor", "chore"]:
        subscores["correct_type"] = 10.0
    else:
        subscores["correct_type"] = 0.0

    # Relevant scope (15 pts)
    if expected.get("scope_relevant"):
        keywords = expected.get("keywords", [])
        output_lower = output.lower()
        matches = sum(1 for kw in keywords if kw.lower() in output_lower)
        subscores["relevant_scope"] = round(15.0 * matches / max(1, len(keywords)), 1)
    else:
        subscores["relevant_scope"] = 15.0

    # Concise first line (15 pts)
    if len(first_line) <= 72:
        subscores["concise"] = 15.0
    elif len(first_line) <= 100:
        subscores["concise"] = 8.0
    else:
        subscores["concise"] = 0.0

    # Body for complex diffs (20 pts)
    body = "\n".join(output.split("\n")[1:]).strip()
    subscores["body_rationale"] = 20.0 if body else 10.0

    total = sum(subscores.values())
    return round(min(100.0, total), 1), subscores


def score_gh_cli(output: str, expected: dict) -> tuple[float, dict]:
    """Score a gh CLI command response."""
    subscores = {}
    output = output.strip()
    # Extract command from markdown code blocks if present
    code_match = re.search(r'```(?:\w+)?\s*\n?(.*?)\n?```', output, re.DOTALL)
    if code_match:
        output = code_match.group(1).strip()
    # Take first line that starts with 'gh'
    for line in output.split("\n"):
        line = line.strip()
        if line.startswith("gh "):
            output = line
            break

    output_lower = output.lower()

    # Correct base command (30 pts)
    pattern = expected.get("command_pattern", "")
    subscores["correct_command"] = 30.0 if pattern.lower() in output_lower else 0.0

    # Required flags present (30 pts)
    required = expected.get("required_flags", [])
    if required:
        found = sum(1 for f in required if f.lower() in output_lower)
        subscores["required_flags"] = round(30.0 * found / len(required), 1)
    else:
        subscores["required_flags"] = 30.0

    # No invalid/forbidden content (15 pts)
    must_not = expected.get("must_not_contain", [])
    violations = sum(1 for f in must_not if f.lower() in output_lower)
    subscores["no_forbidden"] = max(0.0, 15.0 - 5.0 * violations)

    # Syntactically valid - starts with gh (10 pts)
    subscores["valid_syntax"] = 10.0 if output.startswith("gh ") else 0.0

    # Uses valid flags (15 pts) - check flags in output against valid_flags list
    valid_flags_list = expected.get("valid_flags", [])
    if valid_flags_list:
        # Extract all --flags from the output
        output_flags = re.findall(r'--[\w-]+', output)
        valid_set = {f.lower() for f in valid_flags_list if f.startswith("--")}
        if output_flags and valid_set:
            invalid = [f for f in output_flags if f.lower() not in valid_set]
            subscores["valid_flags"] = max(0.0, 15.0 - 5.0 * len(invalid))
        else:
            subscores["valid_flags"] = 15.0
    else:
        subscores["valid_flags"] = 15.0

    total = sum(subscores.values())
    return round(min(100.0, total), 1), subscores


SCORERS = {
    "pr_description": score_pr_description,
    "code_review": score_code_review,
    "issue_triage": score_issue_triage,
    "commit_message": score_commit_message,
    "gh_cli": score_gh_cli,
}


# ==============================================================================
# API interaction
# ==============================================================================

async def run_test_case(
    session: aiohttp.ClientSession,
    base_url: str,
    model: str,
    test_case: dict,
    timeout: int,
) -> TestResult:
    """Run a single test case and score the response."""
    category = test_case["category"]
    system_prompt = SYSTEM_PROMPTS.get(category, "")
    test_input = test_case["input"]

    # Build user message based on category
    if category == "pr_description":
        user_msg = f"Here is the git diff:\n\n{test_input['diff']}"
        if test_input.get("context"):
            user_msg += f"\n\nContext: {test_input['context']}"
    elif category == "code_review":
        user_msg = f"Review this {test_input.get('language', 'code')} code from {test_input.get('file_path', 'unknown')}:\n\n{test_input['code']}"
    elif category == "issue_triage":
        user_msg = f"Title: {test_input['title']}\n\nBody: {test_input['body']}"
    elif category == "commit_message":
        user_msg = f"Generate a commit message for this diff:\n\n{test_input['diff']}"
        if test_input.get("context"):
            user_msg += f"\n\nContext: {test_input['context']}"
    elif category == "gh_cli":
        user_msg = test_input["task"]
    else:
        user_msg = json.dumps(test_input)

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_msg},
    ]

    url = f"{base_url}/chat/completions"
    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": test_case.get("max_tokens", 500),
        "temperature": 0.3,
        "stream": False,
    }

    t_start = time.perf_counter()
    try:
        async with session.post(
            url,
            json=payload,
            timeout=aiohttp.ClientTimeout(total=timeout),
        ) as resp:
            if resp.status != 200:
                body = await resp.text()
                return TestResult(
                    test_case_id=test_case["id"],
                    category=category,
                    error=f"HTTP {resp.status}: {body[:200]}",
                )

            data = await resp.json()
            t_end = time.perf_counter()

            content = data["choices"][0]["message"]["content"]
            latency = (t_end - t_start) * 1000

            scorer = SCORERS.get(category)
            if scorer is None:
                return TestResult(
                    test_case_id=test_case["id"],
                    category=category,
                    error=f"No scorer for category: {category}",
                )

            score, subscores = scorer(content, test_case.get("expected", {}))

            return TestResult(
                test_case_id=test_case["id"],
                category=category,
                score=score,
                subscores=subscores,
                model_output=content,
                latency_ms=round(latency, 2),
            )

    except asyncio.TimeoutError:
        return TestResult(
            test_case_id=test_case["id"], category=category, error="timeout"
        )
    except aiohttp.ClientError as e:
        return TestResult(
            test_case_id=test_case["id"], category=category, error=str(e)
        )
    except Exception as e:
        return TestResult(
            test_case_id=test_case["id"], category=category, error=f"unexpected: {e}"
        )


# ==============================================================================
# Aggregation and output
# ==============================================================================

def summarize_by_category(results: list[TestResult]) -> dict[str, CategorySummary]:
    """Group results by category and compute summary statistics."""
    by_cat: dict[str, list[TestResult]] = {}
    for r in results:
        by_cat.setdefault(r.category, []).append(r)

    summaries = {}
    for cat, cat_results in sorted(by_cat.items()):
        scores = [r.score for r in cat_results if r.error is None]
        failed = sum(1 for r in cat_results if r.error is not None)

        summaries[cat] = CategorySummary(
            category=cat,
            mean_score=round(statistics.mean(scores), 1) if scores else 0.0,
            median_score=round(statistics.median(scores), 1) if scores else 0.0,
            min_score=round(min(scores), 1) if scores else 0.0,
            max_score=round(max(scores), 1) if scores else 0.0,
            total_cases=len(cat_results),
            failed_cases=failed,
        )
    return summaries


def print_summary(model: str, summaries: dict[str, CategorySummary]) -> str:
    """Print and return a formatted summary table."""
    headers = ["Category", "Mean", "Median", "Min", "Max", "Cases", "Failed"]
    rows = []
    all_means = []
    for cat, s in sorted(summaries.items()):
        rows.append([
            cat, f"{s.mean_score:.1f}", f"{s.median_score:.1f}",
            f"{s.min_score:.1f}", f"{s.max_score:.1f}",
            s.total_cases, s.failed_cases,
        ])
        if s.mean_score > 0:
            all_means.append(s.mean_score)

    overall = round(statistics.mean(all_means), 1) if all_means else 0.0
    rows.append(["OVERALL", f"{overall:.1f}", "", "", "", "", ""])

    table = tabulate(rows, headers=headers, tablefmt="grid")
    header = f"\nModel: {model}"
    output = f"{header}\n{table}\n"
    print(output)
    return output


# ==============================================================================
# Main
# ==============================================================================

async def main():
    parser = argparse.ArgumentParser(
        description="GitHub Operations Quality Benchmark for LLMs"
    )
    parser.add_argument(
        "--base-url", required=True,
        help="Base URL for OpenAI-compatible API (e.g., http://localhost:8000/v1)",
    )
    parser.add_argument("--model", required=True, help="Model name/ID to benchmark")
    parser.add_argument(
        "--testdata-dir", default="github_ops_testdata",
        help="Path to test data directory (default: github_ops_testdata)",
    )
    parser.add_argument("--output", required=True, help="Output JSON file path")
    parser.add_argument(
        "--categories", default="pr_description,code_review,issue_triage,commit_message,gh_cli",
        help="Comma-separated categories to benchmark (default: all)",
    )
    parser.add_argument(
        "--timeout", type=int, default=120,
        help="Per-request timeout in seconds (default: 120)",
    )
    parser.add_argument(
        "--concurrency", type=int, default=4,
        help="Max concurrent requests (default: 4)",
    )
    args = parser.parse_args()

    categories = [c.strip() for c in args.categories.split(",")]
    testdata_dir = Path(args.testdata_dir)

    # Load test cases
    all_cases = []
    for cat in categories:
        cat_file = testdata_dir / f"{cat}.json"
        if not cat_file.exists():
            print(f"WARNING: Test data not found: {cat_file}", file=sys.stderr)
            continue
        with open(cat_file) as f:
            cases = json.load(f)
        all_cases.extend(cases)
        print(f"Loaded {len(cases)} test cases for {cat}")

    if not all_cases:
        print("ERROR: No test cases loaded", file=sys.stderr)
        sys.exit(1)

    print(f"\nBenchmark: {args.model}")
    print(f"Total test cases: {len(all_cases)}")
    print(f"API: {args.base_url}")
    print("-" * 60)

    # Run all test cases with bounded concurrency
    semaphore = asyncio.Semaphore(args.concurrency)
    connector = aiohttp.TCPConnector(limit=args.concurrency + 5)

    async def bounded_run(session, case):
        async with semaphore:
            return await run_test_case(session, args.base_url, args.model, case, args.timeout)

    t_start = time.perf_counter()
    async with aiohttp.ClientSession(connector=connector) as session:
        tasks = [bounded_run(session, case) for case in all_cases]
        results = await asyncio.gather(*tasks)
    t_end = time.perf_counter()

    total_duration = t_end - t_start

    for r in results:
        if r.error:
            print(f"  ERROR [{r.test_case_id}]: {r.error}")

    summaries = summarize_by_category(results)
    table_str = print_summary(args.model, summaries)

    all_means = [s.mean_score for s in summaries.values() if s.mean_score > 0]
    overall_score = round(statistics.mean(all_means), 1) if all_means else 0.0

    output_data = {
        "metadata": {
            "model": args.model,
            "base_url": args.base_url,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "total_test_cases": len(all_cases),
            "total_duration_s": round(total_duration, 2),
            "categories": categories,
        },
        "summary": {
            "overall_score": overall_score,
            "by_category": {
                cat: asdict(s) for cat, s in summaries.items()
            },
        },
        "results": [asdict(r) for r in results],
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"\nResults saved to: {output_path}")
    print(f"Overall score: {overall_score}/100")
    print(f"Duration: {total_duration:.1f}s")

    table_path = output_path.with_suffix(".txt")
    with open(table_path, "w") as f:
        f.write(table_str)


if __name__ == "__main__":
    asyncio.run(main())
