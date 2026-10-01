from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT = (ROOT / "scripts" / "file_intelligence_client.gd").read_text(encoding="utf-8")
SERVICE = (ROOT / "file_intelligence" / "file_service.py").read_text(encoding="utf-8")
SETTINGS = (ROOT / "scripts" / "settings_overlay.gd").read_text(encoding="utf-8")
WEB = (ROOT / "scripts" / "public_web_manager.gd").read_text(encoding="utf-8")


def test_file_intelligence_resource_budgets_are_owner_visible_and_propagated():
    for marker in ["OWNER_LIMIT_DEFAULTS", "OWNER_LIMIT_ENV", "func owner_limits()", "func apply_owner_limits(", "AURORAFOX_FILE_REQUEST_MAX_TEXT", "_export_owner_limits_to_environment()"]:
        assert marker in CLIENT
    for marker in ["Пределы File Intelligence", "SettingsFileLimitsApply", "SettingsFileLimitsReset", "request_max_text_chars", "archive_max_expanded", "ocr_max_render_pixels"]:
        assert marker in SETTINGS
    assert "clampi(max_chars, 2000, 500000)" not in CLIENT
    assert "le=500000" not in SERVICE
    assert "MAX_REQUEST_TEXT_CHARS" in SERVICE


def test_public_reader_context_title_and_url_budgets_are_owner_controls():
    for marker in ["max_url_length", "max_title_chars", "context_chars"]:
        assert marker in WEB
        assert marker in SETTINGS
    assert "url.length() > 4096" not in WEB
    assert ".substr(0, 400)" not in WEB
    assert ".substr(0, 24000)" not in WEB
