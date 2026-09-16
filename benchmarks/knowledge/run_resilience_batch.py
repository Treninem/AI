#!/usr/bin/env python3
"""Run a consolidated AuroraFox Knowledge resilience/scaling evidence batch.

This orchestrator intentionally reuses the existing deterministic probes instead
of duplicating production logic. It produces one machine-readable verdict for
concurrency races, dedupe/source lifecycle, failure injection, restart recovery,
and isolated registry N/2N/4N scaling on the current platform.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Any

import run_knowledge_benchmark as base


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--counts", default="16,32,64")
    parser.add_argument("--source-kb", type=int, default=4)
    parser.add_argument("--timeout-seconds", type=int, default=300)
    parser.add_argument("--report", required=True)
    parser.add_argument("--enforce-performance", action="store_true")
    return parser.parse_args()


def load_report(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return {"ok": False, "error": f"cannot read child report: {exc}"}
    return value if isinstance(value, dict) else {"ok": False, "error": "child report is not an object"}


def report_passed(payload: dict[str, Any]) -> bool:
    if "ok" in payload:
        return bool(payload.get("ok"))
    hard = payload.get("hard_correctness")
    return bool(hard.get("passed", False)) if isinstance(hard, dict) else False


def registry_performance_blockers(payload: dict[str, Any]) -> list[str]:
    relative = payload.get("relative_performance")
    if not isinstance(relative, dict):
        return []
    return ["suspected_quadratic_registry"] if bool(relative.get("suspected_quadratic_registry", False)) else []


def run_child(name: str, command: list[str], report_path: Path, repo: Path, timeout: int) -> dict[str, Any]:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    try:
        proc = subprocess.run(
            command,
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
        )
        timed_out = False
        return_code = proc.returncode
        stdout_tail = proc.stdout[-4000:]
        stderr_tail = proc.stderr[-4000:]
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        return_code = -1
        stdout_tail = (exc.stdout or "")[-4000:] if isinstance(exc.stdout, str) else ""
        stderr_tail = (exc.stderr or "")[-4000:] if isinstance(exc.stderr, str) else ""

    payload = load_report(report_path) if report_path.exists() else {
        "ok": False,
        "error": "child report missing",
    }
    ok = not timed_out and return_code == 0 and report_passed(payload)
    return {
        "name": name,
        "ok": ok,
        "return_code": return_code,
        "timed_out": timed_out,
        "wall_ms": (time.perf_counter() - started) * 1000.0,
        "report_path": str(report_path),
        "stdout_tail": stdout_tail,
        "stderr_tail": stderr_tail,
        "report": payload,
    }


def probe_command(python: str, godot: str, script: str, prefix: str, report: Path, timeout: int) -> list[str]:
    return [
        python,
        "benchmarks/knowledge/run_godot_probe.py",
        "--godot",
        godot,
        "--script",
        script,
        "--prefix",
        prefix,
        "--timeout-seconds",
        str(timeout),
        "--report",
        str(report),
    ]


def main() -> int:
    args = parse_args()
    repo = Path.cwd().resolve()
    godot = str(Path(args.godot).resolve()) if not os.path.isabs(args.godot) else args.godot
    python = sys.executable
    final_report = Path(args.report)
    final_report.parent.mkdir(parents=True, exist_ok=True)
    child_dir = final_report.parent / "resilience-batch"
    child_dir.mkdir(parents=True, exist_ok=True)
    child_timeout = max(60, args.timeout_seconds)
    outer_timeout = child_timeout + 90

    specs: list[tuple[str, list[str], Path]] = []

    race_report = child_dir / "concurrency-race.json"
    specs.append((
        "concurrency_race",
        probe_command(
            python,
            godot,
            "benchmarks/knowledge/concurrency_race_probe.gd",
            "AURORA_KNOWLEDGE_CONCURRENCY_RESULT=",
            race_report,
            child_timeout,
        ),
        race_report,
    ))

    dedupe_report = child_dir / "record-dedupe-shared-source.json"
    specs.append((
        "record_dedupe_shared_source",
        probe_command(
            python,
            godot,
            "benchmarks/knowledge/record_dedupe_shared_source_probe.gd",
            "AURORA_KNOWLEDGE_RECORD_DEDUPE_RESULT=",
            dedupe_report,
            child_timeout,
        ),
        dedupe_report,
    ))

    alias_report = child_dir / "dedupe-alias-removal.json"
    specs.append((
        "dedupe_alias_removal",
        probe_command(
            python,
            godot,
            "benchmarks/knowledge/dedupe_alias_removal_probe.gd",
            "AURORA_KNOWLEDGE_ALIAS_REMOVAL_RESULT=",
            alias_report,
            child_timeout,
        ),
        alias_report,
    ))

    write_failure_report = child_dir / "write-failure-rollback.json"
    specs.append((
        "registry_write_failure_rollback",
        probe_command(
            python,
            godot,
            "benchmarks/knowledge/write_failure_rollback_probe.gd",
            "AURORA_KNOWLEDGE_WRITE_FAILURE_RESULT=",
            write_failure_report,
            child_timeout,
        ),
        write_failure_report,
    ))

    truncated_report = child_dir / "registry-truncated-temp.json"
    specs.append((
        "registry_truncated_temp",
        probe_command(
            python,
            godot,
            "benchmarks/knowledge/registry_truncated_temp_probe.gd",
            "AURORA_KNOWLEDGE_TRUNCATED_REGISTRY_RESULT=",
            truncated_report,
            child_timeout,
        ),
        truncated_report,
    ))

    interrupted_import_report = child_dir / "interrupted-import-recovery.json"
    specs.append((
        "interrupted_import_recovery",
        [
            python,
            "benchmarks/knowledge/run_interrupted_import_recovery.py",
            "--godot",
            godot,
            "--target-mb",
            "16",
            "--timeout-seconds",
            str(child_timeout),
            "--report",
            str(interrupted_import_report),
        ],
        interrupted_import_report,
    ))

    interrupted_remove_report = child_dir / "interrupted-removal-recovery.json"
    specs.append((
        "interrupted_removal_recovery",
        [
            python,
            "benchmarks/knowledge/run_interrupted_removal_recovery.py",
            "--godot",
            godot,
            "--target-mb",
            "8",
            "--timeout-seconds",
            str(child_timeout),
            "--report",
            str(interrupted_remove_report),
        ],
        interrupted_remove_report,
    ))

    registry_report = child_dir / "registry-scaling.json"
    specs.append((
        "registry_scaling",
        [
            python,
            "benchmarks/knowledge/run_registry_scaling.py",
            "--godot",
            godot,
            "--counts",
            args.counts,
            "--source-kb",
            str(args.source_kb),
            "--timeout-seconds",
            str(child_timeout),
            "--report",
            str(registry_report),
        ],
        registry_report,
    ))

    started = time.perf_counter()
    cases = [run_child(name, command, report, repo, outer_timeout) for name, command, report in specs]
    correctness_errors = [
        {"case": row["name"], "error": row["report"].get("error", "child failed"), "return_code": row["return_code"]}
        for row in cases
        if not row["ok"]
    ]
    registry_payload = next(
        (row["report"] for row in cases if row["name"] == "registry_scaling"),
        {},
    )
    performance_blockers = registry_performance_blockers(registry_payload)
    performance_ok = not args.enforce_performance or not performance_blockers
    overall_ok = not correctness_errors and performance_ok

    report = {
        "schema": "aurorafox_knowledge_resilience_batch_v1",
        "generated_at_unix": time.time(),
        "ok": overall_ok,
        "platform_runtime_identity": base.comparable_identity(),
        "hard_correctness": {"passed": not correctness_errors, "errors": correctness_errors},
        "relative_performance": {
            "enforced": bool(args.enforce_performance),
            "blockers": performance_blockers,
            "registry_n_2n_4n": registry_payload.get("relative_performance", {}).get("n_2n_4n", []) if isinstance(registry_payload.get("relative_performance"), dict) else [],
            "absolute_ci_timings_are_informational": True,
        },
        "self_reliance_contract": {
            "network_required": False,
            "external_runtime_required": False,
            "ollama_required": False,
        },
        "counts": args.counts,
        "source_kb": args.source_kb,
        "wall_ms": (time.perf_counter() - started) * 1000.0,
        "cases": cases,
    }
    final_report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "report": str(final_report),
        "ok": overall_ok,
        "failed_cases": [row["case"] for row in correctness_errors],
        "performance_blockers": performance_blockers,
    }, ensure_ascii=False))
    if correctness_errors:
        return 1
    if not performance_ok:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
