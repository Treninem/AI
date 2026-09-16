#!/usr/bin/env python3
"""Portable entrypoint for the AuroraFox Knowledge benchmark.

Fresh Windows Godot runners can statically resolve a preloaded GDScript resource
as an external script class and reject dynamic production methods before the
benchmark starts. The production scripts are valid (the project/editor parse is
already green); this adapter writes an untracked runtime copy of the benchmark
script whose preloaded production-script handles are explicitly Variant-typed.
That keeps all calls dynamic without changing any production source.
"""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import time
from typing import Any

import run_knowledge_benchmark as base

SCRIPT_NAMES = (
    "KnowledgeDocumentImporterScript",
    "AuroraJsonStreamReaderScript",
    "KnowledgeSourceRegistryScript",
    "KnowledgeStoreScript",
    "LargeJsonKnowledgeImporterScript",
    "KnowledgeImportTransactionScript",
    "KnowledgeManagerScript",
    "AuroraLocalSemanticVectorizerScript",
    "MemoryStoreScript",
)
RUNTIME_NAME = ".knowledge_stress_benchmark.portable.gd"


def portable_harness(repo: Path) -> Path:
    source = repo / "benchmarks" / "knowledge" / "knowledge_stress_benchmark.gd"
    target = source.with_name(RUNTIME_NAME)
    text = source.read_text(encoding="utf-8")
    changed = 0
    for name in SCRIPT_NAMES:
        old = f"const {name} = preload("
        new = f"const {name}: Variant = preload("
        if old in text:
            text = text.replace(old, new, 1)
            changed += 1
        elif new in text:
            # Future direct source hardening remains compatible with this runner.
            changed += 1
    if changed != len(SCRIPT_NAMES):
        raise RuntimeError(
            f"portable harness transform incomplete: {changed}/{len(SCRIPT_NAMES)} script handles found"
        )
    target.write_text(text, encoding="utf-8")
    return target


def portable_run_godot_case(
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
    env = base.base_environment(user_root, case)
    if extra_env:
        env.update(extra_env)
    stdout_path = log_dir / f"{tag}.stdout.log"
    stderr_path = log_dir / f"{tag}.stderr.log"
    runtime_script = portable_harness(repo)
    script_arg = runtime_script.relative_to(repo).as_posix()
    command = [godot, "--headless", "--path", str(repo), "--script", script_arg]
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
        peak_rss = max(peak_rss, base.process_rss_bytes(proc.pid))
    wall_ms = (time.perf_counter() - started) * 1000.0
    stdout = stdout_path.read_text(encoding="utf-8", errors="replace")
    stderr = stderr_path.read_text(encoding="utf-8", errors="replace")
    parsed = base.parse_result(stdout)
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
            "portable_dynamic_harness": True,
        }
    )
    if timed_out or return_code != 0:
        parsed["ok"] = False
        if timed_out:
            parsed["error"] = f"bounded execution timeout after {timeout_seconds}s"
        elif not parsed.get("error"):
            parsed["error"] = f"Godot exited with {return_code}"
    return parsed


def main() -> int:
    # Functions in the imported module resolve this global at call time, so
    # restart checks also use the same portable execution path.
    base.run_godot_case = portable_run_godot_case
    return base.main()


if __name__ == "__main__":
    raise SystemExit(main())
