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


def test_spreadsheet_budgets_are_visible_persisted_and_exported_without_old_clamps():
    for key, env in [("spreadsheet_max_cells", "AURORAFOX_FILE_SPREADSHEET_MAX_CELLS"), ("xls_max_rows", "AURORAFOX_FILE_XLS_MAX_ROWS")]:
        assert key in CLIENT and key in SETTINGS and env in CLIENT and env in SERVICE
    assert "cells >= 50000" not in SERVICE
    assert "range(min(sheet.nrows, 10000))" not in SERVICE
    assert '"output_truncated":' in SERVICE
    assert 'MAX_SPREADSHEET_CELLS}|{MAX_XLS_ROWS}' in SERVICE


def test_listing_search_limits_are_owned_on_windows_and_defaults_honor_lower_limits():
    for key, env in [("tree_max_items", "AURORAFOX_FILE_TREE_MAX_ITEMS"), ("search_max_results", "AURORAFOX_FILE_SEARCH_MAX_RESULTS"), ("search_excerpt_chars", "AURORAFOX_FILE_SEARCH_EXCERPT_CHARS")]:
        assert key in CLIENT and key in SETTINGS and env in CLIENT and env in SERVICE
    assert 'default=min(2000, MAX_TREE_ITEMS)' in SERVICE
    assert 'default=min(20, MAX_CACHE_SEARCH_RESULTS)' in SERVICE
    assert '"excerpt_truncated": len(content) > MAX_CACHE_EXCERPT_CHARS' in SERVICE
    assert '"more_results": "unknown" if limit_reached else "none"' in SERVICE
    windows_tree = CLIENT.split('func tree(', 1)[1].split('func search_cache', 1)[0].split('if OS.get_name() != "Windows"', 1)[1]
    assert 'clampi(max_items, 1, 5000)' not in windows_tree
    assert 'int(owner_limits().get("tree_max_items", 5000))' in windows_tree
