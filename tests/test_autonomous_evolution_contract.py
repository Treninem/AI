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


def test_autonomous_research_is_promoted_to_long_term_knowledge():
    text = read("agent/research_collector.gd")
    assert "memory.learn(" in text
    assert '"research_knowledge"' in text
    assert '"learned": learned' in text


def test_verified_release_updates_are_applied_automatically_by_default():
    text = read("update/update_manager.gd")
    assert '"auto_check": true' in text
    assert '"auto_download": true' in text
    assert '"auto_apply": true' in text
    assert '"check_interval_hours": 1' in text
    assert 'response["apply"] = apply_downloaded_update()' in text
    assert "set_auto_apply" in text


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
