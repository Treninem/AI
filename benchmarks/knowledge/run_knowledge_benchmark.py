#!/usr/bin/env python3
"""AuroraFox Knowledge/Memory benchmark orchestrator.

Runs the real Godot KnowledgeStore/MemoryStore benchmark in an isolated user-data
root, samples child-process RSS without third-party packages, preserves raw logs,
and writes one machine-readable JSON report.
"""
from __future__ import annotations

import argparse
import ctypes
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "benchmarks" / "core"))
from report_identity import checkout_sha

RESULT_PREFIX = "AURORA_KNOWLEDGE_BENCH_RESULT="
MB = 1024 * 1024


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True, help="Godot 4.7.1 executable")
    parser.add_argument("--profile", choices=("smoke", "standard", "stress"), default="smoke")
    parser.add_argument("--scenario", default="", help="Optional single scenario")
    parser.add_argument("--target-mb", type=int, default=0)
    parser.add_argument("--count", type=int, default=0)
    parser.add_argument("--source-kb", type=int, default=0)
    parser.add_argument("--timeout-seconds", type=int, default=900)
    parser.add_argument("--report", default="artifacts/knowledge-performance/report.json")
    return parser.parse_args()


def scenario_matrix(profile: str) -> list[dict[str, Any]]:
    # Push CI stays bounded; standard/stress are explicit workflow_dispatch gates.
    if profile == "smoke":
        return [
            {"scenario": "import_jsonl", "target_mb": 1, "restart": True},
            {"scenario": "source_lifecycle", "target_mb": 1},
            {"scenario": "rollback", "target_mb": 9, "restart": True, "restart_marker": "AURORA_ROLLBACK_STABLE_MARKER", "restart_source": "user://knowledge_bench/rollback_source.json"},
            {"scenario": "scaling_many_sources", "count": 4, "source_kb": 16},
            {"scenario": "scaling_many_sources", "count": 8, "source_kb": 16},
            {"scenario": "scaling_many_sources", "count": 16, "source_kb": 16},
            {"scenario": "semantic_memory", "count": 64},
            {"scenario": "unicode_long_path"},
        ]
    if profile == "standard":
        return [
            {"scenario": "import_jsonl", "target_mb": 10, "restart": True},
            {"scenario": "import_csv", "target_mb": 10, "restart": True},
            {"scenario": "import_txt", "target_mb": 10, "restart": True},
            {"scenario": "import_json", "target_mb": 10, "restart": True},
            {"scenario": "dedupe_seed", "target_mb": 2, "next": "dedupe_reimport"},
            {"scenario": "source_lifecycle", "target_mb": 3},
            {"scenario": "rollback", "target_mb": 10, "restart": True, "restart_marker": "AURORA_ROLLBACK_STABLE_MARKER", "restart_source": "user://knowledge_bench/rollback_source.json"},
            {"scenario": "scaling_many_sources", "count": 8, "source_kb": 32},
            {"scenario": "scaling_many_sources", "count": 16, "source_kb": 32},
            {"scenario": "scaling_many_sources", "count": 32, "source_kb": 32},
            {"scenario": "semantic_memory", "count": 250},
            {"scenario": "concurrent_import", "target_mb": 1},
            {"scenario": "unicode_long_path"},
        ]
    return [
        {"scenario": "import_jsonl", "target_mb": 10, "restart": True},
        {"scenario": "import_jsonl", "target_mb": 50, "restart": True},
        {"scenario": "import_jsonl", "target_mb": 100, "restart": True},
        {"scenario": "import_jsonl", "target_mb": 250, "restart": True},
        {"scenario": "import_csv", "target_mb": 50, "restart": True},
        {"scenario": "import_txt", "target_mb": 100, "restart": True},
        {"scenario": "import_json", "target_mb": 100, "restart": True},
        {"scenario": "dedupe_seed", "target_mb": 10, "next": "dedupe_reimport"},
        {"scenario": "source_lifecycle", "target_mb": 30},
        {"scenario": "rollback", "target_mb": 100, "restart": True, "restart_marker": "AURORA_ROLLBACK_STABLE_MARKER", "restart_source": "user://knowledge_bench/rollback_source.json"},
        {"scenario": "scaling_many_sources", "count": 16, "source_kb": 64},
        {"scenario": "scaling_many_sources", "count": 32, "source_kb": 64},
        {"scenario": "scaling_many_sources", "count": 64, "source_kb": 64},
        {"scenario": "semantic_memory", "count": 500},
        {"scenario": "semantic_memory", "count": 1000},
        {"scenario": "concurrent_import", "target_mb": 10},
        {"scenario": "unicode_long_path"},
    ]


def process_rss_bytes(pid: int) -> int:
    if sys.platform.startswith("linux"):
        try:
            for line in Path(f"/proc/{pid}/status").read_text(encoding="utf-8").splitlines():
                if line.startswith("VmRSS:"):
                    return int(line.split()[1]) * 1024
        except (OSError, ValueError, IndexError):
            return 0
        return 0
    if sys.platform == "win32":
        try:
            class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
                _fields_ = [
                    ("cb", ctypes.c_ulong),
                    ("PageFaultCount", ctypes.c_ulong),
                    ("PeakWorkingSetSize", ctypes.c_size_t),
                    ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t),
                    ("PeakPagefileUsage", ctypes.c_size_t),
                ]
            kernel32 = ctypes.windll.kernel32
            psapi = ctypes.windll.psapi
            handle = kernel32.OpenProcess(0x0400 | 0x0010, False, pid)
            if not handle:
                return 0
            counters = PROCESS_MEMORY_COUNTERS()
            counters.cb = ctypes.sizeof(counters)
            ok = psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb)
            kernel32.CloseHandle(handle)
            return int(counters.WorkingSetSize) if ok else 0
        except (AttributeError, OSError, ValueError):
            return 0
    return 0


def base_environment(user_root: Path, case: dict[str, Any]) -> dict[str, str]:
    env = os.environ.copy()
    home = user_root / "home"
    xdg = user_root / "xdg"
    appdata = user_root / "appdata"
    localappdata = user_root / "localappdata"
    for path in (home, xdg, appdata, localappdata):
        path.mkdir(parents=True, exist_ok=True)
    env.update(
        {
            "HOME": str(home),
            "XDG_DATA_HOME": str(xdg),
            "APPDATA": str(appdata),
            "LOCALAPPDATA": str(localappdata),
            "AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE": "1",
            "AURORA_KNOWLEDGE_SCENARIO": str(case.get("scenario", "")),
            "AURORA_KNOWLEDGE_TARGET_MB": str(case.get("target_mb", 1)),
            "AURORA_KNOWLEDGE_COUNT": str(case.get("count", 1)),
            "AURORA_KNOWLEDGE_SOURCE_KB": str(case.get("source_kb", 16)),
        }
    )
    return env


def parse_result(stdout: str) -> dict[str, Any] | None:
    for line in reversed(stdout.splitlines()):
        if line.startswith(RESULT_PREFIX):
            try:
                parsed = json.loads(line[len(RESULT_PREFIX) :])
            except json.JSONDecodeError:
                return None
            return parsed if isinstance(parsed, dict) else None
    return None


def run_godot_case(
    godot: str,
    repo: Path,
    user_root: Path,
    case: dict[str, Any],
    timeout_seconds: int,
    log_dir: Path,
    suffix: str = "",
    extra_env: dict[str, str] | None = None,
) -> dict[str, Any]:
    scenario = str(case.get("scenario", "unknown"))
    tag = f"{scenario}_{case.get('target_mb', '')}_{case.get('count', '')}{suffix}".strip("_")
    env = base_environment(user_root, case)
    if extra_env:
        env.update(extra_env)
    stdout_path = log_dir / f"{tag}.stdout.log"
    stderr_path = log_dir / f"{tag}.stderr.log"
    command = [godot, "--headless", "--path", str(repo), "--script", "benchmarks/knowledge/knowledge_stress_benchmark.gd"]
    peak_rss = 0
    timed_out = False
    started = time.perf_counter()
    with stdout_path.open("wb") as stdout_file, stderr_path.open("wb") as stderr_file:
        proc = subprocess.Popen(command, cwd=repo, env=env, stdout=stdout_file, stderr=stderr_file)
        while proc.poll() is None:
            peak_rss = max(peak_rss, process_rss_bytes(proc.pid))
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
        peak_rss = max(peak_rss, process_rss_bytes(proc.pid))
    wall_ms = (time.perf_counter() - started) * 1000.0
    stdout = stdout_path.read_text(encoding="utf-8", errors="replace")
    stderr = stderr_path.read_text(encoding="utf-8", errors="replace")
    parsed = parse_result(stdout)
    if parsed is None:
        parsed = {"ok": False, "error": "benchmark result marker missing"}
    parsed.update(
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
        parsed["ok"] = False
        if timed_out:
            parsed["error"] = f"bounded execution timeout after {timeout_seconds}s"
        elif not parsed.get("error"):
            parsed["error"] = f"Godot exited with {return_code}"
    return parsed


def run_restart_check(
    godot: str,
    repo: Path,
    user_root: Path,
    source_result: dict[str, Any],
    timeout_seconds: int,
    log_dir: Path,
    restart_marker: str = "",
    restart_source: str = "",
) -> dict[str, Any]:
    contract = source_result.get("restart_contract", {})
    if not isinstance(contract, dict):
        contract = {}
    marker = restart_marker or str(contract.get("marker", ""))
    source = restart_source or str(contract.get("source", ""))
    return run_godot_case(
        godot,
        repo,
        user_root,
        {"scenario": "restart_check"},
        timeout_seconds,
        log_dir,
        suffix="_process_restart",
        extra_env={"AURORA_KNOWLEDGE_EXPECT_MARKER": marker, "AURORA_KNOWLEDGE_EXPECT_SOURCE": source},
    )


def scaling_findings(results: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = [r for r in results if r.get("scenario") == "scaling_many_sources" and r.get("ok")]
    rows.sort(key=lambda r: int(r.get("source_count", 0)))
    findings: list[dict[str, Any]] = []
    for left, right in zip(rows, rows[1:]):
        n1, n2 = int(left.get("source_count", 0)), int(right.get("source_count", 0))
        t1, t2 = float(left.get("import_duration_ms", 0.0)), float(right.get("import_duration_ms", 0.0))
        if n1 <= 0 or n2 != n1 * 2 or t1 <= 0:
            continue
        ratio = t2 / t1
        findings.append(
            {
                "from_n": n1,
                "to_n": n2,
                "time_ratio": ratio,
                "suspected_quadratic": ratio >= 3.5,
                "rule": "2x input approaching 4x+ runtime is a production scaling blocker candidate",
            }
        )
    return findings


def memory_scaling_findings(results: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = [r for r in results if r.get("scenario") == "import_jsonl" and r.get("ok")]
    rows.sort(key=lambda r: float((r.get("dataset") or {}).get("size_mb", 0.0)))
    out: list[dict[str, Any]] = []
    for row in rows:
        dataset = row.get("dataset") or {}
        size = int(dataset.get("bytes", 0))
        rss = int(row.get("peak_rss_bytes", 0))
        out.append(
            {
                "dataset_bytes": size,
                "peak_rss_bytes": rss,
                "rss_to_dataset_ratio": (float(rss) / float(size)) if size else 0.0,
            }
        )
    return out


def _godot_version(runtime: dict[str, Any]) -> str:
    value = runtime.get("godot", {})
    if not isinstance(value, dict):
        return str(value or "")
    if value.get("string"):
        return str(value.get("string"))
    major, minor, patch = value.get("major", ""), value.get("minor", ""), value.get("patch", "")
    status = str(value.get("status", ""))
    version = ".".join(str(part) for part in (major, minor, patch) if str(part) != "")
    return version + (f"-{status}" if status else "")


def comparable_identity(results: list[dict[str, Any]] | None = None, repo: Path = ROOT) -> dict[str, Any]:
    identity: dict[str, Any] = {
        "os": platform.system(),
        "os_release": platform.release(),
        "machine": platform.machine(),
        "python": platform.python_version(),
        "cpu_count": os.cpu_count(),
        "ci": bool(os.environ.get("CI")),
        "runner_name": os.environ.get("RUNNER_NAME", ""),
        "runner_os": os.environ.get("RUNNER_OS", ""),
        "runner_arch": os.environ.get("RUNNER_ARCH", ""),
        "git_sha": checkout_sha(repo),
    }
    for row in results or []:
        runtime = row.get("runtime", {}) if isinstance(row, dict) else {}
        if not isinstance(runtime, dict) or not runtime:
            continue
        identity["processor_name"] = str(runtime.get("processor_name", ""))
        identity["godot_architecture"] = str(runtime.get("architecture", ""))
        identity["godot_version"] = _godot_version(runtime)
        break
    return identity


def aggregate_counts(results: list[dict[str, Any]], hard_errors: list[dict[str, Any]]) -> dict[str, int]:
    dataset_bytes = 0
    records = 0
    chunks = 0
    duplicate_count = 0
    for row in results:
        if not isinstance(row, dict):
            continue
        dataset = row.get("dataset", {})
        if isinstance(dataset, dict):
            dataset_bytes += int(dataset.get("bytes", 0) or 0)
        records += int(row.get("records", 0) or 0)
        chunks += int(row.get("chunks", 0) or 0)
        if row.get("scenario") == "dedupe_reimport":
            for key in ("same_path_duplicate", "renamed_duplicate"):
                event = row.get(key, {})
                if isinstance(event, dict) and bool(event.get("duplicate", False)) and bool(event.get("skipped", False)):
                    duplicate_count += 1
        elif bool(row.get("duplicate", False)):
            duplicate_count += 1
    return {
        "case_count": len(results),
        "dataset_bytes_total": dataset_bytes,
        "records_reported_total": records,
        "chunks_reported_total": chunks,
        "duplicate_count": duplicate_count,
        "error_count": len(hard_errors),
    }


def main() -> int:
    args = parse_args()
    repo = Path.cwd().resolve()
    source_sha = checkout_sha(repo)
    print("AURORA_KNOWLEDGE_SOURCE_SHA=" + source_sha, flush=True)
    godot = str(Path(args.godot).resolve()) if not os.path.isabs(args.godot) else args.godot
    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    log_dir = report_path.parent / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    matrix = scenario_matrix(args.profile)
    if args.scenario:
        case: dict[str, Any] = {"scenario": args.scenario}
        if args.target_mb:
            case["target_mb"] = args.target_mb
        if args.count:
            case["count"] = args.count
        if args.source_kb:
            case["source_kb"] = args.source_kb
        if args.scenario.startswith("import_") or args.scenario == "rollback":
            case["restart"] = True
        matrix = [case]

    results: list[dict[str, Any]] = []
    hard_errors: list[dict[str, Any]] = []
    for index, case in enumerate(matrix):
        user_root = Path(tempfile.mkdtemp(prefix=f"aurora-knowledge-{index:02d}-"))
        try:
            result = run_godot_case(godot, repo, user_root, case, args.timeout_seconds, log_dir)
            result["case"] = case
            results.append(result)
            if not result.get("ok"):
                hard_errors.append({"scenario": case.get("scenario"), "error": result.get("error", "failed")})
                continue

            if case.get("restart"):
                restart = run_restart_check(
                    godot,
                    repo,
                    user_root,
                    result,
                    args.timeout_seconds,
                    log_dir,
                    str(case.get("restart_marker", "")),
                    str(case.get("restart_source", "")),
                )
                restart["parent_scenario"] = case.get("scenario")
                results.append(restart)
                if not restart.get("ok"):
                    hard_errors.append({"scenario": "restart_check", "parent": case.get("scenario"), "error": restart.get("error", "failed")})

            next_scenario = str(case.get("next", ""))
            if next_scenario:
                followup = run_godot_case(
                    godot,
                    repo,
                    user_root,
                    {"scenario": next_scenario},
                    args.timeout_seconds,
                    log_dir,
                    suffix="_after_restart",
                )
                followup["parent_scenario"] = case.get("scenario")
                results.append(followup)
                if not followup.get("ok"):
                    hard_errors.append({"scenario": next_scenario, "error": followup.get("error", "failed")})
        finally:
            shutil.rmtree(user_root, ignore_errors=True)

    scaling = scaling_findings(results)
    counts = aggregate_counts(results, hard_errors)
    checkout_sha(repo, source_sha)  # Do not relabel results if HEAD moved during the run.
    report: dict[str, Any] = {
        "schema": "aurorafox_knowledge_performance_v1",
        "generated_at_unix": time.time(),
        "profile": args.profile,
        "platform_runtime_identity": comparable_identity(results, repo),
        "summary_counts": counts,
        "error_count": counts["error_count"],
        "duplicate_count": counts["duplicate_count"],
        "self_reliance_contract": {
            "network_required": False,
            "external_runtime_required": False,
            "ollama_required": False,
            "remote_inference": False,
        },
        "android_contract": {
            "bounded_memory_required": True,
            "incremental_processing_required": True,
            "giant_temporary_copies_forbidden": True,
            "private_storage_required": True,
            "physical_device_proof": False,
            "note": "Desktop CI evidence is not Android device proof; physical-device stress remains a separate gate.",
        },
        "hard_correctness": {
            "passed": not hard_errors,
            "errors": hard_errors,
            "checks": ["no_crash", "no_partial_source", "restart_retrieval", "dedupe", "source_removal", "rollback", "search_correctness", "self_reliance"],
        },
        "relative_performance": {
            "n_2n_4n": scaling,
            "suspected_quadratic": any(bool(row.get("suspected_quadratic")) for row in scaling),
            "memory_scaling": memory_scaling_findings(results),
            "absolute_ci_timings_are_informational": True,
        },
        "results": results,
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"report": str(report_path), "passed": not hard_errors, "cases": len(results), "error_count": counts["error_count"], "duplicate_count": counts["duplicate_count"], "suspected_quadratic": report["relative_performance"]["suspected_quadratic"]}, ensure_ascii=False))
    return 0 if not hard_errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
