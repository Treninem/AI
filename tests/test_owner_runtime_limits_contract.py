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


def test_archive_listing_budgets_are_visible_and_cache_identity_covers_archive_controls():
    for key, env in [("archive_listing_max_chars", "AURORAFOX_ARCHIVE_LISTING_MAX_CHARS"), ("archive_listing_percent", "AURORAFOX_ARCHIVE_LISTING_PERCENT")]:
        assert key in CLIENT and key in SETTINGS and env in CLIENT and env in SERVICE
    assert "max_chars // 4" not in SERVICE
    assert "v5-owner-archive-budgets" in SERVICE
    assert '"listing_truncated": listing_truncated' in SERVICE


def test_android_directory_limit_reaches_native_traversal_without_fixed_ceiling():
    native = (ROOT / "android_plugin/plugin/src/main/java/com/aurorafox/runtime/AndroidFileRuntime.kt").read_text()
    assert "maxItems.coerceIn(1, 5000)" not in native
    assert "clampi(max_items, 1, 5000)" not in CLIENT
    assert "boundedDirectoryTree(root, maxItems)" in native
    assert '"truncated" to snapshot.truncated' in native


def test_android_parser_settings_are_immutable_per_job_and_reads_are_bounded():
    plugin = (ROOT / "android_plugin/plugin/src/main/java/com/aurorafox/runtime/GodotAndroidPlugin.kt").read_text()
    native = (ROOT / "android_plugin/plugin/src/main/java/com/aurorafox/runtime/AndroidFileRuntime.kt").read_text()
    ocr = (ROOT / "android_plugin/plugin/src/main/java/com/aurorafox/runtime/AndroidOcrRuntime.kt").read_text()
    assert 'plugin.call("startAnalyzeLocalFileWithLimits"' in CLIENT
    assert "runtime.analyze(path, question, visual, limits)" in plugin
    assert "FileAnalysisLimits.from(values)" in plugin
    assert "fileJobs.size >= limits.pendingJobs" in plugin
    assert "readOwnerBounded" in native and ".readBytes()" not in native
    assert "ocr.extract(file.absolutePath, limits)" in native
    for field in ["pdfBytes", "pdfPages", "ocrPages", "outputChars", "renderPixels", "inputPixels"]:
        assert "limits." + field in ocr
    for key in ["analysis_timeout_seconds", "android_pending_file_jobs", "ocr_max_input_pixels"]:
        assert key in CLIENT and key in SETTINGS
    assert "ANDROID_ANALYSIS_TIMEOUT_MS" not in CLIENT


def test_resource_policy_consumer_keys_are_persistable_and_owner_visible():
    import re
    policy = (ROOT / "scripts/owner_resource_policy.gd").read_text()
    defaults, labels = policy.split("const DEFAULTS := {", 1)[1].split("const LABELS := {", 1)
    default_keys = re.findall(r'^\s*"([a-z0-9_]+)":', defaults, re.M)
    label_keys = re.findall(r'^\s*"([a-z0-9_]+)":', labels.split("static var", 1)[0], re.M)
    assert len(default_keys) == len(set(default_keys))
    assert set(default_keys) == set(label_keys)
    for folder in ["scripts", "agent", "work", "voice", "evolution_engine"]:
        for path in (ROOT / folder).rglob("*.gd"):
            for line in path.read_text().splitlines():
                if line.lstrip().startswith("#"):
                    continue
                keys = re.findall(r'OwnerResourcePolicy\.value\("([a-z0-9_]+)"\)', line)
                keys += re.findall(r'OwnerResourcePolicy\.(?:clip|count)\(.*?, "([a-z0-9_]+)"\)', line)
                for key in keys:
                    assert key in default_keys, (path.relative_to(ROOT), key)


def test_voice_dsp_owner_controls_reach_the_backend_without_silent_fft_clamps():
    policy = (ROOT / "scripts/owner_resource_policy.gd").read_text()
    bridge = (ROOT / "voice/voice_bridge.gd").read_text()
    backend = (ROOT / "voice/python/aurora_voice_server.py").read_text()
    processor = (ROOT / "voice/python/processor.py").read_text()
    for name in ("voice_stft_n_fft", "voice_stft_hop_length"):
        assert name in policy
    for suffix in ("STFT_N_FFT", "STFT_HOP_LENGTH"):
        assert suffix in bridge
    assert 'processor_config["stft_n_fft"] = VOICE_LIMITS.stft_n_fft' in backend
    assert 'processor_config["stft_hop_length"] = VOICE_LIMITS.stft_hop_length' in backend
    assert 'CONFIG["processor"] = processor_config' in backend
    assert 'min(2048, requested)' not in processor
    assert 'max(64, min(n_fft // 2, hop))' not in processor


def test_native_extractor_cannot_save_acceptance_placeholders_as_knowledge():
    native = (ROOT / "android_plugin/plugin/src/main/java/com/aurorafox/runtime/AndroidFileRuntime.kt").read_text()
    assert "readXlsText(file, limits)" in native
    assert "readRarText(file, limits, textExt)" in native
    assert "readSevenZText(file, limits, textExt)" in native
    assert '"error_code" to "unsupported_format"' in native
    assert '"Аудиофайл принят."' not in native
    assert '"Архив $ext принят."' not in native
    audio = native.split("private fun analyzeAudio", 1)[1].split("private fun analyzeVideo", 1)[0]
    assert 'if (text.isBlank()) return error(' in audio
    assert 'return error(obj.optString("error"' in audio
    assert 'text.take(limits.outputChars)' in audio
    assert '"gif_frame_scope", "first_frame"' in native


def test_owner_limits_persist_in_private_storage_and_failed_saves_do_not_apply():
    persistence = (ROOT / "scripts/owner_limit_persistence.gd").read_text()
    assert 'PATH := "user://owner_operation_limits.cfg"' in persistence
    assert 'file.load(path)' in persistence and 'file.save(temporary)' in persistence
    assert 'DirAccess.rename_absolute' in persistence
    assert 'ProjectSettings.save()' not in CLIENT and 'ProjectSettings.save()' not in WEB
    file_apply = CLIENT.split("func apply_owner_limits", 1)[1].split("func _export_owner_limits_to_environment", 1)[0]
    web_apply = WEB.split("func apply_owner_limits", 1)[1].split("func owner_limits", 1)[0]
    assert file_apply.index('if saved != OK: return') < file_apply.index('ProjectSettings.set_setting(')
    assert web_apply.index('if saved != OK: return') < web_apply.index('set(key, next_limits[key])')
    assert '"files", next_limits, owner_limits_path' in file_apply
    assert '"web", next_limits, owner_limits_path' in web_apply
    assert 'if not bool(result.get("ok", false))' in SETTINGS


def test_windows_file_suboperation_limits_reach_private_settings_ui_and_consumers():
    formats = (ROOT / 'file_intelligence/extended_formats.py').read_text()
    keys = {
        'path_max_chars': 'AURORAFOX_FILE_PATH_MAX_CHARS',
        'question_max_chars': 'AURORAFOX_FILE_QUESTION_MAX_CHARS',
        'query_max_chars': 'AURORAFOX_FILE_QUERY_MAX_CHARS',
        'cache_max_bytes': 'AURORAFOX_FILE_CACHE_MAX_BYTES',
        'epub_max_chapters': 'AURORAFOX_EPUB_MAX_CHAPTERS',
        'archive_text_entry_max': 'AURORAFOX_ARCHIVE_TEXT_ENTRY_MAX',
        'archive_text_entries': 'AURORAFOX_ARCHIVE_TEXT_ENTRIES',
        'vision_timeout_seconds': 'AURORAFOX_FILE_VISION_TIMEOUT_SECONDS',
        'ollama_health_timeout_ms': 'AURORAFOX_FILE_OLLAMA_HEALTH_TIMEOUT_MS',
        'voice_health_timeout_ms': 'AURORAFOX_FILE_VOICE_HEALTH_TIMEOUT_MS',
        'ocr_max_render_scale_percent': 'AURORAFOX_OCR_MAX_RENDER_SCALE_PERCENT',
        'stt_timeout_seconds': 'AURORAFOX_FILE_STT_TIMEOUT_SECONDS',
        'video_timeout_seconds': 'AURORAFOX_FILE_VIDEO_TIMEOUT_SECONDS',
        'video_max_frames': 'AURORAFOX_FILE_VIDEO_MAX_FRAMES',
        'video_frame_interval_seconds': 'AURORAFOX_FILE_VIDEO_FRAME_INTERVAL_SECONDS',
        'video_frame_max_width': 'AURORAFOX_FILE_VIDEO_FRAME_MAX_WIDTH',
        'vision_image_max_width': 'AURORAFOX_FILE_VISION_IMAGE_MAX_WIDTH',
    }
    for key, env in keys.items():
        assert key in CLIENT and key in SETTINGS and env in CLIENT
        assert env in SERVICE or env in formats
    for token in ['max_length=PATH_MAX_CHARS', 'max_length=QUESTION_MAX_CHARS', 'max_length=QUERY_MAX_CHARS', '_trim_cache(CACHE_MAX_BYTES)', 'timeout=VISION_TIMEOUT_SECONDS', 'timeout=STT_TIMEOUT_SECONDS', 'timeout=VIDEO_TIMEOUT_SECONDS', '[:VIDEO_MAX_FRAMES]', 'VISION_IMAGE_MAX_WIDTH']:
        assert token in SERVICE


def test_agent_file_tools_reuse_platform_client_and_owner_limits():
    registry = (ROOT / 'scripts/tool_registry.gd').read_text()
    file_tools = registry.split('func _analyze_file', 1)[1].split('func _security_configuration_check', 1)[0]
    for token in ['await client.analyze_file(', 'await client.tree(', 'await client.search_cache(', 'manager.intelligence', '_path_allowed(path, false)']:
        assert token in file_tools
    assert 'clampi(' not in file_tools and '_http_json(' not in file_tools
    assert 'FileIntelligenceClient.new()' not in file_tools


def test_file_client_suboperation_deadlines_are_owner_persisted_and_routed():
    for key, default in [
        ('client_health_timeout_seconds', 4),
        ('client_tree_timeout_seconds', 60),
        ('client_cache_timeout_seconds', 30),
    ]:
        assert f'"{key}": {default}' in CLIENT
        assert f'"{key}": 0' in CLIENT
        assert key in SETTINGS
    assert '_request("/health", HTTPClient.METHOD_GET, {}, _client_timeout("client_health_timeout_seconds"))' in CLIENT
    assert '_client_timeout("client_tree_timeout_seconds"))' in CLIENT
    assert CLIENT.count('_client_timeout("client_cache_timeout_seconds"))') == 2
    assert 'req.timeout = timeout' in CLIENT
    assert 'return float(owner_limits()[key])' in CLIENT
    assert '_new_http_request(timeout)' in CLIENT
