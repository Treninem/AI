#!/usr/bin/env python3
"""Compare AuroraFox Knowledge benchmark reports on comparable machines.

Absolute hosted-runner timings are intentionally not treated as universal gates.
This comparator only emits relative regression failures when platform/runtime,
profile, and case identity match.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline")
    parser.add_argument("candidate")
    parser.add_argument("--output", default="knowledge-comparison.json")
    parser.add_argument("--import-regression", type=float, default=1.50)
    parser.add_argument("--search-regression", type=float, default=1.75)
    parser.add_argument("--memory-regression", type=float, default=1.50)
    parser.add_argument("--storage-regression", type=float, default=1.35)
    parser.add_argument("--fail-on-regression", action="store_true")
    return parser.parse_args()


def load(path: str) -> dict[str, Any]:
    value = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"report is not an object: {path}")
    return value


def comparable(a: dict[str, Any], b: dict[str, Any]) -> tuple[bool, list[str]]:
    reasons: list[str] = []
    if a.get("profile") != b.get("profile"):
        reasons.append("profile")
    am = a.get("machine", {})
    bm = b.get("machine", {})
    for key in ("platform", "machine", "godot"):
        if am.get(key) != bm.get(key):
            reasons.append(f"machine.{key}")
    return not reasons, reasons


def case_key(case: dict[str, Any]) -> tuple[str, float]:
    return str(case.get("format", "")), float(case.get("target_size_mb", 0.0))


def safe_ratio(candidate: Any, baseline: Any) -> float | None:
    try:
        base = float(baseline)
        cand = float(candidate)
    except (TypeError, ValueError):
        return None
    if base <= 0.0:
        return None
    return cand / base


def main() -> int:
    args = parse_args()
    base = load(args.baseline)
    cand = load(args.candidate)
    is_comparable, mismatch = comparable(base, cand)
    result: dict[str, Any] = {
        "schema_version": 1,
        "comparable": is_comparable,
        "mismatch": mismatch,
        "baseline_sha": base.get("git_sha", ""),
        "candidate_sha": cand.get("git_sha", ""),
        "regressions": [],
        "comparisons": [],
    }
    if not is_comparable:
        pathlib.Path(args.output).write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result))
        return 0

    base_cases = {case_key(case): case for case in base.get("knowledge_cases", [])}
    for candidate_case in cand.get("knowledge_cases", []):
        key = case_key(candidate_case)
        baseline_case = base_cases.get(key)
        if baseline_case is None:
            continue
        metrics = {
            "import_duration_ms": safe_ratio(
                candidate_case.get("import", {}).get("import_duration_ms"),
                baseline_case.get("import", {}).get("import_duration_ms"),
            ),
            "search_p95_ms": safe_ratio(
                candidate_case.get("import", {}).get("search", {}).get("p95_ms"),
                baseline_case.get("import", {}).get("search", {}).get("p95_ms"),
            ),
            "peak_rss_delta_bytes": safe_ratio(
                candidate_case.get("peak_rss_delta_bytes"), baseline_case.get("peak_rss_delta_bytes")
            ),
            "storage_amplification": safe_ratio(
                candidate_case.get("storage_amplification_vs_dataset"),
                baseline_case.get("storage_amplification_vs_dataset"),
            ),
        }
        thresholds = {
            "import_duration_ms": args.import_regression,
            "search_p95_ms": args.search_regression,
            "peak_rss_delta_bytes": args.memory_regression,
            "storage_amplification": args.storage_regression,
        }
        row = {"format": key[0], "size_mb": key[1], "ratios": metrics}
        result["comparisons"].append(row)
        for metric, value in metrics.items():
            if value is not None and value > thresholds[metric]:
                result["regressions"].append(
                    {
                        "format": key[0],
                        "size_mb": key[1],
                        "metric": metric,
                        "ratio": value,
                        "threshold": thresholds[metric],
                    }
                )

    # Correctness never gets a performance waiver: candidate hard gates may not
    # become worse than a passing baseline even if timings are noisy.
    if bool(base.get("hard_gates", {}).get("passed", False)) and not bool(
        cand.get("hard_gates", {}).get("passed", False)
    ):
        result["regressions"].append({"metric": "hard_gates", "reason": "passing baseline became failing"})

    result["regression_detected"] = bool(result["regressions"])
    pathlib.Path(args.output).write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({"comparable": True, "regressions": result["regressions"]}))
    if args.fail_on_regression and result["regression_detected"]:
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
