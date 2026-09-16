from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_self_improver_runs_three_to_ten_distinct_mutations():
    text = read("scripts/self_improver.gd")
    assert "const MIN_MUTATIONS := 3" in text
    assert "const MAX_MUTATIONS := 10" in text
    assert "func run_mutation_tournament" in text
    assert "duplicate mutation rejected" in text
    assert "verified.size() < MIN_MUTATIONS" in text
    assert "apply_generated_module(winner_proposal)" in text
    assert "winner_final_test" in text


def test_tournament_competes_only_after_independent_tests():
    text = read("scripts/self_improver.gd")
    assert "await evaluate_generated_module(proposal)" in text
    assert 'tools.call_tool("workspace_test"' in text
    assert "_runtime_contract_test" in text
    assert "aurora_extension_self_test" in text
    assert "_judge_verified_candidates" in text
    assert "verified.sort_custom" in text
    assert "scoreboard" in text


def test_windows_and_android_support_autonomous_hot_mutations():
    improver = read("scripts/self_improver.gd")
    coordinator = read("agent/autonomous_coordinator.gd")
    assert 'OS.get_name() not in ["Windows", "Android"]' in improver
    assert 'platform == "Android"' in improver
    assert 'verification_mode": "restricted_gdscript_compile_contract"' in improver
    assert 'return OS.get_name() in ["Windows", "Android"]' in coordinator
    assert 'elif OS.get_name() == "Android":' in coordinator
    assert 'for name in ["read_file", "write_file"]' in coordinator


def test_coordinator_starts_learning_and_evolution_without_manual_trigger():
    text = read("agent/autonomous_coordinator.gd")
    assert "cycle_interval_seconds := 300.0" in text
    assert "mutation_cooldown_seconds := 900.0" in text
    assert "research_cooldown_seconds := 300.0" in text
    assert "mutation_population_size := 5" in text
    assert 'call_deferred("_run_initial_cycle")' in text
    assert "await run_autonomous_cycle()" in text
    assert "await research.collect(selected_goal)" in text
    assert "await improver.run_mutation_tournament(selected_goal, population_size)" in text
    assert "extensions.activate_staged" in text


def test_autonomous_research_is_promoted_only_through_curator():
    collector = read("agent/research_collector.gd")
    curator = read("agent/learning_curator.gd")

    # The collector is observation-only. Durable automatic learning in this
    # layer would bypass provenance, quality, dedupe and local-document gates.
    assert "memory.learn(" not in collector
    assert '"curation_required": true' in collector
    assert '"learned": 0' in collector
    assert "research_completed.emit(report)" in collector

    # LearningCurator is the single automatic promotion authority and stores
    # accepted observations as explicitly untrusted, provenance-bearing Core
    # Knowledge only after its gates have run.
    assert "research_completed.connect(_on_research_completed)" in curator
    assert 'if source == "local_documents":' in curator
    assert "_valid_external_url" in curator
    assert "MIN_PROMOTION_SCORE" in curator
    assert "_seen_content" in curator
    assert "ai.import_knowledge_text(" in curator
    assert '"kind": "research_knowledge"' in curator
    assert '"untrusted_external": true' in curator
    assert '"provenance_fingerprint": fingerprint' in curator
    assert '"quality_score": score' in curator


def test_verified_release_updates_are_applied_automatically_by_default():
    text = read("update/update_manager.gd")
    assert '"auto_check": true' in text
    assert '"auto_download": true' in text
    assert '"auto_apply": true' in text
    assert '"check_interval_hours": 1' in text
    assert 'response["download"] = await download_update(manual)' in text
    assert 'response["apply"] = apply_downloaded_update(manual)' in text
    assert "set_auto_apply" in text


def test_background_update_failures_remain_non_blocking():
    text = read("update/update_manager.gd")
    assert "func check_for_updates(manual := true)" in text
    assert "func download_update(manual := true)" in text
    assert "func apply_downloaded_update(manual := true)" in text
    assert "if visible: update_error.emit(message)" in text


def test_no_user_confirmation_gate_exists_in_evolution_path():
    improver = read("scripts/self_improver.gd").lower()
    coordinator = read("agent/autonomous_coordinator.gd").lower()
    overlay = read("scripts/self_improvement_overlay.gd").lower()
    for forbidden in (
        "await user_confirmation",
        "require_user_confirmation",
        "approval_required",
        "confirm_before_activation",
        "confirmationdialog",
    ):
        assert forbidden not in improver
        assert forbidden not in coordinator
        assert forbidden not in overlay
