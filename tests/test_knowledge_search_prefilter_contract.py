"""Source guard for AF-183's conservative raw JSONL prefilter.

The full-pack installed p95 remains a distinct required real-device gate.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STORE = (ROOT / "scripts/knowledge_store.gd").read_text(encoding="utf-8")


def block(start: str, end: str) -> str:
    return STORE.split(start, 1)[1].split(end, 1)[0]


def test_provenance_scoring_and_limit_contract_are_unchanged() -> None:
    search = block("func search(", "func _raw_search_row_misses(")
    assert search.index("_raw_search_row_misses(line, normalized_query, terms)") < search.index("JSON.parse_string(line)")
    assert 'str(item.get("text", "")).to_lower()' in search
    assert 'str(item.get("source", "")).to_lower()' in search
    assert 'str(item.get("kind", "")).to_lower()' in search
    assert "if text.contains(normalized_query):" in search
    assert "score += 5" in search
    assert "if text.contains(term): score += 2" in search
    assert "if source.contains(term): score += 1" in search
    assert "if kind.contains(term): score += 1" in search
    assert "_scored_trim(scored, limit)" in search
    assert 'out.append(row.get("item", {}))' in search
    assert "return out" in search


def test_prefilter_only_rejects_rows_missing_all_possible_score_terms() -> None:
    prefilter = block("func _raw_search_row_misses(", "func all_items()")
    # Treat JSON escapes as uncertain and let the authoritative parser decide.
    assert 'line.contains("\\\\u")' in prefilter
    assert "normalized_query.contains(ch)" in prefilter
    assert "if folded.contains(normalized_query):" in prefilter
    assert "if term.length() >= 2 and folded.contains(term):" in prefilter
    assert "return false" in prefilter
    assert prefilter.rstrip().endswith("return true")


def test_full_pack_perf_gate_remains_independent() -> None:
    master = (ROOT / "docs" / "PROJECT_MASTER_LOG.md").read_text(encoding="utf-8")
    assert "CHAT-2026-10-09-V15-AF183-KNOWLEDGE-SEARCH" in master
    assert "persistent index" in master
    assert "full-pack installed speed gate" in master
