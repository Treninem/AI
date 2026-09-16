#!/usr/bin/env python3
"""Kill a real AuroraFox reimport after snapshot+mutation, then verify restart recovery."""
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

RESULT_PREFIX = "AURORA_KNOWLEDGE_INTERRUPT_RESULT="
SCRIPT = "benchmarks/knowledge/interrupted_import_probe.gd"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--target-mb", type=int, default=32)
    parser.add_argument("--timeout-seconds", type=int, default=180)
    parser.add_argument("--report", required=True)
    return parser.parse_args()


def parse_result(stdout: str) -> dict[str, Any] | None:
    for line in reversed(stdout.splitlines()):
        if not line.startswith(RESULT_PREFIX):
            continue
        try:
            value = json.loads(line[len(RESULT_PREFIX):])
        except json.JSONDecodeError:
            return None
        return value if isinstance(value, dict) else None
    return None


def run_phase(godot: str, repo: Path, env: dict[str, str], phase: str, timeout_seconds: int) -> dict[str, Any]:
    phase_env = env.copy()
    phase_env["AURORA_INTERRUPT_PHASE"] = phase
    started = time.perf_counter()
    proc = subprocess.run(
        [godot, "--headless", "--path", str(repo), "--script", SCRIPT],
        cwd=repo,
        env=phase_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout_seconds,
        check=False,
    )
    parsed = parse_result(proc.stdout) or {"ok": False, "error": "probe result marker missing"}
    parsed.update(
        {
            "return_code": proc.returncode,
            "wall_ms": (time.perf_counter() - started) * 1000.0,
            "stderr": proc.stderr[-4000:],
        }
    )
    return parsed


def file_size(path: Path) -> int:
    try:
        return path.stat().st_size
    except OSError:
        return -1


def main() -> int:
    args = parse_args()
    repo = Path.cwd().resolve()
    godot = str(Path(args.godot).resolve()) if not os.path.isabs(args.godot) else args.godot
    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    log_dir = report_path.parent / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="aurora-knowledge-interrupt-"))
    started = time.perf_counter()
    try:
        env = base.base_environment(root, {"scenario": "interrupted_import"})
        env["AURORA_INTERRUPT_TARGET_MB"] = str(max(16, args.target_mb))
        warm = portable.warm_isolated_windows_profile(
            godot,
            repo,
            root,
            env,
            args.timeout_seconds,
            log_dir,
            "interrupted-recovery",
        )
        if not warm.get("ok"):
            report = {
                "schema": "aurorafox_knowledge_interrupted_recovery_v1",
                "ok": False,
                "phase": "profile_warmup",
                "isolated_profile_warmup": warm,
                "network_required": False,
                "external_runtime_required": False,
                "ollama_required": False,
            }
            report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
            print(json.dumps({"report": str(report_path), "ok": False, "phase": "profile_warmup"}))
            return 1

        seed = run_phase(godot, repo, env, "seed", args.timeout_seconds)
        if not seed.get("ok"):
            report = {"ok": False, "phase": "seed", "seed": seed, "isolated_profile_warmup": warm}
            report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
            print(json.dumps({"report": str(report_path), "ok": False, "phase": "seed"}))
            return 1

        db_path = Path(str(seed.get("db_abs", "")))
        structured_path = Path(str(seed.get("structured_abs", "")))
        db_backup = Path(str(seed.get("db_backup_abs", "")))
        structured_backup = Path(str(seed.get("structured_backup_abs", "")))
        registry_backup = Path(str(seed.get("registry_backup_abs", "")))
        seed_db_size = int(seed.get("db_size", -1))
        seed_structured_size = int(seed.get("structured_size", -1))

        import_env = env.copy()
        import_env["AURORA_INTERRUPT_PHASE"] = "import"
        stdout_path = log_dir / "interrupted-import.stdout.log"
        stderr_path = log_dir / "interrupted-import.stderr.log"
        kill_observed = False
        mutation_observed = False
        snapshot_observed = False
        timed_out = False
        import_started = time.perf_counter()
        with stdout_path.open("wb") as stdout_file, stderr_path.open("wb") as stderr_file:
            proc = subprocess.Popen(
                [godot, "--headless", "--path", str(repo), "--script", SCRIPT],
                cwd=repo,
                env=import_env,
                stdout=stdout_file,
                stderr=stderr_file,
            )
            while proc.poll() is None:
                snapshot_observed = registry_backup.exists() and (db_backup.exists() or structured_backup.exists())
                current_db = file_size(db_path)
                current_structured = file_size(structured_path)
                mutation_observed = snapshot_observed and (
                    (current_db >= 0 and current_db != seed_db_size)
                    or (current_structured >= 0 and current_structured != seed_structured_size)
                )
                if mutation_observed:
                    proc.kill()
                    kill_observed = True
                    break
                if time.perf_counter() - import_started > args.timeout_seconds:
                    proc.kill()
                    timed_out = True
                    break
                time.sleep(0.02)
            try:
                return_code = proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                return_code = proc.wait()

        verify = run_phase(godot, repo, env, "verify", args.timeout_seconds)
        import_stdout = stdout_path.read_text(encoding="utf-8", errors="replace")[-4000:]
        import_stderr = stderr_path.read_text(encoding="utf-8", errors="replace")[-4000:]
        ok = bool(kill_observed and snapshot_observed and mutation_observed and not timed_out and verify.get("ok"))
        report = {
            "schema": "aurorafox_knowledge_interrupted_recovery_v1",
            "ok": ok,
            "seed": seed,
            "injection": {
                "target_mb": max(16, args.target_mb),
                "snapshot_observed": snapshot_observed,
                "storage_mutation_observed": mutation_observed,
                "process_killed": kill_observed,
                "timed_out": timed_out,
                "import_return_code": return_code,
                "stdout_tail": import_stdout,
                "stderr_tail": import_stderr,
            },
            "restart_verify": verify,
            "isolated_profile_warmup": warm,
            "wall_ms": (time.perf_counter() - started) * 1000.0,
            "network_required": False,
            "external_runtime_required": False,
            "ollama_required": False,
        }
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"report": str(report_path), "ok": ok, "killed": kill_observed, "recovered": bool(verify.get("ok"))}, ensure_ascii=False))
        return 0 if ok else 1
    except subprocess.TimeoutExpired as exc:
        report = {"ok": False, "error": f"phase timeout: {exc}", "wall_ms": (time.perf_counter() - started) * 1000.0}
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"report": str(report_path), "ok": False, "error": report["error"]}))
        return 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
