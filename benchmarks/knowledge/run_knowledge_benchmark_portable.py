#!/usr/bin/env python3
"""Portable entrypoint for the AuroraFox Knowledge benchmark.

Fresh Windows Godot runners may start a ``--script`` process before its isolated
profile has populated the project/global script-class metadata used by depended
production scripts. The project itself parses successfully in editor mode, so
this adapter warms *the same isolated HOME/APPDATA* before a Windows benchmark
child and also keeps benchmark-side production handles dynamically typed. No
production source is rewritten.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys
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
UNTYPED_INFERRED_VAR = re.compile(r"\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*:=")
WARM_SENTINEL = ".godot-profile-warmed"


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
            changed += 1
    if changed != len(SCRIPT_NAMES):
        raise RuntimeError(
            f"portable harness transform incomplete: {changed}/{len(SCRIPT_NAMES)} script handles found"
        )

    # Dynamic Script handles make inferred locals ambiguous on Godot 4.7. Keep
    # this relaxation confined to the generated benchmark copy.
    text = UNTYPED_INFERRED_VAR.sub(r"var \1: Variant =", text)
    target.write_text(text, encoding="utf-8")
    return target


def warm_isolated_windows_profile(
    godot: str,
    repo: Path,
    user_root: Path,
    env: dict[str, str],
    timeout_seconds: int,
    log_dir: Path,
    tag: str,
) -> dict[str, Any]:
    """Populate Godot metadata in the exact profile used by the benchmark child.

    The workflow-level editor parse uses the runner's default profile. Benchmark
    cases intentionally replace HOME/APPDATA for isolation, which is exactly the
    condition that previously reproduced missing global class registrations on
    Windows. Warm each isolated case once; Linux does not need this workaround.
    """
    if sys.platform != "win32":
        return {"ok": True, "required": False, "performed": False}
    sentinel = user_root / WARM_SENTINEL
    if sentinel.exists():
        return {"ok": True, "required": True, "performed": False, "cached": True}

    stdout_path = log_dir / f"{tag}.warm.stdout.log"
    stderr_path = log_dir / f"{tag}.warm.stderr.log"
    command = [godot, "--headless", "--editor", "--path", str(repo), "--quit"]
    started = time.perf_counter()
    try:
        with stdout_path.open("wb") as stdout_file, stderr_path.open("wb") as stderr_file:
            proc = subprocess.run(
                command,
                cwd=repo,
                env=env,
                stdout=stdout_file,
                stderr=stderr_file,
                timeout=max(30, min(120, timeout_seconds)),
                check=False,
            )
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "required": True,
            "performed": True,
            "timed_out": True,
            "error": "isolated Windows Godot editor warm-up timed out",
            "stdout_log": str(stdout_path),
            "stderr_log": str(stderr_path),
        }
    wall_ms = (time.perf_counter() - started) * 1000.0
    if proc.returncode != 0:
        return {
            "ok": False,
            "required": True,
            "performed": True,
            "return_code": proc.returncode,
            "wall_ms": wall_ms,
            "error": "isolated Windows Godot editor warm-up failed",
            "stdout_log": str(stdout_path),
            "stderr_log": str(stderr_path),
        }
    sentinel.write_text("ok\n", encoding="utf-8")
    return {
        "ok": True,
        "required": True,
        "performed": True,
        "return_code": proc.returncode,
        "wall_ms": wall_ms,
        "stdout_log": str(stdout_path),
        "stderr_log": str(stderr_path),
    }


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

    warm = warm_isolated_windows_profile(godot, repo, user_root, env, timeout_seconds, log_dir, tag)
    if not warm.get("ok"):
        return {
            "ok": False,
            "error": warm.get("error", "isolated Windows Godot warm-up failed"),
            "runner_return_code": int(warm.get("return_code", 1) or 1),
            "runner_wall_ms": float(warm.get("wall_ms", 0.0)),
            "peak_rss_bytes": 0,
            "timed_out": bool(warm.get("timed_out", False)),
            "stdout_log": str(stdout_path),
            "stderr_log": str(stderr_path),
            "portable_dynamic_harness": True,
            "isolated_profile_warmup": warm,
        }

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
            "isolated_profile_warmup": warm,
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
