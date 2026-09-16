#!/usr/bin/env python3
"""Measure AuroraFox persistent semantic-memory scaling on real MemoryStore.

Uses the existing isolated Godot stress harness and reports write/index/search/
restart scaling plus raw and baseline-adjusted process RSS. Performance findings
are recorded here; validate_performance_report.py decides whether CI enforces them.

`MemoryStore.reindex_semantic()` is also an explicit persistence boundary: it
flushes pending canonical memory/knowledge JSON before rebuilding vectors. The
blocking N->2N->4N ratio therefore uses learn-loop + reindex/flush duration so
coalesced persistence cannot make the benchmark appear faster by merely moving
I/O outside the measured durable path.
"""
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
    parser.add_argument("--counts", default="125,250,500")
    parser.add_argument("--timeout-seconds", type=int, default=600)
    parser.add_argument("--report", default="artifacts/knowledge-performance/memory-scaling.json")
    return parser.parse_args()


def parse_counts(raw: str) -> list[int]:
    values = sorted({int(value.strip()) for value in raw.split(",") if value.strip()})
    if not values or any(value <= 0 for value in values):
        raise ValueError("counts must be positive integers")
    return values


def pair_findings(results: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = sorted(
        (row for row in results if row.get("ok")),
        key=lambda row: int(row.get("records_requested", 0)),
    )
    findings: list[dict[str, Any]] = []
    for left, right in zip(rows, rows[1:]):
        n1 = int(left.get("records_requested", 0))
        n2 = int(right.get("records_requested", 0))
        if n1 <= 0 or n2 != n1 * 2:
            continue
        learn1 = float(left.get("write_duration_ms", 0.0) or 0.0)
        learn2 = float(right.get("write_duration_ms", 0.0) or 0.0)
        index1 = float(left.get("semantic_index_build_ms", 0.0) or 0.0)
        index2 = float(right.get("semantic_index_build_ms", 0.0) or 0.0)
        durable1 = learn1 + index1
        durable2 = learn2 + index2
        durable_ratio = (durable2 / durable1) if durable1 > 0 else 0.0
        findings.append(
            {
                "from_n": n1,
                "to_n": n2,
                "learn_loop_time_ratio": (learn2 / learn1) if learn1 > 0 else 0.0,
                "index_and_flush_time_ratio": (index2 / index1) if index1 > 0 else 0.0,
                "durable_write_path_ms_from": durable1,
                "durable_write_path_ms_to": durable2,
                "durable_write_path_ratio": durable_ratio,
                # Kept for schema/gate compatibility. This now means the full
                # durable write path, not just the pre-flush learn loop.
                "write_time_ratio": durable_ratio,
                "suspected_quadratic_write": durable1 > 0 and durable_ratio >= 3.5,
            }
        )
    return findings


def main() -> int:
    args = parse_args()
    counts = parse_counts(args.counts)
    repo = Path.cwd().resolve()
    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    log_dir = report_path.parent / "memory-scaling-logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    # Count=1 includes Godot + harness + MemoryStore startup and is a more useful
    # hosted-runner baseline than dividing raw process RSS by dataset bytes.
    baseline_root = Path(tempfile.mkdtemp(prefix="aurora-memory-baseline-"))
    try:
        baseline = runner.run_godot_case(
            args.godot,
            repo,
            baseline_root,
            {"scenario": "semantic_memory", "count": 1},
            args.timeout_seconds,
            log_dir,
            suffix="_baseline",
        )
    finally:
        shutil.rmtree(baseline_root, ignore_errors=True)
    baseline_rss = int(baseline.get("peak_rss_bytes", 0)) if baseline.get("ok") else 0

    results: list[dict[str, Any]] = []
    hard_errors: list[dict[str, Any]] = []
    for count in counts:
        user_root = Path(tempfile.mkdtemp(prefix=f"aurora-memory-{count}-"))
        try:
            result = runner.run_godot_case(
                args.godot,
                repo,
                user_root,
                {"scenario": "semantic_memory", "count": count},
                args.timeout_seconds,
                log_dir,
            )
        finally:
            shutil.rmtree(user_root, ignore_errors=True)
        result["incremental_peak_rss_bytes"] = max(0, int(result.get("peak_rss_bytes", 0)) - baseline_rss)
        result["durable_write_path_ms"] = float(result.get("write_duration_ms", 0.0) or 0.0) + float(
            result.get("semantic_index_build_ms", 0.0) or 0.0
        )
        results.append(result)
        if not result.get("ok"):
            hard_errors.append({"count": count, "error": result.get("error", "case failed")})
        for key in ("network_required", "external_runtime_required", "ollama_required"):
            if bool(result.get(key, True)):
                hard_errors.append({"count": count, "error": f"self-reliance regression: {key}=true"})

    findings = pair_findings(results)
    suspected = any(bool(row.get("suspected_quadratic_write")) for row in findings)
    report = {
        "schema": "aurorafox_memory_scaling_v1",
        "platform_runtime_identity": runner.comparable_identity(),
        "baseline": {
            "scenario": "semantic_memory",
            "records": 1,
            "ok": bool(baseline.get("ok", False)),
            "peak_rss_bytes": baseline_rss,
            "note": "baseline includes Godot/harness/MemoryStore startup plus one record",
        },
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
            "suspected_quadratic_write": suspected,
            "write_scaling_contract": "learn loop + reindex/flush is the durable write path",
            "absolute_ci_timings_are_informational": True,
        },
        "results": results,
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"report": str(report_path), "hard_passed": not hard_errors, "suspected_quadratic_write": suspected}))
    return 0 if not hard_errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
