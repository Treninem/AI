from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_existing_mutation_tournament_is_reused_not_reimplemented():
    existing = read("scripts/self_improver.gd")
    adapter = read("evolution_engine/evaluation/tournament_adapter.gd")
    assert "const MIN_MUTATIONS := 3" in existing
    assert "const MAX_MUTATIONS := 10" in existing
    assert "func run_mutation_tournament" in existing
    assert "winner_final_test" in existing
    assert "apply_generated_module(winner_proposal)" in existing
    assert "improver.run_mutation_tournament" in adapter
    assert "func _deterministic_candidate_score" not in adapter
    assert "func _judge_verified_candidates" not in adapter


def test_existing_safety_foundation_remains_authoritative():
    sandbox = read("scripts/sandbox_manager.gd")
    extensions = read("scripts/runtime_extension_manager.gd")
    autonomy = read("scripts/autonomy_settings_manager.gd")
    update_guard = read("scripts/update_autonomy_guard.gd")
    assert "func snapshot(" in sandbox
    assert "func rollback(" in sandbox
    assert "master_stop" in sandbox
    assert "func activate_staged(" in extensions
    assert '"master_enabled": true' in autonomy
    assert "func set_master_enabled" in autonomy
    assert "func status()" in update_guard
    assert '"paused_hot_improvements"' in update_guard


def test_controller_preserves_stage_then_activate_separation():
    controller = read("evolution_engine/core/evolution_controller.gd")
    assert "run_experiment" in controller
    assert 'result["activation_performed"] = false' in controller
    assert "activate_verified_winner" in controller
    assert "LEVEL_VERIFIED_ACTIVATION" in controller
    assert "activate_staged(stage_path, sha256)" in controller


def test_controller_requires_independent_evolution_evidence_gate():
    controller = read("evolution_engine/core/evolution_controller.gd")
    evidence = read("evolution_engine/evaluation/evidence_gate.gd")
    assert "evidence_gate.validate_tournament" in controller
    assert "population < MIN_MUTATIONS" in evidence
    assert "verified < MIN_MUTATIONS" in evidence
    assert "scoreboard_incomplete" in evidence
    assert "winner_not_verified" in evidence
    assert "final_verification_missing" in evidence
    assert "unsafe_stage_path" in evidence
    assert "invalid_stage_sha256" in evidence


def test_controller_fails_closed_on_master_stop_and_update_guard():
    controller = read("evolution_engine/core/evolution_controller.gd")
    foundation = read("evolution_engine/integration/foundation_adapter.gd")
    assert "master stop is active or unavailable" in controller
    assert "update_gate_status" in controller
    assert "UpdateAutonomyGuard is unavailable" in foundation
    assert '"master_enabled": false' in foundation
    assert '"updater_bound"' in foundation


def test_controller_does_not_bypass_core_tournament_requirement():
    controller = read("evolution_engine/core/evolution_controller.gd")
    assert "core_autonomous_promotion_enabled" in controller
    assert "autonomous_core_promotion_enabled" in controller
    assert "3..10 candidate Core tournament adapter" in controller
    assert "core_pipeline.run_candidate(" not in controller


def test_learning_reuses_existing_memory_and_knowledge():
    bridge = read("evolution_engine/learning/experience_bridge.gd")
    context = read("evolution_engine/learning/context_bridge.gd")
    assert 'memory.remember(KIND' in bridge
    assert "memory.retrieve(" in context
    assert "knowledge.search(" in context
    assert "memory.learn(" not in bridge
    assert "knowledge.import_text(" not in bridge
    assert "import_knowledge_text(" not in bridge


def test_evolution_isolated_from_release_paths():
    controller = read("evolution_engine/core/evolution_controller.gd")
    forbidden = (
        "update/update_manager.gd",
        ".github/workflows",
        "project/version.json",
        "project.godot",
        "release.yml",
    )
    for marker in forbidden:
        assert marker not in controller


def test_permission_policy_matches_declared_levels_and_population():
    policy = read("evolution_engine/safety/evolution_policy.gd")
    assert "const LEVEL_ANALYSIS := 0" in policy
    assert "const LEVEL_PROPOSAL := 1" in policy
    assert "const LEVEL_SANDBOX_EXPERIMENT := 2" in policy
    assert "const LEVEL_PROMOTION_HANDOFF := 3" in policy
    assert "const LEVEL_VERIFIED_ACTIVATION := 4" in policy
    assert "const MIN_MUTATIONS := 3" in policy
    assert "const MAX_MUTATIONS := 10" in policy


def test_evolution_is_not_wired_into_release_runtime_or_workflows_yet():
    project = read("project.godot")
    assert "evolution_engine/" not in project
    assert "AuroraEvolutionEngine" not in project
    for workflow in (ROOT / ".github" / "workflows").glob("*.yml"):
        text = workflow.read_text(encoding="utf-8")
        assert "evolution_engine/" not in text
        assert "AuroraEvolutionEngine" not in text


def test_foundation_requires_existing_memory_retrieval_contract():
    foundation = read("evolution_engine/integration/foundation_adapter.gd")
    assert '_require_method(missing, "memory", memory, "remember")' in foundation
    assert '_require_method(missing, "memory", memory, "retrieve")' in foundation


def test_evolution_serializes_against_existing_autonomous_cycle_and_reuses_rollback():
    controller = read("evolution_engine/core/evolution_controller.gd")
    guard = read("evolution_engine/safety/execution_guard.gd")
    foundation = read("evolution_engine/integration/foundation_adapter.gd")
    assert 'coordinator.get("_cycle_running")' in guard
    assert 'coordinator.set("autonomous_hot_improvements", false)' in guard
    assert 'coordinator.set("autonomous_hot_improvements", _saved_hot_improvements)' in guard
    assert "execution_guard.acquire()" in controller
    assert "execution_guard.release()" in controller
    assert "rollback_hot_extension" in controller
    assert "extensions.deactivate(clean_id)" in controller
    assert '_require_method(missing, "extensions", extensions, "deactivate")' in foundation
