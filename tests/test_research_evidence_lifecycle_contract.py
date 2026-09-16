from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CURATOR = ROOT / "agent" / "learning_curator.gd"
COLLECTOR = ROOT / "agent" / "research_collector.gd"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_curator_is_single_durable_learning_authority() -> None:
    collector = read(COLLECTOR)
    curator = read(CURATOR)
    assert "memory.learn(" not in collector
    assert '"curation_required": true' in collector
    assert "research_completed.emit(report)" in collector
    assert "ai.import_knowledge_text(" in curator
    assert 'if source == "local_documents":' in curator
    assert '"untrusted_external": true' in curator


def test_promotions_are_claim_scoped_and_revocable() -> None:
    curator = read(CURATOR)
    assert "func _promotion_source" in curator
    assert 'return "autonomous_research:%s:%s"' in curator
    assert 'ledger["promoted_source"] = scoped_source' in curator
    assert "func _invalidate_promoted_claim" in curator
    assert "ai.remove_knowledge_source(source)" in curator
    assert '"contradiction"' in curator
    assert '"stance_reversed"' in curator
    assert '"evidence_expired_or_superseded"' in curator
    assert 'replacement_reason = "evidence_superseded"' in curator
    assert 'replacement_reason = "evidence_retracted"' in curator


def test_retraction_notice_cannot_be_promoted_as_fresh_claim_evidence() -> None:
    curator = read(CURATOR)
    assert 'candidate["suppress_promotion"] = true' in curator
    assert '"status": "retraction_notice" if retraction_notice else "active"' in curator
    assert 'if bool(best.get("suppress_promotion", false)):' in curator
    assert '_queue_gap(claim_key, "retracted_evidence"' in curator
    assert '"retracted_evidence": return 100' in curator
    assert 'question = "Перепроверить отозванное доказательство независимыми источниками: " + title' in curator


def test_evidence_has_lifecycle_and_independent_source_model() -> None:
    curator = read(CURATOR)
    assert "DEFAULT_EVIDENCE_MAX_AGE_SECONDS" in curator
    assert "RESEARCH_EVIDENCE_MAX_AGE_SECONDS" in curator
    assert "COMMUNITY_EVIDENCE_MAX_AGE_SECONDS" in curator
    assert "func _record_claim_evidence" in curator
    assert "func _refresh_ledger" in curator
    assert "func _sweep_evidence_lifecycle" in curator
    assert 'old["status"] = "superseded"' in curator
    assert 'old["status"] = "retracted"' in curator
    assert 'observation["status"] = "stale"' in curator
    assert '"support_families"' in curator
    assert '"oppose_families"' in curator


def test_gap_queue_has_priority_backoff_and_restart_state() -> None:
    curator = read(CURATOR)
    assert "GAP_BASE_RETRY_SECONDS" in curator
    assert "GAP_MAX_RETRY_SECONDS" in curator
    assert "func _gap_priority" in curator
    assert "func mark_question_attempt" in curator
    assert 'updated["next_retry_unix"] = now + delay' in curator
    assert '"attempts": 0' in curator
    assert '"gap_questions": _gap_questions' in curator
    assert "func next_question" in curator


def test_provenance_and_state_are_durable_and_recoverable() -> None:
    curator = read(CURATOR)
    assert "STATE_BACKUP_PATH" in curator
    assert "STATE_TEMP_PATH" in curator
    assert "func provenance_for_claim" in curator
    assert "func _record_audit" in curator
    assert '"audit_events": _audit_events' in curator
    assert "DirAccess.rename_absolute(target_abs, backup_abs)" in curator
    assert "DirAccess.rename_absolute(temp_abs, target_abs)" in curator
    assert '"version": 2' in curator
