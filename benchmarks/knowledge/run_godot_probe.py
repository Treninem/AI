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
        command = [args.godot, "--headless", "--path", str(repo), "--script", args.script]
        started = time.perf_counter()
        peak_rss = 0
        proc = subprocess.Popen(command, cwd=repo, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace")
        timed_out = False
        while proc.poll() is None:
            peak_rss = max(peak_rss, base.process_rss_bytes(proc.pid))
            if time.perf_counter() - started > args.timeout_seconds:
                timed_out = True
                proc.kill()
                break
            time.sleep(0.05)
        stdout, stderr = proc.communicate(timeout=10)
        wall_ms = (time.perf_counter() - started) * 1000.0
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
            "stderr": stderr[-4000:],
        })
        report.write_text(json.dumps(parsed, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"report": str(report), "ok": bool(parsed.get("ok", False)), "return_code": proc.returncode}, ensure_ascii=False))
        return 0 if bool(parsed.get("ok", False)) and proc.returncode == 0 and not timed_out else 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
