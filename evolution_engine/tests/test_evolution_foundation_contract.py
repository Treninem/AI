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
    assert "func activate_staged(" in extensions
    assert "func deactivate(" in extensions
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
    assert "experiments.mark_consumed(source_experiment_id" in controller


def test_activation_source_is_single_use_after_success():
    registry = read("evolution_engine/core/experiment_registry.gd")
    smoke = read("evolution_engine/tests/evolution_controller_smoke.gd")
    assert "func mark_consumed(" in registry
    assert 'record["status"] = "activated"' in registry
    assert "Consumed tournament winner was activated more than once" in smoke


def test_controller_requires_independent_evolution_evidence_gate():
    controller = read("evolution_engine/core/evolution_controller.gd")
    evidence = read("evolution_engine/evaluation/evidence_gate.gd")
    assert "evidence_gate.validate_tournament" in controller
    assert "population < MIN_MUTATIONS" in evidence
    assert "verified < MIN_MUTATIONS" in evidence
    assert "scoreboard_count_mismatch" in evidence
    assert "scoreboard_duplicate_candidate" in evidence
    assert "winner_missing_from_scoreboard" in evidence
    assert "winner_is_not_scoreboard_leader" in evidence
    assert "winner_stage_sha_mismatch" in evidence
    assert "final_verification_not_ok" in evidence
    assert "unsafe_stage_path" in evidence
    assert "invalid_stage_sha256" in evidence


def test_controller_fails_closed_on_master_stop_update_guard_and_managed_mode():
    controller = read("evolution_engine/core/evolution_controller.gd")
    foundation = read("evolution_engine/integration/foundation_adapter.gd")
    policy = read("evolution_engine/safety/evolution_policy.gd")
    managed = read("evolution_engine/safety/managed_mode_guard.gd")
    assert "master stop is active or unavailable" in controller
    assert "update_gate_status" in controller
    assert "managed_mode.permits_evolution()" in controller
    assert "Evolution managed mode is required" in controller
    assert "UpdateAutonomyGuard is unavailable" in foundation
    assert '"master_enabled": false' in foundation
    assert 'settings.get("master_enabled", false)' in policy
    assert 'coordinator.set("autonomous_hot_improvements", false)' in managed


def test_managed_mode_blocks_legacy_direct_hot_activation_path():
    controller = read("evolution_engine/core/evolution_controller.gd")
    managed = read("evolution_engine/safety/managed_mode_guard.gd")
    legacy = read("agent/autonomous_coordinator.gd")
    assert "enter_managed_mode" in controller
    assert "leave_managed_mode" in controller
    assert "managed_mode.fail_closed" in controller
    assert "permits_evolution" in managed
    assert "extensions.activate_staged" in legacy
    assert 'coordinator.set("autonomous_hot_improvements", false)' in managed


def test_controller_does_not_bypass_core_tournament_or_release_authority():
    controller = read("evolution_engine/core/evolution_controller.gd")
    assert "run_core_experiment" in controller
    assert "core_tournament.run" in controller
    assert "prepare_core_promotion" in controller
    assert "core_pipeline.run_candidate(" not in controller
    assert 'result["release_authority_granted"] = false' in controller
    assert '"release_authority_granted": false' in controller


def test_learning_reuses_existing_memory_and_knowledge_without_double_counting():
    bridge = read("evolution_engine/learning/experience_bridge.gd")
    context = read("evolution_engine/learning/context_bridge.gd")
    assert 'memory.remember(KIND' in bridge
    assert "candidate_ledger" in bridge
    assert "decision" in bridge
    assert "memory.retrieve(goal, safe_memory_limit, true, false)" in context
    assert "knowledge.search(goal, safe_knowledge_limit)" in context
    assert "memory.learn(" not in bridge
    assert "knowledge.import_text(" not in bridge
    assert "import_knowledge_text(" not in bridge


def test_candidate_ledger_records_rejected_and_verified_candidates():
    ledger = read("evolution_engine/learning/candidate_ledger.gd")
    assert "MAX_CANDIDATES := 10" in ledger
    assert '"outcome": "verified" if bool(row.get("verified", false)) else "rejected"' in ledger
    assert 'verification.get("stage"' in ledger
    assert 'verification.get("error"' in ledger
    assert 'candidate_id = "%s-%s"' in ledger


def test_controller_has_bounded_experiment_registry_metrics_and_decisions():
    controller = read("evolution_engine/core/evolution_controller.gd")
    registry = read("evolution_engine/core/experiment_registry.gd")
    metrics = read("evolution_engine/evaluation/metrics_adapter.gd")
    decision = read("evolution_engine/evaluation/decision_record.gd")
    assert "AuroraEvolutionExperimentRegistry.new()" in controller
    assert "AuroraEvolutionCandidateLedger.new()" in controller
    assert "AuroraEvolutionMetricsAdapter.new()" in controller
    assert "AuroraEvolutionDecisionRecord.new()" in controller
    assert "MAX_RECENT := 64" in registry
    assert "verification_ratio" in metrics
    assert '"memory": {"available": false}' in metrics
    assert "outcome" in decision
    assert "release_authority_granted" in decision


def test_async_recovery_invalidates_old_cycle_generation():
    controller = read("evolution_engine/core/evolution_controller.gd")
    assert "var _cycle_epoch := 0" in controller
    assert "var _active_cycle_token := 0" in controller
    assert "_cycle_is_current" in controller
    assert "_superseded_result" in controller
    assert "cycle_superseded" in controller
    assert "recover_stuck_cycle" in controller
    assert "_cycle_epoch += 1" in controller


def test_execution_and_core_locks_are_owned_and_explicitly_recoverable():
    guard = read("evolution_engine/safety/execution_guard.gd")
    core = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    assert "func stale_status(" in guard
    assert "recover_if_stale" not in guard
    assert "func emergency_release(" in guard
    assert "var _owns_pipeline_lock := false" in core
    assert "func _acquire_pipeline_lock(" in core
    assert "func _release_pipeline_lock(" in core
    assert "func emergency_release_owned_lock(" in core


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


def test_foundation_requires_existing_memory_and_extension_contracts():
    foundation = read("evolution_engine/integration/foundation_adapter.gd")
    assert '_require_method(missing, "memory", memory, "remember")' in foundation
    assert '_require_method(missing, "memory", memory, "retrieve")' in foundation
    assert '_require_method(missing, "extensions", extensions, "activate_staged")' in foundation
    assert '_require_method(missing, "extensions", extensions, "deactivate")' in foundation


def test_complete_cycle_entrypoint_records_analysis_and_decision():
    controller = read("evolution_engine/core/evolution_controller.gd")
    assert "func run_evolution_cycle(" in controller
    assert 'phase_changed.emit("cycle_analysis"' in controller
    assert 'phase_changed.emit("cycle_experiment"' in controller
    assert 'result["decision"] = decisions.build' in controller
    assert 'result["cycle_complete"] = true' in controller


def test_hot_tournament_collects_existing_candidate_signals_for_learning():
    adapter = read("evolution_engine/evaluation/tournament_adapter.gd")
    existing = read("scripts/self_improver.gd")
    ledger = read("evolution_engine/learning/candidate_ledger.gd")
    assert "signal mutation_candidate_completed" in existing
    assert 'has_signal("mutation_candidate_completed")' in adapter
    assert "_on_mutation_candidate_completed" in adapter
    assert 'result["candidates"] = _captured_candidates.duplicate(true)' in adapter
    assert 'var rows = result.get("candidates", [])' in ledger


def test_core_success_exposes_full_population_for_learning_not_only_finalists():
    core = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    assert '"scoreboard": _public_scoreboard(finalists)' in core
    assert '"candidates": _public_scoreboard(population)' in core


def test_execution_guard_reserves_legacy_coordinator_cycle_lock():
    guard = read("evolution_engine/safety/execution_guard.gd")
    assert 'coordinator.set("_cycle_running", true)' in guard
    assert 'coordinator.set("_cycle_running", false)' in guard
    assert "var _owns_coordinator_cycle_lock := false" in guard
    assert '"owns_coordinator_cycle_lock"' in guard


def test_learning_signal_uses_only_own_evolution_memory_as_generation_metadata():
    learning = read("evolution_engine/learning/learning_signal.gd")
    controller = read("evolution_engine/core/evolution_controller.gd")
    assert 'EVOLUTION_SOURCE := "aurorafox_evolution_engine"' in learning
    assert 'EVOLUTION_KIND := "evolution_experience"' in learning
    assert "raw_knowledge_instructions_used" in learning
    assert "knowledge_refs" in learning
    assert "learning_signal.derive" in controller
    assert "learning_signal.augment_goal" in controller
    assert 'phase_changed.emit("cycle_proposal"' in controller
    assert "func augment_goal(goal: String, learning_data: Dictionary)" in learning
    assert "var signal:" not in read("evolution_engine/learning/experience_bridge.gd")
    assert '"recovered_cycle_token": recovered_token' not in controller


def test_proposal_record_is_metadata_not_second_candidate_generator():
    proposal = read("evolution_engine/core/proposal_record.gd")
    assert "class_name AuroraEvolutionProposalRecord" in proposal
    assert "reuse_existing_aurorafox_foundation" in proposal
    assert "population_3_to_10" in proposal
    assert "no_release_authority" in proposal
    assert "ai.chat" not in proposal
    assert "propose_improvement" not in proposal
