#!/usr/bin/env python3
"""Run a small AuroraFox Knowledge Godot probe in isolated user storage."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

import run_knowledge_benchmark as base
import run_knowledge_benchmark_portable as portable


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--script", required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--timeout-seconds", type=int, default=120)
    parser.add_argument("--report", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = Path.cwd().resolve()
    report = Path(args.report)
    report.parent.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="aurora-knowledge-probe-"))
    try:
        env = base.base_environment(root, {"scenario": "probe"})
        warm = portable.warm_isolated_windows_profile(
            args.godot,
            repo,
            root,
            env,
            args.timeout_seconds,
            report.parent,
            report.stem,
        )
        if not warm.get("ok"):
            parsed = {
                "ok": False,
                "error": warm.get("error", "isolated Windows Godot warm-up failed"),
                "isolated_profile_warmup": warm,
            }
            report.write_text(json.dumps(parsed, ensure_ascii=False, indent=2), encoding="utf-8")
            print(json.dumps({"report": str(report), "ok": False, "warmup_failed": True}, ensure_ascii=False))
            return 1

        command = [args.godot, "--headless", "--path", str(repo), "--script", args.script]
        stdout_log = report.with_name(report.stem + ".stdout.log")
        stderr_log = report.with_name(report.stem + ".stderr.log")
        started = time.perf_counter()
        peak_rss = 0
        timed_out = False

        # Never leave a verbose Godot child blocked on an unread PIPE. Windows
        # pipe buffers are small enough that editor/script diagnostics can fill
        # them before SceneTree.quit() runs, producing a false 120 s "hang".
        # File-backed capture preserves full evidence while RSS/time monitoring
        # remains active and the timeout contract stays unchanged.
        with stdout_log.open("w", encoding="utf-8", errors="replace") as stdout_file, stderr_log.open(
            "w", encoding="utf-8", errors="replace"
        ) as stderr_file:
            proc = subprocess.Popen(
                command,
                cwd=repo,
                env=env,
                stdout=stdout_file,
                stderr=stderr_file,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            while proc.poll() is None:
                peak_rss = max(peak_rss, base.process_rss_bytes(proc.pid))
                if time.perf_counter() - started > args.timeout_seconds:
                    timed_out = True
                    proc.kill()
                    break
                time.sleep(0.05)
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                timed_out = True
                proc.kill()
                proc.wait(timeout=10)

        wall_ms = (time.perf_counter() - started) * 1000.0
        stdout = stdout_log.read_text(encoding="utf-8", errors="replace") if stdout_log.exists() else ""
        stderr = stderr_log.read_text(encoding="utf-8", errors="replace") if stderr_log.exists() else ""
        parsed = None
        for line in reversed(stdout.splitlines()):
            if line.startswith(args.prefix):
                try:
                    value = json.loads(line[len(args.prefix):])
                    parsed = value if isinstance(value, dict) else None
                except json.JSONDecodeError:
                    parsed = None
                break
        if parsed is None:
            parsed = {"ok": False, "error": "probe result marker missing"}
        parsed.update({
            "runner_return_code": int(proc.returncode or 0),
            "runner_wall_ms": wall_ms,
            "peak_rss_bytes": peak_rss,
            "timed_out": timed_out,
            "stdout_log": str(stdout_log),
            "stderr_log": str(stderr_log),
            "stderr": stderr[-4000:],
            "isolated_profile_warmup": warm,
        })
        report.write_text(json.dumps(parsed, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"report": str(report), "ok": bool(parsed.get("ok", False)), "return_code": proc.returncode}, ensure_ascii=False))
        return 0 if bool(parsed.get("ok", False)) and proc.returncode == 0 and not timed_out else 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
