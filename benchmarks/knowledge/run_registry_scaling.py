#!/usr/bin/env python3
"""Measure isolated KnowledgeSourceRegistry N/2N/4N scaling."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from typing import Any

import run_knowledge_benchmark as base
import run_knowledge_benchmark_portable as portable

PREFIX = "AURORA_KNOWLEDGE_REGISTRY_SCALING_RESULT="


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--counts", default="16,32,64")
    parser.add_argument("--source-kb", type=int, default=4)
    parser.add_argument("--timeout-seconds", type=int, default=300)
    parser.add_argument("--report", required=True)
    return parser.parse_args()


def parse_result(stdout: str) -> dict[str, Any] | None:
    for line in reversed(stdout.splitlines()):
        if not line.startswith(PREFIX):
            continue
        try:
            value = json.loads(line[len(PREFIX) :])
        except json.JSONDecodeError:
            return None
        return value if isinstance(value, dict) else None
    return None


def run_case(godot: str, repo: Path, count: int, source_kb: int, timeout: int, logs: Path) -> dict[str, Any]:
    root = Path(tempfile.mkdtemp(prefix=f"aurora-registry-{count}-"))
    try:
        env = base.base_environment(root, {"scenario": "registry_scaling"})
        env["AURORA_REGISTRY_SCALING_COUNT"] = str(count)
        env["AURORA_REGISTRY_SCALING_SOURCE_KB"] = str(source_kb)
        stdout_path = logs / f"registry_{count}.stdout.log"
        stderr_path = logs / f"registry_{count}.stderr.log"
        warm = portable.warm_isolated_windows_profile(
            godot,
            repo,
            root,
            env,
            timeout,
            logs,
            f"registry-{count}",
        )
        if not warm.get("ok"):
            return {
                "ok": False,
                "source_count": count,
                "error": warm.get("error", "isolated Windows Godot warm-up failed"),
                "isolated_profile_warmup": warm,
                "runner_return_code": int(warm.get("return_code", 1) or 1),
                "runner_wall_ms": float(warm.get("wall_ms", 0.0)),
                "peak_rss_bytes": 0,
                "timed_out": bool(warm.get("timed_out", False)),
                "stdout_log": str(stdout_path),
                "stderr_log": str(stderr_path),
            }
        command = [godot, "--headless", "--path", str(repo), "--script", "benchmarks/knowledge/registry_scaling_probe.gd"]
        peak_rss = 0
        started = time.perf_counter()
        with stdout_path.open("wb") as out, stderr_path.open("wb") as err:
            proc = subprocess.Popen(command, cwd=repo, env=env, stdout=out, stderr=err)
            timed_out = False
            while proc.poll() is None:
                peak_rss = max(peak_rss, base.process_rss_bytes(proc.pid))
                if time.perf_counter() - started > timeout:
                    timed_out = True
                    proc.kill()
                    break
                time.sleep(0.05)
            return_code = proc.wait(timeout=10)
        wall_ms = (time.perf_counter() - started) * 1000.0
        stdout = stdout_path.read_text(encoding="utf-8", errors="replace")
        result = parse_result(stdout) or {"ok": False, "error": "registry result marker missing"}
        result.update(
            {
                "runner_return_code": return_code,
                "runner_wall_ms": wall_ms,
                "peak_rss_bytes": peak_rss,
                "timed_out": timed_out,
                "stdout_log": str(stdout_path),
                "stderr_log": str(stderr_path),
                "isolated_profile_warmup": warm,
            }
        )
        if timed_out or return_code != 0:
            result["ok"] = False
            if timed_out:
                result["error"] = f"bounded execution timeout after {timeout}s"
            elif not result.get("error"):
                result["error"] = f"Godot exited with {return_code}"
        return result
    finally:
        shutil.rmtree(root, ignore_errors=True)


def pair_findings(results: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = [row for row in results if row.get("ok")]
    rows.sort(key=lambda row: int(row.get("source_count", 0)))
    findings: list[dict[str, Any]] = []
    for left, right in zip(rows, rows[1:]):
        n1 = int(left.get("source_count", 0))
        n2 = int(right.get("source_count", 0))
        t1 = float(left.get("register_duration_ms", 0.0))
        t2 = float(right.get("register_duration_ms", 0.0))
        if n1 <= 0 or n2 != n1 * 2 or t1 <= 0:
            continue
        ratio = t2 / t1
        findings.append(
            {
                "from_n": n1,
                "to_n": n2,
                "time_ratio": ratio,
                "suspected_quadratic_registry": ratio >= 3.5,
                "rule": "2x registry source count approaching 4x+ cumulative registration runtime is a scaling blocker",
            }
        )
    return findings


def main() -> int:
    args = parse_args()
    counts = [int(item) for item in args.counts.split(",") if item.strip()]
    if len(counts) < 2 or any(value <= 0 for value in counts):
        raise SystemExit("--counts requires at least two positive integers")
    repo = Path.cwd().resolve()
    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    logs = report_path.parent / "registry-scaling-logs"
    logs.mkdir(parents=True, exist_ok=True)
    godot = str(Path(args.godot).resolve()) if not os.path.isabs(args.godot) else args.godot

    results = [run_case(godot, repo, count, args.source_kb, args.timeout_seconds, logs) for count in counts]
    errors = [
        {"source_count": row.get("source_count", counts[index]), "error": row.get("error", "failed")}
        for index, row in enumerate(results)
        if not row.get("ok")
    ]
    findings = pair_findings(results)
    report = {
        "schema": "aurorafox_knowledge_registry_scaling_v1",
        "generated_at_unix": time.time(),
        "platform_runtime_identity": base.comparable_identity(),
        "hard_correctness": {"passed": not errors, "errors": errors},
        "relative_performance": {
            "n_2n_4n": findings,
            "suspected_quadratic_registry": any(row["suspected_quadratic_registry"] for row in findings),
            "absolute_ci_timings_are_informational": True,
        },
        "source_kb": args.source_kb,
        "results": results,
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "report": str(report_path),
        "passed": not errors,
        "suspected_quadratic_registry": report["relative_performance"]["suspected_quadratic_registry"],
    }, ensure_ascii=False))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
