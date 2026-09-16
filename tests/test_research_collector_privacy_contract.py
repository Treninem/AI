from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COLLECTOR = ROOT / "agent" / "research_collector.gd"


def _read() -> str:
    return COLLECTOR.read_text(encoding="utf-8")


def _collect_body(text: str) -> str:
    start = text.index("func collect(query: String) -> Dictionary:")
    end = text.index("\nfunc _collect_github", start)
    return text[start:end]


def test_autonomous_research_never_scans_personal_documents() -> None:
    text = _read()
    collect = _collect_body(text)

    assert "_collect_local_documents" not in text
    assert "USERPROFILE" not in text
    assert 'path_join("Documents")' not in text
    assert '"research_scope": "external_observations_only"' in collect
    assert '"personal_files_scanned": false' in collect


def test_collector_remains_observation_only_and_curator_gated() -> None:
    text = _read()

    assert "memory.learn(" not in text
    assert "import_knowledge_text(" not in text
    assert '"curation_required": true' in text
    assert '"learned": 0' in text
    assert "research_completed.emit(report)" in text


def test_external_response_memory_is_bounded_before_parsing() -> None:
    text = _read()

    assert "const MAX_RESPONSE_BYTES := 2 * 1024 * 1024" in text
    assert "const REQUEST_TIMEOUT_SECONDS := 20.0" in text
    assert "req.timeout = REQUEST_TIMEOUT_SECONDS" in text
    assert "req.body_size_limit = MAX_RESPONSE_BYTES" in text
    assert "request_result != HTTPRequest.RESULT_SUCCESS" in text
    assert "body.substr(0, MAX_RESPONSE_BYTES)" in text


def test_research_audit_log_has_bounded_rotation() -> None:
    text = _read()

    assert 'const LOG_BACKUP_PATH := "user://agent/research.jsonl.1"' in text
    assert "const MAX_LOG_BYTES := 8 * 1024 * 1024" in text
    assert '"audit_log_limit_bytes": MAX_LOG_BYTES' in text
    assert "_rotate_log_if_needed()" in text
    assert "if size < MAX_LOG_BYTES:" in text
    assert "DirAccess.rename_absolute(log_abs, backup_abs)" in text


def test_source_failures_are_visible_and_bounded() -> None:
    text = _read()
    collect = _collect_body(text)

    assert "const MAX_SOURCE_ERRORS := 16" in text
    assert "var _request_errors: Array = []" in text
    assert "_request_errors.clear()" in collect
    assert "var complete_failure := items.is_empty() and not source_errors.is_empty()" in collect
    assert "var partial := not items.is_empty() and not source_errors.is_empty()" in collect
    assert '"ok": not complete_failure' in collect
    assert '"partial": partial' in collect
    assert '"source_error_count": source_errors.size()' in collect
    assert 'report["error"] = "All autonomous research sources failed"' in collect
    assert "func _record_request_error" in text
    assert "if _request_errors.size() >= MAX_SOURCE_ERRORS:" in text
    assert '_record_request_error("json_parse"' in text
    assert '_record_request_error("request_result"' in text
    assert '_record_request_error("http"' in text
