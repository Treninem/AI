#!/usr/bin/env python3
"""Validate AuroraFox Knowledge/Memory performance reports.

Absolute GitHub-hosted-runner timings remain informational. The gate fails on
hard correctness/self-reliance regressions and on reproducible N->2N scaling
that the benchmark already classified as a quadratic/superlinear blocker.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("reports", nargs="+", help="Machine-readable benchmark reports")
    parser.add_argument("--output", default="", help="Optional JSON gate summary")
    parser.add_argument(
        "--enforce-performance",
        action="store_true",
        help="Fail on reproducible quadratic/superlinear findings",
    )
    parser.add_argument(
        "--max-search-p95-ms",
        type=float,
        default=0.0,
        help="Explicit absolute search p95 limit for a measured target machine; zero leaves hosted-runner timing informational",
    )
    return parser.parse_args()


def _load(path: str) -> dict[str, Any]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"report is not an object: {path}")
    return data


def evaluate_report(report: dict[str, Any], path: str = "", max_search_p95_ms: float = 0.0) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    schema = str(report.get("schema", ""))

    hard = report.get("hard_correctness")
    if isinstance(hard, dict) and not bool(hard.get("passed", False)):
        errors.append("hard correctness gate failed")
    elif "hard_correctness" in report and not isinstance(hard, dict):
        errors.append("hard correctness section malformed")

    self_reliance = report.get("self_reliance_contract")
    if isinstance(self_reliance, dict):
        for key in ("network_required", "external_runtime_required", "ollama_required"):
            if bool(self_reliance.get(key, True)):
                errors.append(f"self-reliance regression: {key}=true")

    relative = report.get("relative_performance")
    blocker_fields: list[str] = []
    if isinstance(relative, dict):
        for key in (
            "suspected_quadratic",
            "suspected_quadratic_write",
            "suspected_quadratic_registry",
            "suspected_superlinear_search",
        ):
            if bool(relative.get(key, False)):
                blocker_fields.append(key)

    # Search absolute latency is runner-dependent, but retain a visible risk
    # summary rather than silently normalizing it with larger timeouts.
    max_search_p95 = 0.0
    search_case_count = 0
    for result in report.get("results", []) if isinstance(report.get("results"), list) else []:
        if not isinstance(result, dict):
            continue
        search = result.get("search")
        if not isinstance(search, dict):
            continue
        for case in search.get("cases", []) if isinstance(search.get("cases"), list) else []:
            if isinstance(case, dict):
                search_case_count += 1
                max_search_p95 = max(max_search_p95, float(case.get("p95_ms", 0.0) or 0.0))
    if max_search_p95_ms > 0:
        if search_case_count == 0 or max_search_p95 <= 0:
            blocker_fields.append("search_p95_missing")
        elif max_search_p95 > max_search_p95_ms:
            blocker_fields.append("search_p95_exceeded")
    if max_search_p95 >= 1000.0:
        warnings.append(
            f"informational CI search latency >=1s (max p95={max_search_p95:.3f} ms); "
            "compare only on matching runner identity"
        )

    return {
        "path": path,
        "schema": schema,
        "correctness_passed": not errors,
        "performance_blockers": blocker_fields,
        "max_search_p95_ms": max_search_p95,
        "absolute_search_limit_ms": max_search_p95_ms,
        "search_case_count": search_case_count,
        "errors": errors,
        "warnings": warnings,
    }


def main() -> int:
    args = parse_args()
    if not math.isfinite(args.max_search_p95_ms) or args.max_search_p95_ms < 0:
        raise SystemExit("--max-search-p95-ms must be a finite nonnegative number")
    evaluations: list[dict[str, Any]] = []
    load_errors: list[str] = []
    for path in args.reports:
        try:
            evaluations.append(evaluate_report(_load(path), path, args.max_search_p95_ms))
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            load_errors.append(f"{path}: {exc}")

    correctness_passed = not load_errors and all(row["correctness_passed"] for row in evaluations)
    blockers = [
        {"path": row["path"], "fields": row["performance_blockers"]}
        for row in evaluations
        if row["performance_blockers"]
    ]
    performance_passed = not blockers
    performance_enforced = bool(args.enforce_performance or args.max_search_p95_ms > 0)
    passed = correctness_passed and (performance_passed or not performance_enforced)
    summary = {
        "schema": "aurorafox_knowledge_performance_gate_v1",
        "passed": passed,
        "correctness_passed": correctness_passed,
        "performance_passed": performance_passed,
        "performance_enforced": performance_enforced,
        "absolute_latency_enforced": bool(args.max_search_p95_ms > 0),
        "absolute_search_limit_ms": args.max_search_p95_ms,
        "load_errors": load_errors,
        "blockers": blockers,
        "reports": evaluations,
        "rule": "hosted-runner absolute timings are informational unless --max-search-p95-ms is supplied for target-machine acceptance; reproducible N->2N near-4x scaling is blocking when performance is enforced",
    }
    if args.output:
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
