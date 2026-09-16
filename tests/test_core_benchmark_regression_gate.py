from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "benchmarks" / "core"


def load(name: str):
    return json.loads((BENCH / name).read_text(encoding="utf-8"))


def evaluator():
    spec = importlib.util.spec_from_file_location("aurora_core_evaluator", BENCH / "evaluate_report.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sample_report(*, cold=10000, warm=1000, tps=20.0, rss=1500, wall=50000, passed=True):
    required = load("scenarios.json")["required_scenarios"]
    return {
        "schema_version": 1,
        "suite": "aurorafox_core_quality_v1",
        "status": "completed",
        "platform": "Windows",
        "machine": {
            "os": "Windows",
            "arch": "x86_64",
            "logical_processors": 4,
            "processor_identifier": "benchmark-cpu",
        },
        "environment": {
            "remote_ai_allowed": False,
            "fixture_core_used": False,
        },
        "core": {
            "prepared_sha256": "model-sha",
            "engine_version": "llama.cpp benchmark-version",
        },
        "scenarios": [
            {"id": name, "passed": passed, "runtime": "aurora_core_desktop"}
            for name in required
        ],
        "performance": {
            "cold_first_response_ms": cold,
            "warm_median_ms": warm,
            "throughput_equivalent_tps": tps,
            "peak_rss_mb": rss,
            "suite_wall_ms": wall,
            "timeout_count": 0,
        },
    }


def test_required_scenarios_cover_requested_real_core_surface() -> None:
    names = set(load("scenarios.json")["required_scenarios"])
    expected = {
        "clean_start_state", "offline_network_guard", "ollama_absent", "bundled_core_identity", "cold_start_first_response",
        "warm_followup", "russian_dialog", "english_dialog", "instruction_following",
        "multi_turn_context", "local_memory_retrieval", "core_knowledge_retrieval",
        "simple_planning", "safe_tool_selection", "text_generation",
        "code_generation_explanation", "basic_reasoning", "corrupted_input",
        "long_context", "compatibility_switch_isolation", "repeatability",
    }
    assert expected <= names


def test_quality_gate_rejects_missing_failed_or_external_runtime_scenarios() -> None:
    ev = evaluator()
    spec = load("scenarios.json")
    report = sample_report()
    assert ev.evaluate_quality(report, spec["required_scenarios"])["passed"]

    report["scenarios"][0]["passed"] = False
    assert not ev.evaluate_quality(report, spec["required_scenarios"])["passed"]

    report = sample_report()
    report["scenarios"][1]["runtime"] = "ollama_legacy"
    result = ev.evaluate_quality(report, spec["required_scenarios"])
    assert not result["passed"]
    assert result["forbidden_runtime_names"] == ["ollama_legacy"]


def test_quality_gate_requires_explicit_allowed_local_runtime_for_inference_rows() -> None:
    ev = evaluator()
    spec = load("scenarios.json")
    policy = load("performance_policy.json")

    report = sample_report()
    result = ev.enrich_report(report, policy, spec)["evaluation"]["quality_gate"]
    assert result["passed"], result
    assert result["allowed_local_runtimes"] == ["aurora_core_desktop", "aurora_core_native"]

    report = sample_report()
    target = next(row for row in report["scenarios"] if row["id"] == "cold_start_first_response")
    target["runtime"] = ""
    result = ev.enrich_report(report, policy, spec)["evaluation"]["quality_gate"]
    assert not result["passed"]
    assert result["missing_runtime_scenarios"] == ["cold_start_first_response"]

    report = sample_report()
    target = next(row for row in report["scenarios"] if row["id"] == "cold_start_first_response")
    target["runtime"] = "mystery_runtime"
    result = ev.enrich_report(report, policy, spec)["evaluation"]["quality_gate"]
    assert not result["passed"]
    assert result["unexpected_runtime_scenarios"] == [
        {"scenario": "cold_start_first_response", "runtime": "mystery_runtime"}
    ]

    report = sample_report()
    target = next(row for row in report["scenarios"] if row["id"] == "cold_start_first_response")
    target["runtime"] = "aurora_core_android"
    result = ev.enrich_report(report, policy, spec)["evaluation"]["quality_gate"]
    assert not result["passed"]
    assert result["unexpected_runtime_scenarios"] == [
        {"scenario": "cold_start_first_response", "runtime": "aurora_core_android"}
    ]


def test_quality_gate_rejects_corrupt_identity_duplicate_and_fixture_reports() -> None:
    ev = evaluator()
    spec = load("scenarios.json")
    policy = load("performance_policy.json")

    report = sample_report()
    duplicate = next(row.copy() for row in report["scenarios"] if row["id"] == "cold_start_first_response")
    report["scenarios"].append(duplicate)
    quality = ev.enrich_report(report, policy, spec)["evaluation"]["quality_gate"]
    assert not quality["passed"]
    assert quality["duplicate_scenario_ids"] == ["cold_start_first_response"]

    for field, value, result_field in (
        ("schema_version", 2, "schema_valid"),
        ("status", "running", "status_complete"),
        ("suite", "wrong-suite", "suite_valid"),
    ):
        report = sample_report()
        report[field] = value
        quality = ev.enrich_report(report, policy, spec)["evaluation"]["quality_gate"]
        assert not quality["passed"], (field, quality)
        assert quality[result_field] is False

    report = sample_report()
    report["platform"] = "Plan9"
    report["machine"]["os"] = "Plan9"
    quality = ev.enrich_report(report, policy, spec)["evaluation"]["quality_gate"]
    assert not quality["passed"]
    assert quality["runtime_policy_missing"] is True

    report = sample_report()
    report["machine"]["os"] = "Android"
    quality = ev.enrich_report(report, policy, spec)["evaluation"]["quality_gate"]
    assert not quality["passed"]
    assert quality["platform_identity_mismatch"] is True

    report = sample_report()
    report["environment"]["fixture_core_used"] = True
    quality = ev.enrich_report(report, policy, spec)["evaluation"]["quality_gate"]
    assert not quality["passed"]
    assert quality["fixture_core_used"] is True

    report = sample_report()
    report["environment"]["remote_ai_allowed"] = True
    quality = ev.enrich_report(report, policy, spec)["evaluation"]["quality_gate"]
    assert not quality["passed"]
    assert quality["remote_ai_allowed"] is True


def test_performance_gate_uses_relative_and_absolute_noise_thresholds() -> None:
    ev = evaluator()
    policy = load("performance_policy.json")
    baseline = sample_report()

    small_noise = sample_report(cold=13000, warm=1250, tps=17.0, rss=1650, wall=60000)
    result = ev.evaluate_performance(small_noise, policy, baseline)
    assert result["passed"], result
    assert result["relative_gate_applied"]

    regression = sample_report(cold=17000, warm=2200, tps=10.0, rss=2100, wall=85000)
    result = ev.evaluate_performance(regression, policy, baseline)
    assert not result["passed"]
    assert {x["metric"] for x in result["relative_failures"]} >= {
        "cold_first_response_ms", "warm_median_ms", "throughput_equivalent_tps", "peak_rss_mb"
    }


def test_machine_mismatch_disables_relative_gate_but_keeps_hard_limits() -> None:
    ev = evaluator()
    policy = load("performance_policy.json")
    baseline = sample_report()
    current = sample_report(cold=50000, warm=5000, tps=5.0, rss=2500, wall=150000)
    current["machine"]["processor_identifier"] = "different-cpu"
    result = ev.evaluate_performance(current, policy, baseline)
    assert result["passed"]
    assert not result["relative_gate_applied"]
    assert result["comparison_status"] == "baseline_machine_mismatch"

    current["performance"]["cold_first_response_ms"] = 130000
    result = ev.evaluate_performance(current, policy, baseline)
    assert not result["passed"]
    assert any(x["metric"] == "cold_first_response_ms" for x in result["hard_failures"])


def test_no_baseline_is_not_a_false_performance_failure() -> None:
    ev = evaluator()
    policy = load("performance_policy.json")
    result = ev.evaluate_performance(sample_report(), policy, None)
    assert result["passed"]
    assert result["comparison_status"] == "no_baseline"
    assert not result["relative_gate_applied"]


def test_invalid_baseline_fails_instead_of_silently_disabling_relative_checks() -> None:
    ev = evaluator()
    policy = load("performance_policy.json")
    current = sample_report()
    baseline = sample_report()
    baseline["performance"].pop("warm_median_ms")
    result = ev.evaluate_performance(current, policy, baseline)
    assert not result["passed"]
    assert result["comparison_status"] == "baseline_invalid"
    assert not result["relative_gate_applied"]
    assert any(x["metric"] == "warm_median_ms" for x in result["baseline_validation_failures"])
    assert any(x.get("reason") == "invalid_baseline" for x in result["hard_failures"])

    timed_out = sample_report()
    timed_out["performance"]["timeout_count"] = 1
    result = ev.evaluate_performance(current, policy, timed_out)
    assert not result["passed"]
    assert result["comparison_status"] == "baseline_invalid"
    assert any(x["metric"] == "timeout_count" for x in result["baseline_validation_failures"])


def test_timeout_is_always_a_hard_failure() -> None:
    ev = evaluator()
    policy = load("performance_policy.json")
    report = sample_report()
    report["performance"]["timeout_count"] = 1
    result = ev.evaluate_performance(report, policy, None)
    assert not result["passed"]
    assert any(x["metric"] == "timeout_count" for x in result["hard_failures"])


def test_performance_gate_rejects_missing_or_non_positive_measurements() -> None:
    ev = evaluator()
    policy = load("performance_policy.json")
    required = (
        "cold_first_response_ms",
        "warm_median_ms",
        "throughput_equivalent_tps",
        "peak_rss_mb",
        "suite_wall_ms",
    )
    for metric in required:
        report = sample_report()
        report["performance"].pop(metric)
        result = ev.evaluate_performance(report, policy, None)
        assert not result["passed"], (metric, result)
        assert metric in result["missing_measurements"]

        report = sample_report()
        report["performance"][metric] = 0
        result = ev.evaluate_performance(report, policy, None)
        assert not result["passed"], (metric, result)
        assert metric in result["missing_measurements"]


def test_real_harness_uses_product_core_and_forbids_fake_or_external_inference() -> None:
    harness = (BENCH / "core_benchmark.gd").read_text(encoding="utf-8")
    runner = (BENCH / "run_windows_benchmark.ps1").read_text(encoding="utf-8")
    workflow = (ROOT / ".github" / "workflows" / "core-benchmarks.yml").read_text(encoding="utf-8")

    assert "AIClient.new()" in harness
    assert "AgentCore.new()" in harness
    assert "CognitionLayer.new()" in harness
    assert "AuroraBundledCoreModel.runtime_candidate()" in harness
    assert "set_ollama_fallback(true)" in harness
    assert "FakeOfflineCore" not in harness
    assert "chat_with_compatibility" not in harness
    assert "http://1.1.1.1/" in harness
    assert "New-NetFirewallRule" in runner
    assert "Get-Process" in runner and "ollama" in runner.lower()
    assert "_console.exe" in runner
    assert "network_guard_executables" in runner
    assert "godotProcessPaths" in runner
    assert "Get-Process -Name $processName" in runner
    assert "godot_process_paths_measured" in runner
    assert "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5" in runner
    assert ".Contains('machine')" in runner
    assert ".ContainsKey(" not in runner
    assert "prepare_bundled_windows_core.ps1" in workflow
    assert "run_windows_benchmark.ps1" in workflow
    assert "--check-only --script benchmarks/core/core_benchmark.gd" in workflow
    assert "actions/cache/restore@v4" in workflow
    assert "actions/cache/save@v4" in workflow
    assert "save-always: true" not in workflow


def test_runner_and_workflow_keep_setup_network_separate_from_measured_offline_phase() -> None:
    runner = (BENCH / "run_windows_benchmark.ps1").read_text(encoding="utf-8")
    workflow = (ROOT / ".github" / "workflows" / "core-benchmarks.yml").read_text(encoding="utf-8")
    prepare_pos = workflow.index("Prepare verified bundled AuroraFox Core")
    benchmark_pos = workflow.index("Run real bundled Core benchmark offline")
    assert prepare_pos < benchmark_pos
    assert "AURORAFOX_BENCHMARK_NETWORK_GUARD_ACTIVE" in runner
    assert "RemoteAddress Internet" in runner
    assert "Remove-NetFirewallRule" in runner
    assert "--baseline" in workflow


def test_code_specialist_normal_path_is_bundled_core_only() -> None:
    source = (ROOT / "scripts" / "code_specialist.gd").read_text(encoding="utf-8")
    assert "general_ai.chat(messages, temperature)" in source
    for forbidden in (
        "ai_client.base_url",
        "HTTPRequest.new()",
        "/api/chat",
        "qwen3-coder",
        "ollama_url",
    ):
        assert forbidden not in source


def test_memory_and_tool_scenarios_measure_distinct_capabilities() -> None:
    harness = (BENCH / "core_benchmark.gd").read_text(encoding="utf-8")
    # Memory retrieval is semantic; exact plain-text compliance is already a
    # separate instruction_following gate. Keep both signals in evidence.
    assert '"answer_exact_format": memory_exact_format' in harness
    assert 'memory_answer_has_marker and retrieval_has_marker' in harness
    # Safe tool selection must require a real local tool call, but should not
    # spend the scenario watchdog on a second, unrelated answer-synthesis LLM call.
    assert "tool_agent.max_steps = 1" in harness
    assert '_probe_calls == 1 and _probe_last_value == "GREEN-73"' in harness
    assert '"single_step_selection_gate": true' in harness


def test_code_specialist_has_real_offline_inference_gate() -> None:
    smoke = (BENCH / "code_specialist_smoke.gd").read_text(encoding="utf-8")
    runner = (BENCH / "run_windows_code_specialist_smoke.ps1").read_text(encoding="utf-8")
    workflow = (ROOT / ".github" / "workflows" / "core-benchmarks.yml").read_text(encoding="utf-8")

    assert "CodeSpecialist.new()" in smoke
    assert "specialist.analyze_request(" in smoke
    assert "set_ollama_fallback(true)" in smoke
    assert '"last_runtime", "")) == "aurora_core_desktop"' in smoke
    assert 'int(runtime_after.get("ollama_failures", -1)) == 0' in smoke
    assert "http://1.1.1.1/" in smoke
    assert "New-NetFirewallRule" in runner
    assert "RemoteAddress Internet" in runner
    assert "Get-Process" in runner and "ollama" in runner.lower()
    assert "run_windows_code_specialist_smoke.ps1" in workflow
    assert "code-specialist-smoke.json" in workflow
    assert "steps.code_specialist_smoke.outcome" in workflow
