#!/usr/bin/env python3
"""Compare two AuroraFox knowledge benchmark reports only when identities match."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

IDENTITY_FIELDS = ("os", "machine", "cpu_count", "runner_os", "runner_arch")
THROUGHPUT_MIN_RATIO = 0.75
LATENCY_MAX_RATIO = 1.50
RSS_MAX_RATIO = 1.35


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline")
    parser.add_argument("candidate")
    parser.add_argument("--output", default="")
    return parser.parse_args()


def load(path: str) -> dict[str, Any]:
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict) or value.get("schema") != "aurorafox_knowledge_performance_v1":
        raise ValueError(f"unsupported report: {path}")
    return value


def comparable_identity(baseline: dict[str, Any], candidate: dict[str, Any]) -> tuple[bool, list[str]]:
    left = baseline.get("platform_runtime_identity", {})
    right = candidate.get("platform_runtime_identity", {})
    mismatches = []
    for field in IDENTITY_FIELDS:
        if left.get(field) != right.get(field):
            mismatches.append(field)
    return not mismatches, mismatches


def case_key(row: dict[str, Any]) -> tuple[Any, ...]:
    case = row.get("case", {}) if isinstance(row.get("case"), dict) else {}
    dataset = row.get("dataset", {}) if isinstance(row.get("dataset"), dict) else {}
    return (
        row.get("scenario"),
        row.get("parent_scenario"),
        int(case.get("target_mb", row.get("target_mb", 0)) or 0),
        int(case.get("count", row.get("source_count", row.get("requested_count", 0))) or 0),
        int(case.get("source_kb", row.get("source_size_kb", 0)) or 0),
        int(dataset.get("bytes", 0) or 0),
    )


def max_search_p95(row: dict[str, Any]) -> float:
    search = row.get("search", {})
    cases = search.get("cases", []) if isinstance(search, dict) else []
    values = [float(case.get("p95_ms", 0.0)) for case in cases if isinstance(case, dict)]
    if row.get("search_latency_ms") is not None:
        values.append(float(row.get("search_latency_ms", 0.0)))
    return max(values, default=0.0)


def compare_metric(name: str, baseline: float, candidate: float, direction: str, threshold: float) -> dict[str, Any] | None:
    if baseline <= 0 or candidate <= 0:
        return None
    ratio = candidate / baseline
    regression = ratio < threshold if direction == "higher_better" else ratio > threshold
    return {
        "metric": name,
        "baseline": baseline,
        "candidate": candidate,
        "candidate_to_baseline_ratio": ratio,
        "direction": direction,
        "threshold": threshold,
        "regression": regression,
    }


def compare_reports(baseline: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    comparable, mismatches = comparable_identity(baseline, candidate)
    output: dict[str, Any] = {
        "schema": "aurorafox_knowledge_performance_comparison_v1",
        "comparable": comparable,
        "identity_mismatches": mismatches,
        "thresholds": {
            "throughput_candidate_to_baseline_min": THROUGHPUT_MIN_RATIO,
            "latency_candidate_to_baseline_max": LATENCY_MAX_RATIO,
            "rss_candidate_to_baseline_max": RSS_MAX_RATIO,
        },
        "cases": [],
        "regressions": [],
    }
    if not comparable:
        output["passed"] = True
        output["comparison_skipped"] = True
        output["reason"] = "machine/platform identity differs; absolute cross-run timings are not comparable"
        return output

    base_rows = {case_key(row): row for row in baseline.get("results", []) if isinstance(row, dict)}
    cand_rows = {case_key(row): row for row in candidate.get("results", []) if isinstance(row, dict)}
    for key in sorted(set(base_rows).intersection(cand_rows), key=str):
        left, right = base_rows[key], cand_rows[key]
        metrics = []
        for metric in (
            compare_metric("records_per_sec", float(left.get("records_per_sec", 0.0)), float(right.get("records_per_sec", 0.0)), "higher_better", THROUGHPUT_MIN_RATIO),
            compare_metric("mb_per_sec", float(left.get("mb_per_sec", 0.0)), float(right.get("mb_per_sec", 0.0)), "higher_better", THROUGHPUT_MIN_RATIO),
            compare_metric("sources_per_sec", float(left.get("sources_per_sec", 0.0)), float(right.get("sources_per_sec", 0.0)), "higher_better", THROUGHPUT_MIN_RATIO),
            compare_metric("search_p95_ms", max_search_p95(left), max_search_p95(right), "lower_better", LATENCY_MAX_RATIO),
            compare_metric("peak_rss_bytes", float(left.get("peak_rss_bytes", 0.0)), float(right.get("peak_rss_bytes", 0.0)), "lower_better", RSS_MAX_RATIO),
            compare_metric("restart_load_search_ms", float(left.get("restart_load_search_ms", 0.0)), float(right.get("restart_load_search_ms", 0.0)), "lower_better", LATENCY_MAX_RATIO),
            compare_metric("removal_duration_ms", float(left.get("removal_duration_ms", 0.0)), float(right.get("removal_duration_ms", 0.0)), "lower_better", LATENCY_MAX_RATIO),
            compare_metric("rollback_duration_ms", float(left.get("rollback_duration_ms", 0.0)), float(right.get("rollback_duration_ms", 0.0)), "lower_better", LATENCY_MAX_RATIO),
        ):
            if metric is not None:
                metrics.append(metric)
                if metric["regression"]:
                    output["regressions"].append({"case": list(key), **metric})
        output["cases"].append({"case": list(key), "metrics": metrics})
    output["comparison_skipped"] = False
    output["passed"] = not output["regressions"]
    output["matched_cases"] = len(output["cases"])
    return output


def main() -> int:
    args = parse_args()
    try:
        baseline = load(args.baseline)
        candidate = load(args.candidate)
        output = compare_reports(baseline, candidate)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"passed": False, "error": str(exc)}))
        return 2
    rendered = json.dumps(output, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).write_text(rendered, encoding="utf-8")
    print(rendered)
    return 0 if output.get("passed") else 1


if __name__ == "__main__":
    raise SystemExit(main())
