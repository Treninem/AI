from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "scripts" / "knowledge_store.gd"
PROBE = ROOT / "benchmarks" / "knowledge" / "record_dedupe_shared_source_probe.gd"


def test_record_dedupe_is_content_scoped_with_source_provenance():
    store = STORE.read_text(encoding="utf-8")
    assert "var fingerprint := _id(source, text)" in store
    assert "_id(source + record_path, text)" not in store
    assert '"record_fingerprint": shared_fingerprint' in store
    assert '"source_record_id": fingerprint' in store
    assert '"normalized_seen": {}' in store


def test_runtime_probe_keeps_cross_source_lifecycle_requirement():
    probe = PROBE.read_text(encoding="utf-8")
    assert 'input_duplicate_records_in_a": 5' in probe
    assert 'int(before.get("a", 0)) == 1' in probe
    assert 'int(before.get("b", 0)) == 1' in probe
    assert "source_removal_preserves_shared_fact" in probe
    assert "unique_b_after.is_empty()" in probe
