from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "scripts" / "settings_overlay.gd").read_text(encoding="utf-8")
WEB = (ROOT / "scripts" / "public_web_manager.gd").read_text(encoding="utf-8")


def test_web_limits_are_visible_editable_persistent_and_resettable():
    for marker in [
        "Публичные ссылки",
        "SettingsWebPolicyApply",
        "SettingsWebPolicyReset",
        "max_urls_per_message",
        "max_redirects",
        "max_response_bytes",
        "request_timeout_seconds",
        "max_url_length",
        "max_title_chars",
        "context_chars",
        'current.call("apply_owner_limits", values, true)',
        "allow_greater = true",
    ]:
        assert marker in SETTINGS


def test_ui_distinguishes_owner_limits_from_external_access_controls():
    assert "Пределы принадлежат владельцу" in SETTINGS
    assert "CAPTCHA" in SETTINGS
    assert "access control" in SETTINGS
    assert "owner_limits" in WEB
    assert "apply_owner_limits" in WEB
