from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INTEGRATION_WORKFLOW = ROOT / ".github" / "workflows" / "integration-gate.yml"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_integration_gate_runs_representative_cross_subsystem_contracts() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")

    # These tests belong to different subsystem owners. Running them together on
    # one SHA is the point of this lane: a green lane-specific CI is not enough
    # when another subsystem changed a shared contract underneath it.
    for test_path in (
        "tests/test_standalone_core_contract.py",
        "tests/test_autonomous_evolution_contract.py",
        "tests/test_api_accounts_sync.py",
        "tests/test_api_privacy_contract.py",
        "tests/test_release_core_gates.py",
        "tests/test_android_contract.py",
        "tests/test_voice_text.py",
        "tests/test_voice_configs.py",
        "tests/test_xtts_contract.py",
        "tests/test_knowledge_performance_contract.py",
        "tests/test_knowledge_performance_compare.py",
        "tests/test_core_candidate_promotion.py",
        "tests/test_api_runtime_resilience.py",
        "tests/test_project_master_contract.py",
    ):
        assert test_path in workflow

    for smoke_path in (
        "tests/self_reliance_smoke.gd",
        "tests/offline_autonomy_smoke.gd",
        "tests/autonomy_learning_smoke.gd",
        "tests/knowledge_registry_smoke.gd",
        "tests/knowledge_transaction_rollback_smoke.gd",
        "tests/api_gateway_smoke.gd",
        "tests/work_mode_smoke.gd",
        "tests/desktop_ui_smoke.gd",
        "tests/runtime_extension_smoke.gd",
        "tests/core_candidate_benchmark_smoke.gd",
        "tests/core_candidate_submitter_smoke.gd",
    ):
        assert smoke_path in workflow


def test_offline_core_execution_proof_stays_in_the_aggregated_gate() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    offline = read("tests/offline_autonomy_smoke.gd")
    standalone = read("tests/test_standalone_core_contract.py")

    assert "tests/offline_autonomy_smoke.gd" in workflow
    assert "fake.set_ollama_fallback_enabled(true)" in offline
    assert "fake.compatibility_calls != 0" in offline
    assert "offline AgentCore escaped into external compatibility" in offline
    assert 'str(status.get("provider", "")) != "aurorafox_local_vector"' in offline
    assert "core_runtime.chat_local_only" in standalone
    assert "chat_with_compatibility" in standalone


def test_research_to_knowledge_authority_is_part_of_same_sha_gate() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    contract = read("tests/test_autonomous_evolution_contract.py")

    assert "tests/test_autonomous_evolution_contract.py" in workflow
    assert "test_autonomous_research_is_promoted_only_through_curator" in contract
    assert 'assert "memory.learn(" not in collector' in contract
    assert 'assert \'if source == "local_documents":\' in curator' in contract
    assert 'assert \'"untrusted_external": true\' in curator' in contract
    assert 'assert \'"provenance_fingerprint"\' in curator' in contract


def test_account_a_b_and_guest_a_b_isolation_is_part_of_same_sha_gate() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    account_tests = read("tests/test_api_accounts_sync.py")

    assert "tests/test_api_accounts_sync.py" in workflow
    assert "test_two_accounts_and_two_guests_are_strictly_isolated" in account_tests
    assert 'accounts.create_guest("Guest A", "windows")' in account_tests
    assert 'accounts.create_guest("Guest B", "android")' in account_tests
    assert 'entity_id": "same-id"' in account_tests
    assert 'assert len({principal["id"] for principal in principals if principal}) == 4' in account_tests


def test_windows_package_gate_proves_installed_bundled_core_not_just_export_parse() -> None:
    workflow = read(".github/workflows/windows-package-ci.yml")

    assert "Build Windows package" in workflow
    assert "Silent install and installed-app smoke" in workflow
    assert "core_runtime\\engine\\llama-server.exe" in workflow
    assert "core_runtime\\engine\\aurorafox-core.gguf" in workflow
    assert "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5" in workflow
    assert "Installed AuroraFox Core integrity check failed" in workflow


def test_android_gate_builds_installs_and_launches_apk() -> None:
    workflow = read(".github/workflows/android-apk-artifact.yml")

    assert "Android release contract" in workflow
    assert "Build unsigned AuroraFox release APK" in workflow
    assert "Sign and validate installable APK" in workflow
    assert "Install and launch APK on Android 35" in workflow
    assert 'adb install -r "$APK_PATH"' in workflow
    assert "adb shell pidof com.aurorafox.ai" in workflow
    assert "AuroraFox crashed during Android launch smoke." in workflow


def test_safety_and_release_authority_contracts_are_aggregated() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    release_contract = read("tests/test_release_core_gates.py")

    for smoke in (
        "tests/runtime_extension_smoke.gd",
        "tests/core_candidate_benchmark_smoke.gd",
        "tests/core_candidate_submitter_smoke.gd",
        "tests/knowledge_transaction_rollback_smoke.gd",
    ):
        assert smoke in workflow

    assert "test_promotion_workflow_cannot_access_release_signing_secrets" in release_contract
    assert "test_signed_release_is_blocked_by_core_gates" in release_contract


def test_python_regressions_are_split_into_owner_routable_steps() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    for step_name in (
        "Voice text contract",
        "Voice config and acoustic-evidence contract",
        "Voice optional XTTS contract",
        "Large Knowledge performance contract",
        "Large Knowledge comparable regression contract",
        "Candidate promotion workflow trust-boundary contract",
        "Updater repair and signed-floor compatibility contract",
        "API runtime resilience contract",
        "Master-log coordination contract",
    ):
        assert step_name in workflow


def test_integration_gate_is_not_mistaken_for_visual_or_physical_device_acceptance() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")

    # Headless UI and emulator/package gates are useful regression gates, but
    # they must not be labelled as human visual acceptance or physical-device
    # acceptance. Those remain explicit final acceptance items in the master log.
    assert "headless UI regression smoke (not visual acceptance)" in workflow
    assert "physical-device acceptance is separate" in workflow


def test_active_lane_workflows_become_visible_to_integration_when_they_land() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")

    # OCR, real-Core benchmark and Work/Computer reliability lanes are
    # independently ACTIVE. Their absence is PENDING, not a failure. Large
    # Knowledge contracts have landed and are required immediately.
    for marker in (
        "local-ocr-ci.yml",
        "core-benchmarks.yml",
        "work-computer-reliability.yml",
        "tests/test_local_ocr.py",
        "benchmarks/core/**",
        "benchmarks/knowledge/**",
        "tests/test_knowledge_performance_contract.py",
        "tests/test_knowledge_performance_compare.py",
    ):
        assert marker in workflow
