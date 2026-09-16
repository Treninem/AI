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


def test_code_specialist_does_not_restore_direct_external_provider_path() -> None:
    source = read("scripts/code_specialist.gd")
    lower = source.lower()
    assert "ai_client.base_url" not in source
    assert "/api/chat" not in lower
    assert "httprequest.new()" not in lower
    assert "await general_ai.chat(" in source


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
