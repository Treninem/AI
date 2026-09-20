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


def test_core_tournament_enforces_population_diversity_and_same_baseline():
    adapter = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    assert "const MIN_MUTATIONS := 3" in adapter
    assert "const MAX_MUTATIONS := 10" in adapter
    assert "seen_hashes" in adapter
    assert "duplicate Core mutation rejected" in adapter
    assert "var original := str(source_result.get" in adapter
    assert "var baseline_sha := _sha256_text(original)" in adapter
    assert "pipeline._validate_candidate(target, original, proposal)" in adapter
    assert "pipeline._verify_in_workspace(clean_goal, target, content)" in adapter


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


def test_core_tournament_shares_existing_pipeline_running_lock():
    adapter = read("evolution_engine/evaluation/core_tournament_adapter.gd")
    pipeline = read("scripts/core_improvement_pipeline.gd")
    assert "var _running := false" in pipeline
    assert 'pipeline.get("_running")' in adapter
    assert 'pipeline.set("_running", true)' in adapter
    assert 'pipeline.set("_running", false)' in adapter
