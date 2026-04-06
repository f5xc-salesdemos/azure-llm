#!/usr/bin/env python3
"""
Compare GitHub Operations benchmark results across multiple models.

Reads all github_ops_*.json result files from a directory and produces
a markdown comparison table with per-category and overall scores.
"""

import argparse
import json
import sys
from pathlib import Path

from tabulate import tabulate


def load_results(results_dir: Path) -> list[dict]:
    """Load all github_ops result JSON files from a directory."""
    results = []
    for f in sorted(results_dir.glob("github_ops_*.json")):
        with open(f) as fh:
            data = json.load(fh)
        data["_file"] = f.name
        results.append(data)
    return results


def build_comparison(results: list[dict]) -> str:
    """Build a markdown comparison table."""
    if not results:
        return "No results found.\n"

    # Collect all categories
    all_cats = set()
    for r in results:
        all_cats.update(r.get("summary", {}).get("by_category", {}).keys())
    cats = sorted(all_cats)

    # Build table
    headers = ["Model"] + [c.replace("_", " ").title() for c in cats] + ["Overall"]
    rows = []

    for r in results:
        model = r.get("metadata", {}).get("model", "unknown")
        # Shorten model name for display
        short_name = model.split("/")[-1] if "/" in model else model
        row = [short_name]

        by_cat = r.get("summary", {}).get("by_category", {})
        for cat in cats:
            cat_data = by_cat.get(cat, {})
            mean = cat_data.get("mean_score", 0)
            row.append(f"{mean:.1f}")

        overall = r.get("summary", {}).get("overall_score", 0)
        row.append(f"{overall:.1f}")
        rows.append(row)

    # Sort by overall score descending
    rows.sort(key=lambda r: float(r[-1]), reverse=True)

    table = tabulate(rows, headers=headers, tablefmt="github")

    # Build full report
    lines = [
        "# GitHub Operations Quality Benchmark — Model Comparison",
        "",
        f"**Models tested:** {len(results)}",
        "",
        "## Scores (0–100, higher is better)",
        "",
        table,
        "",
        "## Details",
        "",
    ]

    # Per-model details
    for r in results:
        model = r.get("metadata", {}).get("model", "unknown")
        meta = r.get("metadata", {})
        lines.append(f"### {model}")
        lines.append(f"- Duration: {meta.get('total_duration_s', 0):.1f}s")
        lines.append(f"- Test cases: {meta.get('total_test_cases', 0)}")
        lines.append(f"- Overall: **{r.get('summary', {}).get('overall_score', 0):.1f}**/100")
        lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Compare GitHub Operations benchmark results across models"
    )
    parser.add_argument(
        "--results-dir", required=True,
        help="Directory containing github_ops_*.json result files",
    )
    parser.add_argument(
        "--output", default=None,
        help="Output markdown file (default: stdout + comparison.md in results dir)",
    )
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    if not results_dir.exists():
        print(f"ERROR: Results directory not found: {results_dir}", file=sys.stderr)
        sys.exit(1)

    results = load_results(results_dir)
    if not results:
        print(f"ERROR: No github_ops_*.json files in {results_dir}", file=sys.stderr)
        sys.exit(1)

    report = build_comparison(results)
    print(report)

    output_path = Path(args.output) if args.output else results_dir / "comparison.md"
    with open(output_path, "w") as f:
        f.write(report)
    print(f"\nReport saved to: {output_path}")


if __name__ == "__main__":
    main()
