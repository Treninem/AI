from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STORE = (ROOT / "scripts" / "knowledge_store.gd").read_text(encoding="utf-8")


def test_store_batches_structured_and_normalized_writes():
    assert "STRUCTURED_WRITE_BATCH := 128" in STORE
    assert "func _append_many(" in STORE
    assert '"structured_pending": []' in STORE
    assert '"normalized_pending": []' in STORE
    assert "func _flush_structured_state(" in STORE


def test_new_source_removal_can_skip_full_rewrite_fail_closed():
    assert "func _source_may_exist(" in STORE
    assert "func _rebuild_source_presence_cache(" in STORE
    assert "if not _source_presence_cache_valid:" in STORE
    assert "return true" in STORE
    assert '"filter_skipped": true' in STORE
