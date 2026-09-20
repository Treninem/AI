from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_core_tournament_wraps_existing_pipeline_primitives():
    adapter = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    pipeline = read("scripts/core_improvement_pipeline.gd")
    for method in (
        "_select_target",
        "_read_res_source",
        "_propose",
        "_validate_candidate",
        "_verify_in_workspace",
        "_comparative_review",
        "_store_candidate",
        "_signed_update_busy",
    ):
        assert f"func {method}" in pipeline
        assert method in adapter


def test_core_tournament_never_uses_single_candidate_entrypoint():
    adapter = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    assert "run_candidate(" not in adapter
    assert "pipeline._store_candidate" in adapter
    assert "applied_to_dev_checkout" in adapter
    assert '"promotion": "signed_update"' in adapter
    assert "project_apply_file" not in adapter


def test_core_tournament_enforces_population_diversity_same_baseline_and_topup():
    adapter = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    assert "const MIN_MUTATIONS := 3" in adapter
    assert "const MAX_MUTATIONS := 10" in adapter
    assert "seen_hashes" in adapter
    assert "duplicate Core mutation rejected" in adapter
    assert "var original := str(source_result.get" in adapter
    assert "var baseline_sha := _sha256_text(original)" in adapter
    assert "pipeline._validate_candidate(target, original, proposal)" in adapter
    assert "pipeline._verify_in_workspace(clean_goal, target, content)" in adapter
    assert "population.size() < requested_count or finalists.size() < MIN_MUTATIONS" in adapter
    assert "population.size() < MAX_MUTATIONS" in adapter


def test_core_tournament_requires_three_verified_finalists_and_second_pass():
    adapter = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    assert "finalists.size() < MIN_MUTATIONS" in adapter
    assert "winner_final_verification" in adapter
    assert "winner_final_review" in adapter
    assert "pipeline._verify_in_workspace(clean_goal, target, winner_content)" in adapter
    assert "pipeline._comparative_review(clean_goal, target, original, winner_content" in adapter


def test_core_promotion_handoff_rechecks_baseline_and_never_grants_release_authority():
    adapter = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    controller = read("evolution_engine/core/evolution_controller.gd")
    assert "Core baseline changed after tournament; rerun tournament" in adapter
    assert "Pending Core winner content changed" in adapter
    assert "signed product update has priority" in adapter
    assert 'result["release_authority_granted"] = false' in controller
    assert '"release_authority_granted": false' in controller


def test_core_tournament_owns_existing_pipeline_running_lock():
    adapter = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    pipeline = read("scripts/core_improvement_pipeline.gd")
    assert "var _running := false" in pipeline
    assert "var _owns_pipeline_lock := false" in adapter
    assert 'pipeline.get("_running")' in adapter
    assert 'pipeline.set("_running", true)' in adapter
    assert 'pipeline.set("_running", false)' in adapter
    assert "func _acquire_pipeline_lock(" in adapter
    assert "func _release_pipeline_lock(" in adapter
    assert "func emergency_release_owned_lock(" in adapter


def test_pending_core_winner_is_bounded_expiring_and_single_use():
    adapter = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    assert "const MAX_PENDING_WINNERS := 5" in adapter
    assert "const PENDING_TTL_SECONDS := 86400" in adapter
    assert "_trim_pending()" in adapter
    assert "_pending_winners.erase(tournament_id)" in adapter
    assert "Unknown or expired Core tournament winner" in adapter
    assert "var _tournament_sequence := 0" in adapter


def test_core_public_candidate_preserves_reason_path_and_evidence():
    adapter = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    assert '"path": path' in adapter
    assert '"reason": reason' in adapter
    assert '"verification": candidate.get("verification", {})' in adapter
    assert '"failure": candidate.get("failure", {})' in adapter


def test_core_async_stages_recheck_owned_lock_token_before_stateful_handoff():
    adapter = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    assert "func _lock_token_current(" in adapter
    assert "func _lock_superseded(" in adapter
    assert 'return _lock_superseded("proposal", lock_token)' in adapter
    assert 'return _lock_superseded("winner_pending_store", lock_token)' in adapter
    assert 'return _lock_superseded("handoff_store", lock_token)' in adapter
    store_pos = adapter.index("var stored = pipeline._store_candidate")
    guard_pos = adapter.rfind('if not _lock_token_current(lock_token):', 0, store_pos)
    assert guard_pos >= 0
