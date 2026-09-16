from __future__ import annotations

import json
from pathlib import Path
import py_compile
import sys

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "benchmarks" / "knowledge" / "run_knowledge_benchmark.py"
GODOT = ROOT / "benchmarks" / "knowledge" / "knowledge_benchmark.gd"
WORKFLOW = ROOT / ".github" / "workflows" / "knowledge-performance.yml"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    require(RUNNER.is_file(), "benchmark orchestrator missing")
    require(GODOT.is_file(), "Godot benchmark runner missing")
    require(WORKFLOW.is_file(), "knowledge performance workflow missing")

    py_compile.compile(str(RUNNER), doraise=True)
    runner = RUNNER.read_text(encoding="utf-8")
    godot = GODOT.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    for target in ("10", "50", "100", "250"):
        require(target in runner, f"stress profile lost {target} MiB target")
    require("--include-500mb" in runner, "500 MiB opt-in stress contract missing")
    for scenario in (
        "import_search", "monolithic_json", "dedup_removal", "rollback",
        "restart_prepare", "restart_verify",
    ):
        require(f'"{scenario}"' in godot, f"scenario {scenario} missing")

    required_fields = (
        "dataset_size_bytes", "record_count", "chunk_count", "import_duration_ms",
        "records_per_sec", "mb_per_sec", "resulting_store_size_bytes",
        "source_removal_time_ms", "rollback_time_ms", "restart_load_time_ms",
        "duplicate_count", "p50_ms", "p95_ms", "p99_ms",
        "fingerprint_sha256", "network_required", "external_runtime_required",
        "ollama_required",
    )
    combined = runner + "\n" + godot
    for field in required_fields:
        require(field in combined, f"machine-readable field missing: {field}")

    require("potential_quadratic_growth" in runner, "N/2N/4N complexity diagnostic missing")
    require("peak_rss_bytes" in runner, "peak RSS measurement missing")
    require("physical_android_device_tested" in runner, "Android proof boundary missing")
    require("desktop_results_are_not_android_device_proof" in runner, "Android honesty contract missing")
    require("AURORA_KNOWLEDGE_BENCHMARK_OFFLINE" in runner, "offline execution guard missing")

    # Benchmark infrastructure must not gain network/remote-AI clients. Mentioning
    # invariant names in reports is allowed; importing/calling clients is not.
    forbidden_python = ("import requests", "import httpx", "urllib.request", "import socket")
    forbidden_godot = ("HTTPRequest", "HTTPClient", "chat_with_compatibility", "OpenAI", "Gemini", "Claude")
    for token in forbidden_python:
        require(token not in runner, f"network dependency added to benchmark: {token}")
    for token in forbidden_godot:
        require(token not in godot, f"remote/external path added to benchmark: {token}")

    require("workflow_dispatch:" in workflow, "manual stress workflow trigger missing")
    require("profile:" in workflow and "stress" in workflow, "workflow stress profile missing")
    require("actions/upload-artifact@v4" in workflow, "JSON report artifact upload missing")
    require("ubuntu-latest" in workflow, "Linux benchmark job missing")
    require("windows-latest" in workflow, "Windows benchmark job missing")
    require("knowledge-benchmark-report" in workflow, "report artifact naming missing")

    print(json.dumps({
        "ok": True,
        "contract": "large_knowledge_performance",
        "synthetic_large_fixtures": True,
        "committed_large_fixtures": False,
        "stress_targets_mb": [10, 50, 100, 250, 500],
        "offline": True,
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
