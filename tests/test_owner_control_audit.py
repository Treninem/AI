import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("owner_control_audit", ROOT / "tools" / "owner_control_audit.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def test_audit_is_machine_readable_and_does_not_claim_incomplete_inventory_is_done():
    report = MODULE.audit()
    assert report["schema"] == "aurorafox.owner-control-audit.v1"
    assert report["files_scanned"] > 100
    assert report["findings"] > 0
    assert report["complete"] is (report["counts"].get("unclassified", 0) == 0)


def test_web_limits_and_security_boundaries_have_explicit_different_classes():
    report = MODULE.audit()
    web = [item for item in report["items"] if item["path"] == "scripts/public_web_manager.gd"]
    assert any(item["class"] == "owner_adjustable" for item in web)
    assert any(item["class"] == "hard_boundary" for item in web)


def test_policy_explains_the_small_set_allowed_to_be_hard_boundaries():
    policy = MODULE.load_policy()
    principle = policy["principle"].lower()
    for required in ["authorization", "access control", "cryptographic", "master-stop", "secret", "untrusted-code"]:
        assert required in principle


def test_fixture_classification_does_not_hide_product_limits():
    policy = MODULE.load_policy()
    assert MODULE.classify("tests/example.gd", "var limit = 2", policy)[0] == "test_evidence"
    assert MODULE.classify("scripts/example.gd", "var limit = 2", policy)[0] == "unclassified"
    assert MODULE.classify("file_intelligence/file_service.py", 'MAX_FILE_BYTES = int(os.getenv("AURORAFOX_FILE_MAX_BYTES", "1024"))', policy)[0] == "owner_adjustable"


def test_reviewed_named_budgets_do_not_hide_remaining_literal_limits():
    policy = MODULE.load_policy()
    assert MODULE.classify("file_intelligence/file_service.py", "if size > MAX_FILE_BYTES:", policy)[0] == "owner_adjustable"
    assert MODULE.classify("file_intelligence/file_service.py", "for r in range(min(sheet.nrows, 10000)):", policy)[0] == "unclassified"
    assert MODULE.classify("security_workspace/runner.py", 'timeout = float(scope.get("timeout_seconds", 10))', policy)[0] == "owner_adjustable"
    assert MODULE.classify("scripts/public_web_manager.gd", 'if bytes.slice(0, 5) == signature:', policy)[0] == "format_structure"
    assert MODULE.classify("scripts/example.gd", '# LIMIT describes a control', policy)[0] == "documentation"
    assert MODULE.classify("scripts/example.gd", 'var LIMIT = 123 # explanatory comment', policy)[0] == "unclassified"


def test_native_reader_budgets_are_reviewed_without_hiding_arbitrary_literals():
    policy = MODULE.load_policy()
    base = "android_plugin/plugin/src/main/java/com/aurorafox/runtime/"
    for reader in ["ArchiveTextReader.kt", "EpubTextReader.kt", "TarTextReader.kt"]:
        assert MODULE.classify(base+reader, "val cap = limits.memberBytes", policy)[0] == "owner_adjustable"
        assert MODULE.classify(base+reader, "val x = Long.MAX_VALUE", policy)[0] == "format_structure"
        assert MODULE.classify(base+reader, "val LIMIT = 17", policy)[0] == "unclassified"
    assert MODULE.classify("android_plugin/plugin/src/test/java/Fixture.kt", "val limit = 2", policy)[0] == "test_evidence"
    assert MODULE.classify(base+"Unreviewed.kt", "val limit = 2", policy)[0] == "unclassified"


def test_native_limit_propagation_preserves_security_and_unknown_literals():
    policy = MODULE.load_policy()
    base = "android_plugin/plugin/src/main/java/com/aurorafox/runtime/"
    for name in ["AndroidFileRuntime.kt", "AndroidOcrRuntime.kt", "GodotAndroidPlugin.kt"]:
        assert MODULE.classify(base+name, "analyze(file, limits)", policy)[0] == "owner_adjustable"
        assert MODULE.classify(base+name, "val LIMIT = 17", policy)[0] == "unclassified"
        assert MODULE.classify(base+name, "val timeout = 99", policy)[0] == "unclassified"
    assert MODULE.classify(base+"AndroidFileRuntime.kt", "files.tree(path, maxItems)", policy)[0] == "owner_adjustable"
    assert MODULE.classify(base+"FileAnalysisLimits.kt", "val x = Int.MAX_VALUE", policy)[0] == "format_structure"
    assert MODULE.classify(base+"FileAnalysisLimits.kt", "require(limit >= 0)", policy)[0] == "owner_adjustable"
    assert MODULE.classify(base+"Example.kt", "/** budget documentation */", policy)[0] == "documentation"
    assert MODULE.classify(base+"Example.kt", "/** comment */ val LIMIT = 17", policy)[0] == "unclassified"
    assert MODULE.classify("scripts/public_web_manager.gd", "private_network_denied", policy)[0] == "hard_boundary"
    assert MODULE.classify("evolution_engine/tests/fixture.gd", "var limit = 2", policy)[0] == "test_evidence"
    assert MODULE.classify("evolution_engine/core/runtime.gd", "var limit = 2", policy)[0] == "unclassified"


def test_core_wait_and_frame_structure_do_not_hide_other_desktop_caps():
    policy = MODULE.load_policy()
    assert MODULE.classify("scripts/core_progress_stream.gd", "pending = pending.slice(scan + 1)", policy)[0] == "format_structure"
    assert MODULE.classify("scripts/core_progress_stream.gd", "byte_budget = budget", policy)[0] == "owner_adjustable"
    assert MODULE.classify("scripts/desktop_local_runtime.gd", "var wait_limits := CoreWaitPolicy.limits()", policy)[0] == "owner_adjustable"
    assert MODULE.classify("scripts/desktop_local_runtime.gd", 'var max_tokens := clampi(int(options.get("max_tokens", default_max_tokens)), 64, 8192)', policy)[0] == "unclassified"
    for path in ["scripts/core_progress_stream.gd", "scripts/core_wait_policy.gd", "scripts/desktop_local_runtime.gd", "scripts/settings_overlay.gd", "scripts/file_intelligence_client.gd"]:
        assert MODULE.classify(path, "var LIMIT = 17", policy)[0] == "unclassified"
        assert MODULE.classify(path, "var timeout = 99", policy)[0] == "unclassified"


def test_owner_ui_review_leaves_minima_geometry_and_generic_deadlines_unknown():
    policy = MODULE.load_policy()
    assert MODULE.classify("scripts/file_intelligence_client.gd", '"max_file_bytes": 1024,', policy)[0] == "unclassified"
    assert MODULE.classify("scripts/file_intelligence_client.gd", '"max_text_chars": 1,', policy)[0] == "owner_adjustable"
    assert MODULE.classify("scripts/file_intelligence_client.gd", 'var timeout_ms := int(limits.get("analysis_timeout_seconds", 600)) * 1000', policy)[0] == "owner_adjustable"
    assert MODULE.classify("scripts/file_intelligence_client.gd", 'req.timeout = timeout', policy)[0] == "owner_adjustable"
    assert MODULE.classify("scripts/settings_overlay.gd", 'slider.max_value = maximum', policy)[0] == "unclassified"
    assert MODULE.classify("scripts/settings_overlay.gd", 'field.max_value = 99', policy)[0] == "unclassified"
    ui = (ROOT / "scripts/settings_overlay.gd").read_text()
    assert "field.max_value = 4096.0\n\tfield.allow_greater = true" in ui
    assert MODULE.classify("benchmarks/core/core_benchmark.gd", 'req.timeout = 3.0', policy)[0] == "test_evidence"
    assert MODULE.classify("scripts/core_benchmark.gd", 'req.timeout = 3.0', policy)[0] == "unclassified"


def test_automatic_web_redirects_are_security_boundary_before_owner_count_rule():
    policy = MODULE.load_policy()
    assert MODULE.classify("scripts/public_web_manager.gd", "request.max_redirects = 0", policy)[0] == "hard_boundary"
    assert MODULE.classify("scripts/public_web_manager.gd", "for redirect_index in range(max_redirects + 1):", policy)[0] == "owner_adjustable"


def test_reviewed_gui_and_capture_policy_keeps_unknown_caps_and_trailing_code_visible():
    policy = MODULE.load_policy()
    positive = [
        ("computer/computer_service.py", 'if cap and len(text) > cap:', "owner_adjustable"),
        ("computer/computer_service.py", 'while max_results > 0 and len(_action_cache) > max_results:', "owner_adjustable"),
        ("computer/computer_service.py", 'room = len(chunk) if capture_bytes == 0 else max(0, capture_bytes - captured_bytes)', "owner_adjustable"),
        ("computer/computer_service.py", 'worker.join(timeout=seconds)', "hard_boundary"),
        ("scripts/computer_request_guard.gd", 'captured["_sandbox_items"] = OwnerResourcePolicy.value("sandbox_tree_items")', "owner_adjustable"),
    ]
    for path, line, kind in positive:
        assert MODULE.classify(path, line, policy)[0] == kind
        assert MODULE.classify(path, line + '; FIXED_LIMIT = 17', policy)[0] == "unclassified"
        assert MODULE.classify("other/" + path, line, policy)[0] == "unclassified"
    for path in ["computer/computer_service.py", "scripts/computer_request_guard.gd"]:
        for unknown in ["LIMIT = 17", "timeout = 99", "capture_bytes = min(capture_bytes, 17)"]:
            assert MODULE.classify(path, unknown, policy)[0] == "unclassified"


def test_api_owner_policy_review_does_not_classify_new_arbitrary_caps():
    policy = MODULE.load_policy()
    cases = [
        ("api/request_limits.py", "if self.max_bytes > 0 and new_received > self.max_bytes:"),
        ("api/conversation_store.py", "if self.max_messages > 0:"),
        ("api/conversation_store.py", "(owner, conversation_id, budget if budget > 0 else -1),"),
    ]
    for path, statement in cases:
        assert MODULE.classify(path, statement, policy)[0] == "owner_adjustable"
        assert MODULE.classify(path, statement + " FIXED_LIMIT = 17", policy)[0] == "unclassified"
    assert MODULE.classify("api/request_limits.py", "if new_received > 17:", policy)[0] == "unclassified"
    assert MODULE.classify("api/conversation_store.py", "self.max_messages = max(20, max_messages)", policy)[0] == "unclassified"


def test_file_transport_owner_policy_preserves_unknown_caps():
    policy = MODULE.load_policy()
    path = "api/file_client.py"
    statement = "if self.max_file_bytes > 0 and len(raw) > self.max_file_bytes:"
    assert MODULE.classify(path, statement, policy)[0] == "owner_adjustable"
    assert MODULE.classify(path, statement + " FIXED_LIMIT = 17", policy)[0] == "unclassified"
    assert MODULE.classify(path, "timeout=180,", policy)[0] == "unclassified"


def test_api_text_budget_review_keeps_fixed_content_caps_visible():
    policy = MODULE.load_policy()
    assert MODULE.classify("api/server.py", "message: str = Field(min_length=1, max_length=MAX_API_CHAT_CHARS)", policy)[0] == "owner_adjustable"
    assert MODULE.classify("api/server.py", "message: str = Field(min_length=1, max_length=100000)", policy)[0] == "unclassified"


def test_provider_owner_review_preserves_arbitrary_response_caps():
    policy = MODULE.load_policy()
    statement = "if self.max_response_bytes > 0 and frame_bytes > self.max_response_bytes:"
    assert MODULE.classify("api/runtime_bridge.py", statement, policy)[0] == "owner_adjustable"
    assert MODULE.classify("api/runtime_bridge.py", statement + " FIXED_LIMIT = 17", policy)[0] == "unclassified"
    assert MODULE.classify("api/runtime_bridge.py", "while len(buffer) < 8 * 1024 * 1024:", policy)[0] == "unclassified"


def test_file_cache_zero_review_does_not_hide_fixed_provider_timeouts():
    policy = MODULE.load_policy()
    statement = 'VISION_TIMEOUT_SECONDS = _operational_budget_from_env("AURORAFOX_FILE_VISION_TIMEOUT_SECONDS", 180) or None'
    assert MODULE.classify("file_intelligence/file_service.py", statement, policy)[0] == "owner_adjustable"
    assert MODULE.classify("file_intelligence/file_service.py", statement + "; FIXED_LIMIT = 17", policy)[0] == "unclassified"
    assert MODULE.classify("file_intelligence/file_service.py", "requests.post(url, timeout=180)", policy)[0] == "unclassified"


def test_file_service_budget_propagation_and_health_controls_keep_unknown_caps_visible():
    policy = MODULE.load_policy()
    path = "file_intelligence/file_service.py"
    reviewed = "if len(items) >= req.max_items:"
    assert MODULE.classify(path, reviewed, policy)[0] == "owner_adjustable"
    assert MODULE.classify(path, reviewed + "  # FIXED_LIMIT = 17", policy)[0] == "unclassified"
    assert MODULE.classify(path, 'r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=None if OLLAMA_HEALTH_TIMEOUT_MS == 0 else OLLAMA_HEALTH_TIMEOUT_MS / 1000.0)', policy)[0] == "owner_adjustable"
    assert MODULE.classify(path, "scale = pixel_scale if scale_percent == 0 else min(scale_percent / 100.0, pixel_scale)", policy)[0] == "owner_adjustable"
    assert MODULE.classify(path, 'r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=1.5)', policy)[0] == "unclassified"
    assert MODULE.classify(path, "scale = min(2.0, math.sqrt(pixel_budget) / math.sqrt(width) / math.sqrt(height))", policy)[0] == "unclassified"


def test_file_client_deadline_review_keeps_diagnostic_and_filename_caps_visible():
    policy = MODULE.load_policy()
    path = "scripts/file_intelligence_client.gd"
    for statement, category in [
        ('req.timeout = timeout', 'owner_adjustable'),
        ('var chunk := src.get_buffer(mini(1024 * 1024, remaining))', 'format_structure'),
        ('await get_tree().create_timer(0.05).timeout', 'format_structure'),
        ('parsed["content"] = str(parsed.get("content", "")).substr(0, max_chars)', 'owner_adjustable'),
    ]:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
    assert MODULE.classify(path, 'return out.substr(0, 120)', policy)[0] == 'unclassified'
    assert MODULE.classify(path, 'return {"ok": false, "http": code, "error": raw.substr(0, 4000)}', policy)[0] == 'unclassified'
    assert MODULE.classify(path, 'req.timeout = 4.0', policy)[0] == 'unclassified'


def test_api_body_accounting_review_does_not_hide_new_byte_caps():
    policy = MODULE.load_policy()
    path = "api/request_limits.py"
    reviewed = "additional = max(0, new_received - reserved)"
    assert MODULE.classify(path, reviewed, policy)[0] == "format_structure"
    assert MODULE.classify(path, reviewed + "; FIXED_LIMIT = 17", policy)[0] == "unclassified"
    assert MODULE.classify(path, "if new_received > 17:", policy)[0] == "unclassified"


def test_public_auth_abuse_guards_are_narrow_security_boundaries():
    policy = MODULE.load_policy()
    path = "api/public_auth_limits.py"
    reviewed = "if queue is None and len(self._hits) >= self.max_buckets:"
    assert MODULE.classify(path, reviewed, policy)[0] == "hard_boundary"
    assert MODULE.classify(path, reviewed + "  # FIXED_LIMIT = 17", policy)[0] == "unclassified"
    assert MODULE.classify(path, "self.max_buckets = 17", policy)[0] == "unclassified"


def test_api_identity_fields_do_not_hide_content_and_pagination_caps():
    policy = MODULE.load_policy()
    path = "api/server.py"
    assert MODULE.classify(path, "password: str = Field(min_length=10, max_length=1024)", policy)[0] == "hard_boundary"
    assert MODULE.classify(path, "conversation_id: str | None = Field(default=None, max_length=256)", policy)[0] == "format_structure"
    assert MODULE.classify(path, "items: list[dict[str, Any]] = Field(default_factory=list, max_length=200)", policy)[0] == "unclassified"
    assert MODULE.classify(path, "password: str = Field(min_length=10, max_length=17)", policy)[0] == "unclassified"


def test_voice_and_knowledge_review_keeps_new_caps_and_trailing_code_unknown():
    policy = MODULE.load_policy()
    for path, statement in [
        ('voice/python/aurora_voice_server.py', 'text: str = Field(min_length=1, max_length=VOICE_LIMITS.tts_input_chars or None)'),
        ('voice/python/aurora_voice_server.py', 'self.q: queue.Queue[np.ndarray] = queue.Queue(maxsize=VOICE_LIMITS.mic_queue_chunks)'),
        ('scripts/knowledge_store.gd', 'if limit > 0 and scored.size() >= SEARCH_BUFFER_LIMIT:'),
    ]:
        assert MODULE.classify(path, statement, policy)[0] == 'owner_adjustable'
        assert MODULE.classify(path, statement + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
    assert MODULE.classify('voice/python/aurora_voice_server.py', 'MAX_VOICE_BYTES = 17', policy)[0] == 'unclassified'
    assert MODULE.classify('voice/python/processor.py', 'n_fft = max(256, min(2048, requested))', policy)[0] == 'unclassified'
