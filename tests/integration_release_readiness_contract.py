from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "integration-gate.yml"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_integration_gate_is_same_sha_and_cancels_stale_runs() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "Checkout exact SHA" in workflow
    assert "cancel-in-progress: true" in workflow
    assert "branches: [main]" in workflow


def test_representative_subsystems_are_aggregated_without_owning_production_code() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    required = (
        "tests/test_standalone_core_contract.py",
        "tests/test_autonomous_evolution_contract.py",
        "tests/test_research_evidence_lifecycle_contract.py",
        "tests/test_research_collector_privacy_contract.py",
        "tests/test_research_source_resilience_contract.py",
        "tests/test_api_accounts_sync.py",
        "tests/test_api_privacy_contract.py",
        "tests/test_api_request_limits.py",
        "tests/test_api_server_hardening.py",
        "tests/test_release_core_gates.py",
        "tests/test_android_contract.py",
        "tests/test_voice_text.py",
        "tests/test_voice_configs.py",
        "tests/test_knowledge_performance_contract.py",
        "tests/test_knowledge_performance_compare.py",
        "tests/test_knowledge_stress_gates.py",
        "tests/test_core_candidate_promotion.py",
        "tests/test_api_runtime_resilience.py",
        "tests/test_project_master_contract.py",
    )
    for marker in required:
        assert marker in workflow


def test_godot_cross_subsystem_smokes_remain_visible_after_one_failure() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    for marker in (
        "tests/self_reliance_smoke.gd",
        "tests/offline_autonomy_smoke.gd",
        "tests/autonomy_learning_smoke.gd",
        "tests/research_evidence_lifecycle_smoke.gd",
        "tests/research_collector_privacy_smoke.gd",
        "tests/research_source_resilience_smoke.gd",
        "tests/knowledge_registry_smoke.gd",
        "tests/knowledge_transaction_rollback_smoke.gd",
        "tests/api_gateway_smoke.gd",
        "tests/work_mode_smoke.gd",
        "tests/work_mode_store_smoke.gd",
        "tests/runtime_extension_smoke.gd",
        "tests/core_candidate_benchmark_smoke.gd",
        "tests/core_candidate_submitter_smoke.gd",
        "tests/desktop_ui_smoke.gd",
    ):
        assert marker in workflow
    assert "if: always()" in workflow
    assert "INTEGRATION_SMOKE_FAILED" in workflow
    assert "uses: actions/upload-artifact@v4" in workflow


def test_offline_core_normal_path_contract_is_still_local_only() -> None:
    standalone = read("tests/test_standalone_core_contract.py")
    agent = read("scripts/agent_core.gd")
    assert "core_runtime.chat_local_only" in standalone
    assert "chat_with_compatibility" in standalone
    assert "await ai.chat(messages)" in agent
    assert "chat_with_compatibility" not in agent


def test_research_promotion_keeps_untrusted_authority_boundary() -> None:
    curator = read("agent/learning_curator.gd")
    collector = read("agent/research_collector.gd")
    assert '"untrusted_external": true' in curator
    assert "provenance_fingerprint" in curator
    assert "import_knowledge_text" in curator
    assert "memory.learn(" not in collector


def test_research_source_resilience_is_same_sha_covered() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    contract = read("tests/test_research_source_resilience_contract.py")
    smoke = read("tests/research_source_resilience_smoke.gd")

    assert "Research source resilience contract" in workflow
    assert "tests/test_research_source_resilience_contract.py" in workflow
    assert "tests/research_source_resilience_smoke.gd" in workflow
    assert "backoff" in contract.lower() or "retry" in contract.lower()
    assert "query" in contract.lower()
    assert "source" in smoke.lower()


def test_code_specialist_does_not_restore_direct_external_provider_path() -> None:
    source = read("scripts/code_specialist.gd")
    lower = source.lower()
    assert "ai_client.base_url" not in source
    assert "/api/chat" not in lower
    assert "httprequest.new()" not in lower
    assert "await general_ai.chat(" in source


def test_work_computer_landing_makes_ui_core_routing_mandatory() -> None:
    lane_workflow_path = ROOT / ".github" / "workflows" / "work-computer-reliability.yml"
    if not lane_workflow_path.exists():
        return

    lane_workflow = lane_workflow_path.read_text(encoding="utf-8")
    client = read("scripts/computer_client.gd")
    registry = read("scripts/tool_registry.gd")
    overlay = read("scripts/computer_overlay.gd")

    # Once the reliability lane lands, service-side goal planning must stay
    # fail-closed and the only executable surface is the protected primitive set.
    assert "local_core_planning_required" in client
    assert "set_computer_control_enabled" in client
    for primitive in ("computer_action", "computer_screenshot", "computer_windows"):
        assert primitive in registry

    # The UI must then be compatible on that same SHA: high-level planning is
    # owned by bundled AuroraFox Core, never by ComputerClient.run()/plan().
    assert "computer.run(" not in overlay
    assert "computer.plan(" not in overlay
    assert "set_computer_control_enabled" in overlay
    assert "run_task(" in overlay

    for required_gate in (
        "tests/computer_agent_reliability_test.py",
        "tests/computer_agent_routing_contract_test.py",
        "tests/work_reliability_store_smoke.gd",
        "tests/work_computer_e2e_control_smoke.gd",
        "tests/work_computer_attempt_safety_smoke.gd",
        "tests/work_computer_e2e_uncertain_result_smoke.gd",
        "tests/work_computer_master_stop_smoke.gd",
    ):
        assert required_gate in lane_workflow


def test_local_ocr_landing_keeps_offline_packaging_and_knowledge_gates() -> None:
    lane_workflow_path = ROOT / ".github" / "workflows" / "local-ocr-ci.yml"
    if not lane_workflow_path.exists():
        return

    lane_workflow = lane_workflow_path.read_text(encoding="utf-8")
    for required in (
        "pytest -q tests/test_local_ocr.py",
        "tests/local_ocr_knowledge_smoke.gd",
        "windows-portable-ocr",
        "android-ocr",
        "rus.traineddata",
        "eng.traineddata",
        "network_required",
        "external_ai_required",
    ):
        assert required in lane_workflow
    assert "OpenAI|Gemini|Claude|Ollama" in lane_workflow


def test_core_benchmark_landing_keeps_real_offline_code_specialist_proof() -> None:
    lane_workflow_path = ROOT / ".github" / "workflows" / "core-benchmarks.yml"
    if not lane_workflow_path.exists():
        return

    lane_workflow = lane_workflow_path.read_text(encoding="utf-8")
    runner = read("benchmarks/core/run_windows_code_specialist_smoke.ps1")
    smoke = read("benchmarks/core/code_specialist_smoke.gd")

    assert "Run Work Mode startup regression smoke" in lane_workflow
    assert "Run real CodeSpecialist through bundled Core offline" in lane_workflow
    assert "Enforce real Core gate" in lane_workflow
    assert "New-NetFirewallRule" in runner
    assert "ollama" in runner.lower()
    assert "CodeSpecialist.new()" in smoke
    assert "analyze_request" in smoke
    assert "aurora_core_desktop" in smoke


def test_release_safety_boundaries_are_present() -> None:
    release_contract = read("tests/test_release_core_gates.py")
    assert "test_promotion_workflow_cannot_access_release_signing_secrets" in release_contract
    assert "test_signed_release_is_blocked_by_core_gates" in release_contract
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "Updater repair and signed-floor compatibility contract" in workflow
    assert "Candidate promotion workflow trust-boundary contract" in workflow


def test_integration_gate_does_not_claim_physical_or_visual_acceptance() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "headless UI regression smoke (not visual acceptance)" in workflow
    assert "physical-device acceptance is separate" in workflow
