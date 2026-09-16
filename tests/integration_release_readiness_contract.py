from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INTEGRATION_WORKFLOW = ROOT / ".github" / "workflows" / "integration-gate.yml"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_integration_gate_runs_representative_cross_subsystem_contracts() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")

    for test_path in (
        "tests/test_standalone_core_contract.py",
        "tests/test_autonomous_evolution_contract.py",
        "tests/test_research_evidence_lifecycle_contract.py",
        "tests/test_research_collector_privacy_contract.py",
        "tests/test_api_accounts_sync.py",
        "tests/test_api_privacy_contract.py",
        "tests/test_api_request_limits.py",
        "tests/test_api_server_hardening.py",
        "tests/test_api_account_web.py",
        "tests/test_api_public_auth_limits.py",
        "tests/test_release_core_gates.py",
        "tests/test_android_contract.py",
        "tests/test_voice_text.py",
        "tests/test_voice_configs.py",
        "tests/test_xtts_contract.py",
        "tests/test_knowledge_performance_contract.py",
        "tests/test_knowledge_performance_compare.py",
        "tests/test_knowledge_stress_gates.py",
        "tests/test_core_candidate_promotion.py",
        "tests/test_api_runtime_resilience.py",
        "tests/test_project_master_contract.py",
    ):
        assert test_path in workflow

    for smoke_path in (
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
    assert "tests/test_research_evidence_lifecycle_contract.py" in workflow
    assert "tests/research_evidence_lifecycle_smoke.gd" in workflow
    assert "tests/test_research_collector_privacy_contract.py" in workflow
    assert "tests/research_collector_privacy_smoke.gd" in workflow
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


def test_knowledge_alias_removal_safety_is_part_of_same_sha_gate() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    probe = read("benchmarks/knowledge/dedupe_alias_removal_probe.gd")
    runner = read("benchmarks/knowledge/run_godot_probe.py")

    assert "Run Knowledge dedupe alias removal safety probe" in workflow
    assert "benchmarks/knowledge/dedupe_alias_removal_probe.gd" in workflow
    assert "AURORA_KNOWLEDGE_ALIAS_REMOVAL_RESULT=" in workflow
    assert '"canonical_survived": canonical_survived' in probe
    assert '"alias_detached": alias_detached' in probe
    assert "removing an alias/copy must not delete the canonical shared knowledge" in probe
    assert 'base.base_environment(root, {"scenario": "probe"})' in runner


def test_legacy_unregistered_rollback_is_part_of_same_sha_gate() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    probe = read("benchmarks/knowledge/legacy_unregistered_rollback_probe.gd")

    assert "Run legacy unregistered Knowledge rollback safety probe" in workflow
    assert "benchmarks/knowledge/legacy_unregistered_rollback_probe.gd" in workflow
    assert "AURORA_KNOWLEDGE_LEGACY_ROLLBACK_RESULT=" in workflow
    assert '"stable_after": stable_after' in probe
    assert '"partial_removed": partial_gone' in probe
    assert "failed reimport must preserve legacy source rows that predate sources.json" in probe


def test_knowledge_shared_lifecycle_and_crash_recovery_are_same_sha_covered() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")

    required = (
        "Run Knowledge record dedupe and shared-source lifecycle probe",
        "benchmarks/knowledge/record_dedupe_shared_source_probe.gd",
        "AURORA_KNOWLEDGE_RECORD_DEDUPE_RESULT=",
        "Run interrupted Knowledge reimport restart recovery",
        "benchmarks/knowledge/run_interrupted_import_recovery.py",
        "interrupted-reimport-recovery.json",
        "Run interrupted canonical Knowledge removal restart recovery",
        "benchmarks/knowledge/run_interrupted_removal_recovery.py",
        "interrupted-removal-recovery.json",
    )
    for marker in required:
        assert marker in workflow

    assert "--target-mb 32" in workflow
    assert "--target-mb 8" in workflow
    assert "timeout-minutes: 35" in workflow


def test_work_persistence_and_self_reliance_are_same_sha_covered() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    work_store = read("tests/work_mode_store_smoke.gd")
    work_ci = read(".github/workflows/work-mode-ci.yml")

    assert "tests/work_mode_smoke.gd" in workflow
    assert "tests/work_mode_store_smoke.gd" in workflow
    assert "tests/offline_autonomy_smoke.gd" in workflow
    assert ".github/workflows/work-mode-ci.yml" in workflow
    assert '"status":"completed"' in work_store
    assert '"progress":100' in work_store
    assert "AuroraFox Core offline self-reliance smoke" in work_ci
    assert "tests/offline_autonomy_smoke.gd" in work_ci


def test_api_request_body_limit_is_owner_routable_and_same_sha_covered() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    request_limit_tests = read("tests/test_api_request_limits.py")

    assert "API early request body limit contract" in workflow
    assert "tests/test_api_request_limits.py" in workflow
    assert "test_content_length_over_limit_is_rejected_before_downstream" in request_limit_tests
    assert "test_chunked_body_is_counted_and_rejected_without_content_length" in request_limit_tests
    assert "test_body_within_limit_reaches_downstream_unchanged" in request_limit_tests


def test_api_server_hardening_is_owner_routable_and_same_sha_covered() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    hardening = read("tests/test_api_server_hardening.py")

    assert "API server hardening contract" in workflow
    assert "tests/test_api_server_hardening.py" in workflow
    assert "test_production_account_routes_deliver_tokens_without_returning_them" in hardening
    assert "test_mail_transport_failure_never_exposes_raw_token" in hardening
    assert "test_production_account_creation_fails_closed_when_mail_is_unconfigured" in hardening
    assert "test_server_rejects_oversized_json_before_route_validation" in hardening


def test_public_account_links_and_auth_limits_are_same_sha_covered() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    account_web = read("tests/test_api_account_web.py")
    auth_limits = read("tests/test_api_public_auth_limits.py")

    assert "API public account web contract" in workflow
    assert "API public authentication rate limit contract" in workflow
    assert "tests/test_api_account_web.py" in workflow
    assert "tests/test_api_public_auth_limits.py" in workflow
    assert "test_email_verification_link_consumes_one_time_token" in account_web
    assert "test_password_reset_link_renders_form_and_resets_password" in account_web
    assert "test_public_auth_path_is_limited_per_client_and_endpoint" in auth_limits
    assert "test_forwarded_for_is_trusted_only_from_loopback_proxy" in auth_limits


def test_code_specialist_normal_path_is_bundled_core_only() -> None:
    source = read("scripts/code_specialist.gd")
    setup_start = source.find("func setup(")
    chat_start = source.find("func _chat_code(")
    assert setup_start >= 0
    assert chat_start >= 0
    setup_end = source.find("\nfunc ", setup_start + 1)
    chat_end = source.find("\nfunc ", chat_start + 1)
    setup = source[setup_start:] if setup_end < 0 else source[setup_start:setup_end]
    chat = source[chat_start:] if chat_end < 0 else source[chat_start:chat_end]
    lower = chat.lower()

    assert "ai_client.base_url" not in setup, (
        "CodeSpecialist.setup must not read the removed AIClient.base_url transport field; this crashes "
        "normal scene/Work startup after the bundled-Core migration."
    )
    assert "await general_ai.chat(messages, temperature)" in chat, (
        "CodeSpecialist normal generation must delegate to AIClient.chat(), whose normal path is bundled AuroraFox Core."
    )
    assert "httprequest.new()" not in lower
    assert "ollama" not in lower
    assert "/api/chat" not in lower


def test_python_regressions_are_split_into_owner_routable_steps() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    for step_name in (
        "Research evidence lifecycle contract",
        "Research collector privacy contract",
        "Voice text contract",
        "Voice config and acoustic-evidence contract",
        "Voice optional XTTS contract",
        "Large Knowledge performance contract",
        "Large Knowledge comparable regression contract",
        "Large Knowledge scaling blocker contract",
        "Candidate promotion workflow trust-boundary contract",
        "Updater repair and signed-floor compatibility contract",
        "API runtime resilience contract",
        "API early request body limit contract",
        "API server hardening contract",
        "API public account web contract",
        "API public authentication rate limit contract",
        "Master-log coordination contract",
    ):
        assert step_name in workflow


def test_godot_failure_does_not_hide_followup_smokes_or_diagnostics() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")

    for step_name in (
        "Run Knowledge record dedupe and shared-source lifecycle probe",
        "Run legacy unregistered Knowledge rollback safety probe",
        "Run interrupted Knowledge reimport restart recovery",
        "Run interrupted canonical Knowledge removal restart recovery",
        "Run offline Core Agent memory Knowledge Work API and safety smokes",
        "Run headless UI regression smoke (not visual acceptance)",
        "Record acceptance boundary",
        "Upload integration gate diagnostics",
    ):
        assert f"- name: {step_name}\n        if: always()" in workflow

    assert "status=0" in workflow
    assert "INTEGRATION_SMOKE_FAILED" in workflow
    assert 'exit "$status"' in workflow
    assert "uses: actions/upload-artifact@v4" in workflow
    assert "path: artifacts/integration-gate/" in workflow
    assert "if-no-files-found: warn" in workflow


def test_integration_gate_is_not_mistaken_for_visual_or_physical_device_acceptance() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
    assert "headless UI regression smoke (not visual acceptance)" in workflow
    assert "physical-device acceptance is separate" in workflow


def test_active_lane_workflows_become_visible_to_integration_when_they_land() -> None:
    workflow = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")

    for marker in (
        "local-ocr-ci.yml",
        "core-benchmarks.yml",
        "work-computer-reliability.yml",
        "work-mode-ci.yml",
        "research-quality-ci.yml",
        "tests/test_local_ocr.py",
        "benchmarks/core/**",
        "benchmarks/knowledge/**",
        "benchmarks/knowledge/dedupe_alias_removal_probe.gd",
        "benchmarks/knowledge/record_dedupe_shared_source_probe.gd",
        "benchmarks/knowledge/legacy_unregistered_rollback_probe.gd",
        "benchmarks/knowledge/run_godot_probe.py",
        "benchmarks/knowledge/run_interrupted_import_recovery.py",
        "benchmarks/knowledge/run_interrupted_removal_recovery.py",
        "tests/test_knowledge_performance_contract.py",
        "tests/test_knowledge_performance_compare.py",
        "tests/test_knowledge_stress_gates.py",
        "tests/test_research_collector_privacy_contract.py",
        "tests/research_collector_privacy_smoke.gd",
        "tests/work_mode_store_smoke.gd",
    ):
        assert marker in workflow
