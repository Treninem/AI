#!/usr/bin/env python3
"""Run the real production Knowledge Pack import with bounded evidence."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import run_knowledge_benchmark as base


ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "benchmarks" / "knowledge" / "production_pack_acceptance.gd"


def warm_project(godot: Path, env: dict[str, str], report: Path, timeout_seconds: int) -> dict:
    stdout_log = report.with_suffix(report.suffix + ".import.stdout.log")
    stderr_log = report.with_suffix(report.suffix + ".import.stderr.log")
    command = [str(godot), "--headless", "--editor", "--path", str(ROOT), "--quit"]
    started = time.monotonic()
    timed_out = False
    return_code = -1
    try:
        with stdout_log.open("w", encoding="utf-8", errors="replace") as stdout_file, stderr_log.open(
            "w", encoding="utf-8", errors="replace"
        ) as stderr_file:
            completed = subprocess.run(
                command,
                cwd=ROOT,
                env=env,
                stdout=stdout_file,
                stderr=stderr_file,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=max(30, min(120, timeout_seconds)),
                check=False,
            )
            return_code = completed.returncode
    except subprocess.TimeoutExpired:
        timed_out = True
    return {
        "ok": return_code == 0 and not timed_out,
        "return_code": return_code,
        "timed_out": timed_out,
        "elapsed_ms": round((time.monotonic() - started) * 1000, 3),
        "stdout_log": str(stdout_log),
        "stderr_log": str(stderr_log),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--pack-dir", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=int, default=21600)
    parser.add_argument("--user-data-dir", type=Path)
    args = parser.parse_args()

    godot = args.godot.resolve()
    pack_dir = args.pack_dir.resolve()
    report = args.report.resolve()
    if not godot.is_file():
        parser.error(f"Godot executable is missing: {godot}")
    if not (pack_dir / "manifest.json").is_file():
        parser.error(f"extracted production pack is missing manifest.json: {pack_dir}")
    report.parent.mkdir(parents=True, exist_ok=True)

    temporary: tempfile.TemporaryDirectory[str] | None = None
    if args.user_data_dir:
        user_data = args.user_data_dir.resolve()
        user_data.mkdir(parents=True, exist_ok=True)
    else:
        temporary = tempfile.TemporaryDirectory(prefix="aurorafox-production-pack-")
        user_data = Path(temporary.name)

    env = base.base_environment(user_data, {"scenario": "production_pack_acceptance"})
    env.update(
        {
            "AURORAFOX_PRODUCTION_PACK_DIR": str(pack_dir),
            "AURORAFOX_PRODUCTION_PACK_REPORT": str(report),
            "AURORAFOX_OFFLINE": "1",
            "AURORAFOX_DISABLE_NETWORK": "1",
        }
    )
    warmup = warm_project(godot, env, report, args.timeout_seconds)
    if not warmup["ok"]:
        result = {
            "passed": False,
            "error": "Godot project import failed before production pack acceptance",
            "runner": {"warmup": warmup},
        }
        report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, ensure_ascii=False, indent=2))
        if temporary is not None:
            temporary.cleanup()
        return 1
    command = [
        str(godot),
        "--headless",
        "--path",
        str(ROOT),
        "--script",
        str(PROBE),
    ]
    started = time.monotonic()
    peak_rss = 0
    timed_out = False
    stdout_log = report.with_suffix(report.suffix + ".stdout.log")
    stderr_log = report.with_suffix(report.suffix + ".stderr.log")
    with stdout_log.open("w", encoding="utf-8", errors="replace") as stdout_file, stderr_log.open(
        "w", encoding="utf-8", errors="replace"
    ) as stderr_file:
        process = subprocess.Popen(
            command,
            cwd=ROOT,
            env=env,
            stdout=stdout_file,
            stderr=stderr_file,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        while process.poll() is None:
            peak_rss = max(peak_rss, base.process_rss_bytes(process.pid))
            if time.monotonic() - started > args.timeout_seconds:
                timed_out = True
                process.kill()
                break
            time.sleep(0.25)
        process.wait(timeout=30)
    stdout = stdout_log.read_text(encoding="utf-8", errors="replace")
    stderr = stderr_log.read_text(encoding="utf-8", errors="replace")

    result: dict = {}
    if report.is_file():
        try:
            result = json.loads(report.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            result = {"passed": False, "error": f"invalid probe report: {exc}"}
    else:
        result = {"passed": False, "error": "probe report was not generated"}
    result["runner"] = {
        "warmup": warmup,
        "exit_code": process.returncode,
        "timed_out": timed_out,
        "elapsed_ms": round((time.monotonic() - started) * 1000, 3),
        "peak_rss_bytes": peak_rss,
        "stdout_log": str(stdout_log),
        "stderr_log": str(stderr_log),
        "stdout_tail": stdout[-8000:],
        "stderr_tail": stderr[-8000:],
    }
    result["passed"] = bool(result.get("passed", False)) and process.returncode == 0 and not timed_out
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if temporary is not None:
        temporary.cleanup()
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
