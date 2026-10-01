from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WEB = (ROOT / "scripts" / "public_web_manager.gd").read_text(encoding="utf-8")
MAIN = (ROOT / "scripts" / "main.gd").read_text(encoding="utf-8")
TOOLS = (ROOT / "scripts" / "tool_registry.gd").read_text(encoding="utf-8")
LOG = (ROOT / "docs" / "PROJECT_MASTER_LOG.md").read_text(encoding="utf-8")


def test_user_url_read_is_also_private_knowledge_import():
    assert "var durable := true" in WEB
    assert '"imported_via": "user_public_url"' in WEB
    assert '"untrusted_external": true' in WEB
    assert '"instruction_authority": false' in WEB
    assert 'public_web.process_user_message(shown)' in MAIN
    assert "_relevant_task_text" in WEB
    assert ".substr(0, context_chars)" in WEB
    assert '"context_chars": context_chars' in WEB


def test_public_reader_has_bounded_ssrf_and_redirect_controls():
    for marker in [
        "DEFAULT_MAX_REDIRECTS",
        "DEFAULT_MAX_RESPONSE_BYTES",
        "DEFAULT_REQUEST_TIMEOUT_SECONDS",
        "private_network_denied",
        "169 and b == 254",
        "request.max_redirects = 0",
        "credentials_denied",
        "owner_decision_required",
        "apply_owner_limits",
        '"owner_adjustable": true',
    ]:
        assert marker in WEB


def test_access_controls_are_reported_not_bypassed():
    for marker in [
        "authentication_required",
        "access_restricted",
        "access_denied",
        "interactive_access_required",
        "CAPTCHA",
    ]:
        assert marker in WEB
    assert "публичные ссылки читаются и запоминаются" in LOG


def test_legacy_http_tool_uses_the_hardened_reader():
    body = TOOLS.split("func _http_get", 1)[1].split("func _read_file", 1)[0]
    assert "PublicWebManager.new()" in body
    assert "read_public_url" in body
    assert "HTTPRequest.new()" not in body
