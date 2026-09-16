#!/usr/bin/env python3
"""Measure KnowledgeStore search scaling with deterministic JSONL datasets."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any

import run_knowledge_benchmark as runner


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--sizes-mb", default="1,2,4")
    parser.add_argument("--timeout-seconds", type=int, default=600)
    parser.add_argument("--report", default="artifacts/knowledge-performance/search-scaling.json")
    return parser.parse_args()


def parse_sizes(raw: str) -> list[int]:
    values = sorted({int(value.strip()) for value in raw.split(",") if value.strip()})
    if not values or any(value <= 0 for value in values):
        raise ValueError("sizes must be positive integers")
    return values


def selected_search_p95(result: dict[str, Any]) -> float:
    search = result.get("search")
    if not isinstance(search, dict):
        return 0.0
    selected = {"exact_rare", "common", "multiple_tokens", "russian", "mixed_ru_en"}
    values: list[float] = []
    for case in search.get("cases", []) if isinstance(search.get("cases"), list) else []:
        if isinstance(case, dict) and str(case.get("name", "")) in selected:
            values.append(float(case.get("p95_ms", 0.0) or 0.0))
    return max(values) if values else 0.0


def pair_findings(results: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = sorted(
        (row for row in results if row.get("ok")),
        key=lambda row: float((row.get("dataset") or {}).get("size_mb", 0.0)),
    )
    findings: list[dict[str, Any]] = []
    for left, right in zip(rows, rows[1:]):
        size1 = float((left.get("dataset") or {}).get("size_mb", 0.0))
        size2 = float((right.get("dataset") or {}).get("size_mb", 0.0))
        if size1 <= 0 or not (1.8 <= size2 / size1 <= 2.2):
            continue
        p1 = selected_search_p95(left)
        p2 = selected_search_p95(right)
        ratio = (p2 / p1) if p1 > 0 else 0.0
        findings.append(
            {
                "from_mb": size1,
                "to_mb": size2,
                "selected_search_p95_ms_from": p1,
                "selected_search_p95_ms_to": p2,
                "time_ratio": ratio,
                "suspected_superlinear_search": ratio >= 3.5,
            }
        )
    return findings


def main() -> int:
    args = parse_args()
    sizes = parse_sizes(args.sizes_mb)
    repo = Path.cwd().resolve()
    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    log_dir = report_path.parent / "search-scaling-logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    results: list[dict[str, Any]] = []
    hard_errors: list[dict[str, Any]] = []
    for size_mb in sizes:
        user_root = Path(tempfile.mkdtemp(prefix=f"aurora-search-{size_mb}mb-"))
        try:
            result = runner.run_godot_case(
                args.godot,
                repo,
                user_root,
                {"scenario": "import_jsonl", "target_mb": size_mb},
                args.timeout_seconds,
                log_dir,
            )
        finally:
            shutil.rmtree(user_root, ignore_errors=True)
        result["selected_search_p95_ms"] = selected_search_p95(result)
        results.append(result)
        if not result.get("ok"):
            hard_errors.append({"size_mb": size_mb, "error": result.get("error", "case failed")})

    findings = pair_findings(results)
    suspected = any(bool(row.get("suspected_superlinear_search")) for row in findings)
    report = {
        "schema": "aurorafox_knowledge_search_scaling_v1",
        "platform_runtime_identity": runner.comparable_identity(),
        "self_reliance_contract": {
            "network_required": False,
            "external_runtime_required": False,
            "ollama_required": False,
        },
        "hard_correctness": {
            "passed": not hard_errors,
            "errors": hard_errors,
        },
        "relative_performance": {
            "n_2n_4n": findings,
            "suspected_superlinear_search": suspected,
            "absolute_ci_timings_are_informational": True,
        },
        "results": results,
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"report": str(report_path), "hard_passed": not hard_errors, "suspected_superlinear_search": suspected}))
    return 0 if not hard_errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
