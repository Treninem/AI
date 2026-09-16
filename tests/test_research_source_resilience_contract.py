from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COLLECTOR = ROOT / "agent" / "research_collector.gd"
WORKFLOW = ROOT / ".github" / "workflows" / "research-quality-ci.yml"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_source_health_backoff_is_persistent_and_bounded() -> None:
    text = read(COLLECTOR)

    assert 'const SOURCE_HEALTH_PATH := "user://agent/research_source_health.json"' in text
    assert "const SOURCE_BACKOFF_BASE_SECONDS := 5 * 60" in text
    assert "const SOURCE_BACKOFF_MAX_SECONDS := 6 * 60 * 60" in text
    assert "const SOURCE_BACKOFF_MAX_FAILURES := 8" in text
    assert "func _can_request_source" in text
    assert "func _record_source_failure" in text
    assert "func _record_source_success" in text
    assert "func _load_source_health" in text
    assert "func _save_source_health" in text
    assert '"next_retry_unix": now + delay' in text
    assert '"source_backoff": _source_health_report()' in text


def test_collection_has_global_budget_in_addition_to_request_timeout() -> None:
    text = read(COLLECTOR)

    assert "const REQUEST_TIMEOUT_SECONDS := 20.0" in text
    assert "const COLLECTION_BUDGET_SECONDS := 45.0" in text
    assert "_collection_deadline_msec = Time.get_ticks_msec() + int(COLLECTION_BUDGET_SECONDS * 1000.0)" in text
    assert "func _remaining_timeout_seconds" in text
    assert 'req.timeout = REQUEST_TIMEOUT_SECONDS' in text
    assert "if remaining_timeout < REQUEST_TIMEOUT_SECONDS:" in text
    assert "req.timeout = remaining_timeout" in text
    assert '_record_request_error("collection_budget"' in text
    assert '"collection_budget_seconds": COLLECTION_BUDGET_SECONDS' in text


def test_external_query_and_failure_telemetry_do_not_export_obvious_local_identifiers() -> None:
    text = read(COLLECTOR)

    assert "const MAX_EXTERNAL_QUERY_CHARS := 240" in text
    assert "const MAX_EXTERNAL_QUERY_WORDS := 24" in text
    assert "func _external_query" in text
    assert 'token.contains("@")' in text
    assert 'token.contains("\\\\")' in text
    assert 'token.contains("://")' in text
    assert 'lowered.begins_with("file:")' in text
    assert '"external_query_limited": true' in text
    assert '"external_query_char_count": external_query.length()' in text
    assert '"endpoint": _safe_endpoint(url)' in text
    assert '"url": url.substr' not in text
    assert "func _safe_endpoint" in text


def test_each_remote_source_has_an_explicit_health_identity() -> None:
    text = read(COLLECTOR)

    assert '_request_json("https://api.github.com/search/repositories' in text
    assert ', "github")' in text
    assert ', "stackoverflow")' in text
    assert 'var source_id := "reddit:" + subreddit' in text
    assert 'await _request_text(url, "arxiv", false)' in text
    assert '_record_source_failure("arxiv", 0, "arxiv_xml")' in text
    assert '_record_source_success("arxiv")' in text


def test_resilience_never_bypasses_curator_or_scans_personal_files() -> None:
    text = read(COLLECTOR)

    assert "memory.learn(" not in text
    assert "import_knowledge_text(" not in text
    assert "_collect_local_documents" not in text
    assert '"research_scope": "external_observations_only"' in text
    assert '"personal_files_scanned": false' in text
    assert '"curation_required": true' in text
    assert '"learned": 0' in text


def test_research_quality_workflow_runs_resilience_contract_and_smoke() -> None:
    workflow = read(WORKFLOW)

    assert "tests/test_research_source_resilience_contract.py" in workflow
    assert "tests/research_source_resilience_smoke.gd" in workflow
    assert "Run research source resilience smoke" in workflow
