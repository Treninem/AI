#!/usr/bin/env python3
"""Bounded large-import pressure evidence without conflating import with 40 full scans."""
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

IMPORT_PREFIX = "AURORA_KNOWLEDGE_PRESSURE_IMPORT_RESULT="
REMOVE_PREFIX = "AURORA_KNOWLEDGE_PRESSURE_REMOVE_RESULT="
MB = 1024 * 1024


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--sizes-mb", default="10,50,100,250")
    parser.add_argument("--timeout-seconds", type=int, default=600)
    parser.add_argument("--report", default="artifacts/knowledge-performance/large-pressure.json")
    return parser.parse_args()


def parse_sizes(raw: str) -> list[int]:
    values = [int(value.strip()) for value in raw.split(",") if value.strip()]
    if not values or any(value <= 0 for value in values):
        raise ValueError("sizes must be positive integers")
    if len(set(values)) != len(values):
        raise ValueError("sizes must be unique")
    return values


def parse_marker(stdout: str, prefix: str) -> dict[str, Any] | None:
    for line in reversed(stdout.splitlines()):
        if line.startswith(prefix):
            try:
                parsed = json.loads(line[len(prefix):])
            except json.JSONDecodeError:
                return None
            return parsed if isinstance(parsed, dict) else None
    return None


def run_script(
    godot: str,
    repo: Path,
    user_root: Path,
    script: str,
    prefix: str,
    timeout_seconds: int,
    log_dir: Path,
    tag: str,
    extra_env: dict[str, str] | None = None,
) -> dict[str, Any]:
    env = base.base_environment(user_root, {"scenario": "large_pressure", "target_mb": 1})
    if extra_env:
        env.update(extra_env)
    stdout_path = log_dir / f"{tag}.stdout.log"
    stderr_path = log_dir / f"{tag}.stderr.log"
    command = [godot, "--headless", "--path", str(repo), "--script", script]
    peak_rss = 0
    timed_out = False
    started = time.perf_counter()
    with stdout_path.open("wb") as stdout_file, stderr_path.open("wb") as stderr_file:
        proc = subprocess.Popen(command, cwd=repo, env=env, stdout=stdout_file, stderr=stderr_file)
        while proc.poll() is None:
            peak_rss = max(peak_rss, base.process_rss_bytes(proc.pid))
            if time.perf_counter() - started > timeout_seconds:
                timed_out = True
                proc.kill()
                break
            time.sleep(0.05)
        try:
            return_code = proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            return_code = proc.wait()
    wall_ms = (time.perf_counter() - started) * 1000.0
    stdout = stdout_path.read_text(encoding="utf-8", errors="replace")
    stderr = stderr_path.read_text(encoding="utf-8", errors="replace")
    result = parse_marker(stdout, prefix) or {"ok": False, "error": "pressure result marker missing"}
    result.update(
        {
            "runner_return_code": return_code,
            "runner_wall_ms": wall_ms,
            "peak_rss_bytes": peak_rss,
            "timed_out": timed_out,
            "stdout_log": str(stdout_path),
            "stderr_log": str(stderr_path),
        }
    )
    if timed_out or return_code != 0:
        result["ok"] = False
        if timed_out:
            result["error"] = f"bounded pressure phase timeout after {timeout_seconds}s"
        elif not result.get("error"):
            result["error"] = f"Godot exited with {return_code}"
    return result


def result_self_reliant(result: dict[str, Any]) -> bool:
    runtime = result.get("runtime")
    if not isinstance(runtime, dict):
        return False
    return (
        runtime.get("network_required") is False
        and runtime.get("external_runtime_required") is False
        and runtime.get("ollama_required") is False
    )


def main() -> int:
    args = parse_args()
    sizes = parse_sizes(args.sizes_mb)
    repo = Path.cwd().resolve()
    godot = str(Path(args.godot).resolve()) if not os.path.isabs(args.godot) else args.godot
    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    log_dir = report_path.parent / "large-pressure-logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    cases: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []
    for size_mb in sizes:
        user_root = Path(tempfile.mkdtemp(prefix=f"aurora-pressure-{size_mb}mb-"))
        try:
            imported = run_script(
                godot,
                repo,
                user_root,
                "benchmarks/knowledge/large_import_pressure_probe.gd",
                IMPORT_PREFIX,
                args.timeout_seconds,
                log_dir,
                f"import_{size_mb}mb",
                {"AURORA_KNOWLEDGE_TARGET_MB": str(size_mb)},
            )
            restart: dict[str, Any] = {"ok": False, "error": "import failed; restart not attempted"}
            removal: dict[str, Any] = {"ok": False, "error": "import failed; removal not attempted"}
            if imported.get("ok"):
                contract = imported.get("restart_contract")
                if not isinstance(contract, dict):
                    contract = {}
                marker = str(contract.get("marker", ""))
                source = str(contract.get("source", ""))
                restart = base.run_restart_check(
                    godot,
                    repo,
                    user_root,
                    imported,
                    args.timeout_seconds,
                    log_dir,
                    restart_marker=marker,
                    restart_source=source,
                )
                if restart.get("ok"):
                    removal = run_script(
                        godot,
                        repo,
                        user_root,
                        "benchmarks/knowledge/large_remove_pressure_probe.gd",
                        REMOVE_PREFIX,
                        args.timeout_seconds,
                        log_dir,
                        f"remove_{size_mb}mb",
                        {
                            "AURORA_KNOWLEDGE_EXPECT_MARKER": marker,
                            "AURORA_KNOWLEDGE_EXPECT_SOURCE": source,
                        },
                    )
            peak_rss = max(
                int(imported.get("peak_rss_bytes", 0) or 0),
                int(restart.get("peak_rss_bytes", 0) or 0),
                int(removal.get("peak_rss_bytes", 0) or 0),
            )
            dataset = imported.get("dataset") if isinstance(imported.get("dataset"), dict) else {}
            dataset_bytes = int(dataset.get("bytes", 0) or 0)
            store_bytes = int(imported.get("store_size_bytes", 0) or 0)
            case_ok = (
                bool(imported.get("ok"))
                and bool(restart.get("ok"))
                and bool(removal.get("ok"))
                and result_self_reliant(imported)
            )
            case = {
                "ok": case_ok,
                "size_mb": size_mb,
                "dataset_bytes": dataset_bytes,
                "records": int(imported.get("records", 0) or 0),
                "chunks": int(imported.get("chunks", 0) or 0),
                "import_duration_ms": float(imported.get("import_duration_ms", 0.0) or 0.0),
                "mb_per_sec": float(imported.get("mb_per_sec", 0.0) or 0.0),
                "search_once_ms": float(imported.get("search_once_ms", 0.0) or 0.0),
                "restart_load_search_ms": float(restart.get("restart_load_search_ms", 0.0) or 0.0),
                "removal_duration_ms": float(removal.get("removal_duration_ms", 0.0) or 0.0),
                "peak_rss_bytes": peak_rss,
                "rss_to_dataset_ratio": (float(peak_rss) / float(dataset_bytes)) if dataset_bytes else 0.0,
                "store_size_bytes": store_bytes,
                "storage_amplification": (float(store_bytes) / float(dataset_bytes)) if dataset_bytes else 0.0,
                "import": imported,
                "restart": restart,
                "removal": removal,
            }
            cases.append(case)
            if not case_ok:
                errors.append(
                    {
                        "size_mb": size_mb,
                        "import_error": imported.get("error", ""),
                        "restart_error": restart.get("error", ""),
                        "removal_error": removal.get("error", ""),
                    }
                )
        finally:
            shutil.rmtree(user_root, ignore_errors=True)

    report = {
        "schema": "aurorafox_knowledge_large_pressure_v1",
        "platform_runtime_identity": base.comparable_identity(),
        "sizes_mb": sizes,
        "self_reliance_contract": {
            "network_required": False,
            "external_runtime_required": False,
            "ollama_required": False,
        },
        "android_contract": {
            "bounded_memory_required": True,
            "private_storage_required": True,
            "mandatory_external_service": False,
            "physical_device_proof": False,
        },
        "hard_correctness": {
            "passed": not errors and len(cases) == len(sizes),
            "errors": errors,
            "checks": [
                "streaming_import",
                "single_search_correctness",
                "process_restart_retrieval",
                "transactional_source_removal",
                "registry_lifecycle",
                "self_reliance",
                "bounded_phase_timeout",
            ],
        },
        "measurement_note": (
            "Large-pressure import intentionally performs one correctness search per size. "
            "Search p50/p95/p99 are measured separately by run_search_scaling.py so full-scan "
            "latency is not multiplied into the import/memory-pressure timeout."
        ),
        "results": cases,
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(
        json.dumps(
            {
                "report": str(report_path),
                "sizes_mb": sizes,
                "hard_passed": report["hard_correctness"]["passed"],
                "error_count": len(errors),
            }
        )
    )
    return 0 if report["hard_correctness"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
