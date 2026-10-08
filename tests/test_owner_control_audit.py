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


def test_project_index_client_deadline_review_keeps_diagnostic_cap_visible():
    policy = MODULE.load_policy()
    path = 'scripts/project_index_client.gd'
    for statement, category in [
        ('req.timeout = timeout', 'owner_adjustable'),
        ('var req := _new_http_request(timeout)', 'format_structure'),
        ('await get_tree().create_timer(0.8).timeout', 'format_structure'),
    ]:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
    assert MODULE.classify(path, 'req.timeout = 60.0', policy)[0] == 'unclassified'
    assert MODULE.classify(path, 'return {"ok": false, "error": raw.substr(0, 4000)}', policy)[0] == 'unclassified'


def test_computer_service_exact_review_preserves_actual_fixed_caps():
    policy = MODULE.load_policy()
    path = 'computer/computer_service.py'
    reviewed = [
        ('action_text_chars: int = Field(default=MAX_TEXT_CHARS, ge=0)', 'owner_adjustable'),
        ('def _run_worker(kind: str, payload: dict[str, Any] | None = None, timeout: float = GUI_TIMEOUT_SECONDS) -> dict[str, Any]:', 'owner_adjustable'),
        ('type: str = Field(min_length=1, max_length=32)', 'format_structure'),
        ('if not math.isfinite(timeout) or timeout < 0:', 'format_structure'),
        ('if any(reader.is_alive() for reader in record.get("capture_threads", [])): terminated = False', 'hard_boundary'),
    ]
    for statement, category in reviewed:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
        assert MODULE.classify('other/' + path, statement, policy)[0] == 'unclassified'
    for statement in [
        'MAX_OUTPUT = 120_000',
        'goal: str = Field(min_length=1, max_length=8000)',
        'max_steps: int = Field(default=20, ge=1, le=100)',
        'result = subprocess.run(["tasklist", "/FI", f"PID eq {PARENT_PID}", "/NH"], capture_output=True, text=True, timeout=2)',
    ]:
        assert MODULE.classify(path, statement, policy)[0] == 'unclassified'


def test_api_persistence_review_keeps_real_scheduling_floor_visible():
    policy = MODULE.load_policy()
    path = 'api/persistence_maintenance.py'
    reviewed = [
        ('self.backup_max_bytes = max(1, int(backup_max_bytes))', 'owner_adjustable'),
        ('self.warn_database_bytes = min(configured_database_warning, backup_guard_warning)', 'owner_adjustable'),
        ('hard_pressure = disk_free_bytes < self.min_free_bytes', 'owner_adjustable'),
        ('retention = max(0, int(retention_seconds))', 'owner_adjustable'),
        ('"next_in_seconds": max(1, self.maintenance_interval_seconds - max(0, elapsed)),', 'format_structure'),
        ('parser = argparse.ArgumentParser(description="Inspect AuroraFox API persistence capacity")', 'format_structure'),
        ('"""Capacity visibility plus conservative ephemeral-row cleanup.', 'documentation'),
    ]
    for statement, category in reviewed:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
        assert MODULE.classify('other/' + path, statement, policy)[0] == 'unclassified'
    for statement in [
        'def _env_int(name: str, default: int, *, minimum: int = 1) -> int:',
        'return max(minimum, value)',
        'minimum=60,',
        'return max(60, value)',
    ]:
        assert MODULE.classify(path, statement, policy)[0] == 'unclassified'


def test_project_index_backend_review_keeps_path_and_sqlite_caps_visible():
    policy = MODULE.load_policy()
    path = 'file_intelligence/project_index_service.py'
    for statement, category in [
        ('start = max(0, pos - size // 3)', 'owner_adjustable'),
        ('end = min(len(content), start + size)', 'owner_adjustable'),
        ('available = max(0, size - len(prefix) - len(suffix))', 'owner_adjustable'),
        ('limit: int = Field(default=20, ge=0, le=9223372036854775806)', 'format_structure'),
        ('db.execute("SELECT rowid FROM files_fts LIMIT 1").fetchall()', 'format_structure'),
        ('limit_reached = True', 'format_structure'),
    ]:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
        assert MODULE.classify('other/' + path, statement, policy)[0] == 'unclassified'
    for statement in [
        'root: str = Field(min_length=1, max_length=8192)',
        'root: str = Field(default="", max_length=8192)',
        'db = sqlite3.connect(DB_PATH, timeout=30)',
    ]:
        assert MODULE.classify(path, statement, policy)[0] == 'unclassified'


def test_bulk_work_code_memory_review_keeps_fixed_caps_visible():
    policy = MODULE.load_policy()
    reviewed = [
        ('scripts/windows_trusted_project_bridge.gd', 'const MAX_COPY_FILES := 30000', 'owner_adjustable'),
        ('scripts/windows_trusted_project_bridge.gd', 'out.store_buffer(file.get_buffer(mini(1024 * 1024, size - file.get_position())))', 'format_structure'),
        ('scripts/trusted_project_sandbox_bridge.gd', '_copy_directory_limited(source, target, state, max_files, max_bytes)', 'owner_adjustable'),
        ('scripts/trusted_project_sandbox_bridge.gd', 'ctx.update(file.get_buffer(mini(1024 * 1024, file.get_length() - file.get_position())))', 'format_structure'),
        ('scripts/memory_store.gd', 'if limit == -1:', 'owner_adjustable'),
        ('scripts/memory_store.gd', 'if out.size() >= limit:', 'owner_adjustable'),
        ('scripts/memory_store.gd', 'if str(parsed.get("resource_policy", "legacy-unversioned-budget")) != _vector_policy_signature: return', 'format_structure'),
        ('scripts/tool_registry.gd', 'if not ComputerRequestGuard.configure_request(req, timeout, "tool_computer_default_http_seconds"):', 'owner_adjustable'),
        ('scripts/tool_registry.gd', 'await get_tree().create_timer(0.10).timeout', 'format_structure'),
        ('scripts/self_improver.gd', 'const MIN_MUTATIONS := 3', 'format_structure'),
        ('scripts/self_improver.gd', 'return arr.slice(0, OwnerResourcePolicy.count(arr.size(), "hot_evidence_items"))', 'owner_adjustable'),
        ('scripts/core_improvement_pipeline.gd', 'var desired_count := clampi(tournament_candidate_count, MIN_TOURNAMENT_CANDIDATES, MAX_TOURNAMENT_CANDIDATES)', 'format_structure'),
        ('scripts/core_improvement_pipeline.gd', 'var max_attempts := desired_count * OwnerResourcePolicy.value("candidate_proposal_attempt_multiplier")', 'owner_adjustable'),
    ]
    for path, statement, category in reviewed:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
        assert MODULE.classify('other/' + path, statement, policy)[0] == 'unclassified'
    hard_line = next(line.strip() for line in (ROOT / 'scripts/tool_registry.gd').read_text(encoding='utf-8').splitlines()
                     if 'guarded.termination_confirmed' in line and 'uncertain_external_state' in line)
    assert MODULE.classify('scripts/tool_registry.gd', hard_line, policy)[0] == 'hard_boundary'
    assert MODULE.classify('scripts/tool_registry.gd', hard_line + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
    for path, statement in [
        ('scripts/windows_trusted_project_bridge.gd', 'var max_chars := clampi(int(args.get("max_chars", 300000)), 1000, 1000000)'),
        ('scripts/windows_trusted_project_bridge.gd', 'req.timeout = 5.0'),
        ('scripts/trusted_project_sandbox_bridge.gd', 'var max_chars := clampi(int(args.get("max_chars", 300000)), 1000, 1000000)'),
        ('scripts/memory_store.gd', 'const MAX_MEMORY := 5000'),
        ('scripts/tool_registry.gd', 'return {"ok": code == 0, "code": code, "output": "\\n".join(output).substr(0, 100000)}'),
        ('scripts/self_improver.gd', 'const MAX_GENERATION_ATTEMPTS := 24'),
    ]:
        assert MODULE.classify(path, statement, policy)[0] == 'unclassified'


def test_learning_evolution_bulk_review_preserves_real_caps():
    policy = MODULE.load_policy()
    reviewed = [
        ('agent/learning_collector.py', 'def collect_local(limit: int = 80) -> list[dict]:', 'owner_adjustable'),
        ('agent/learning_collector.py', 'for entry in root.findall("atom:entry", ns)[:limit]:', 'owner_adjustable'),
        ('agent/learning_collector.py', 'parser.add_argument("--source-limit", type=int, default=8)', 'owner_adjustable'),
        ('api/community_learning.py', 'changed = max(0, int(cursor.rowcount))', 'format_structure'),
        ('api/community_learning.py', 'overflow = max(0, terminal - self.max_terminal_events)', 'format_structure'),
        ('evolution_engine/core/experiment_registry.gd', 'func recent(limit := 10) -> Array:', 'owner_adjustable'),
        ('evolution_engine/core/experiment_registry.gd', 'while cap > 0 and _recent.size() > cap:', 'owner_adjustable'),
    ]
    for path, statement, category in reviewed:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
        assert MODULE.classify('other/' + path, statement, policy)[0] == 'unclassified'
    unresolved = [
        ('agent/learning_collector.py', 'MAX_HTTP_BYTES = 2 * 1024 * 1024'),
        ('agent/learning_collector.py', 'items.extend(collect_internet(args.query, max(1, min(args.source_limit, 20))))'),
        ('agent/learning_curator.gd', 'const MIN_PROMOTION_SCORE := 0.48'),
        ('api/community_learning.py', 'bounded_limit = max(1, min(int(limit), 200))'),
        ('api/community_learning.py', 'self.max_terminal_events = max(1000, int(max_terminal_events))'),
        ('evolution_engine/core/experiment_registry.gd', '"goal": goal.substr(0, 2000),'),
        ('evolution_engine/learning/experience_bridge.gd', '"goal": goal.substr(0, 2000),'),
    ]
    for path, statement in unresolved:
        assert MODULE.classify(path, statement, policy)[0] == 'unclassified'


def test_api_personal_data_bulk_review_keeps_operational_caps_visible():
    policy = MODULE.load_policy()
    reviewed = [
        ('api/account_store.py', 'self.account_token_cooldown = max(0, int(account_token_cooldown))', 'owner_adjustable'),
        ('api/account_store.py', '"WHERE s.access_hash=? LIMIT 1",', 'format_structure'),
        ('api/agent_bridge.gd', 'clampf(float(payload.get("confidence", 0.80)), 0.0, 1.0),', 'format_structure'),
        ('api/backup_service.py', 'backup_max_bytes=self.max_source_bytes,', 'owner_adjustable'),
        ('api/backup_service.py', '"hard_pressure": bool(capacity.get("hard_pressure", False)),', 'format_structure'),
        ('api/learning_store.py', 'overflow = max(0, total - self.max_events)', 'format_structure'),
        ('api/sync_store.py', 'safe_cursor = max(0, int(cursor))', 'format_structure'),
        ('api/server.py', 'content_base64: str = Field(min_length=1)', 'format_structure'),
        ('api/settings_overlay.gd', 'port_box.max_value = 65535', 'format_structure'),
    ]
    for path, statement, category in reviewed:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
        assert MODULE.classify('other/' + path, statement, policy)[0] == 'unclassified'
    unresolved = [
        ('api/account_store.py', 'self.access_ttl = max(60, int(access_ttl))'),
        ('api/agent_bridge.gd', '@export_range(1, 128, 1) var max_clients := 32'),
        ('api/backup_service.py', 'source_db = sqlite3.connect(source_uri, uri=True, timeout=30)'),
        ('api/learning_store.py', 'self.max_events = max(1000, max_events)'),
        ('api/local_core_client.py', 'self.timeout = max(5.0, timeout)'),
        ('api/server.py', 'limit: int = Query(default=200, ge=1, le=500),'),
        ('api/settings_overlay.gd', 'const MAX_VISIBLE_MEMORY_ROWS := 30'),
        ('api/sync_store.py', 'safe_limit = min(500, max(1, int(limit)))'),
    ]
    for path, statement in unresolved:
        assert MODULE.classify(path, statement, policy)[0] == 'unclassified'


def test_candidate_source_budget_audit_is_exact_and_other_candidate_caps_stay_visible():
    policy = MODULE.load_policy()
    reviewed = [
        ('scripts/core_candidate_submitter.gd', 'var max_source_bytes := OwnerResourcePolicy.value("candidate_source_bytes")'),
        ('scripts/core_candidate_submitter.gd', 'if max_source_bytes > 0 and source_size > max_source_bytes:'),
        ('api/core_candidate_queue.py', 'self.max_source_bytes = _nonnegative_budget(configured_source_bytes, SOURCE_BYTES_ENV)'),
        ('api/core_candidate_queue.py', 'if not raw or (max_source_bytes and len(raw) > max_source_bytes):'),
    ]
    for path, statement in reviewed:
        assert MODULE.classify(path, statement, policy)[0] == 'owner_adjustable'
        assert MODULE.classify(path, statement + ' FIXED_LIMIT = 17', policy)[0] == 'unclassified'
        assert MODULE.classify('other/' + path, statement, policy)[0] == 'unclassified'
    assert MODULE.classify('api/core_candidate_queue.py', 'MAX_QUEUE_ITEMS = 200', policy)[0] == 'unclassified'


def test_api_bulk_review_classifies_exact_forwarding_without_hiding_real_caps():
    policy = MODULE.load_policy()
    reviewed = [
        ('api/account_mailer.py', 'timeout = float(os.getenv("AURORAFOX_SMTP_TIMEOUT_SECONDS", "10"))', 'owner_adjustable'),
        ('api/account_store.py', '"ORDER BY created_at DESC LIMIT 1",', 'format_structure'),
        ('api/community_learning.py', '"ORDER BY created_at, id LIMIT ?",', 'format_structure'),
        ('api/conversation_store.py', 'self.max_messages = _nonnegative_budget(', 'owner_adjustable'),
        ('api/core_candidate_queue.py', 'rows = self.list(self.max_items)', 'owner_adjustable'),
        ('api/file_client.py', 'configured_max = max_file_bytes', 'owner_adjustable'),
        ('api/learning_store.py', '``max_events`` is a history cap, never a durability cap. If the server is', 'documentation'),
        ('api/runtime_bridge.py', 'raise RuntimeError("AuroraFox bridge response exceeds owner byte budget")', 'format_structure'),
        ('api/server.py', 'return sync.pull(_personal(record), cursor=cursor, limit=limit)', 'format_structure'),
        ('api/sync_store.py', '"ORDER BY seq LIMIT ?",', 'format_structure'),
    ]
    for path, statement, category in reviewed:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + ' FIXED_LIMIT = 17', policy)[0] == 'unclassified'
        assert MODULE.classify('other/' + path, statement, policy)[0] == 'unclassified'
    unresolved = [
        ('api/account_mailer.py', 'timeout=max(1.0, min(60.0, timeout)),'),
        ('api/community_learning.py', 'bounded_limit = max(1, min(int(limit), 200))'),
        ('api/core_candidate_queue.py', 'rows = self.list(self.max_items + 50)'),
        ('api/gateway_manager.gd', 'request.timeout = 2.5'),
        ('api/knowledge_bundle.py', 'MAX_SERVER_TARGET_BYTES = 240 * 1024 * 1024'),
        ('api/local_core_client.py', 'backoff = min(900.0, 5.0 * (2 ** min(7, failures - 1)))'),
        ('api/server.py', 'limit: int = Query(default=50, ge=1, le=200),'),
        ('api/sync_store.py', 'safe_limit = min(500, max(1, int(limit)))'),
    ]
    for path, statement in unresolved:
        assert MODULE.classify(path, statement, policy)[0] == 'unclassified'


def test_local_input_bulk_review_preserves_real_agent_file_voice_limits():
    policy = MODULE.load_policy()
    reviewed = [
        ('agent/autonomous_coordinator.gd', 'report["events"] = _events.slice(maxi(0, _events.size() - OwnerResourcePolicy.count(_events.size(), "coordinator_report_items")), _events.size())', 'owner_adjustable'),
        ('agent/autonomous_coordinator.gd', 'return clampi(size, SelfImprover.MIN_MUTATIONS, SelfImprover.MAX_MUTATIONS)', 'format_structure'),
        ('agent/goals.gd', 'var accuracy := clampf(float(metrics.get("accuracy", 0.0)), 0.0, 1.0)', 'format_structure'),
        ('agent/learning_collector.py', 'with urllib.request.urlopen(request, timeout=timeout) as response:', 'owner_adjustable'),
        ('file_intelligence/extended_formats.py', 'remaining = max(0, max_chars)', 'owner_adjustable'),
        ('file_intelligence/extended_formats.py', 'expanded += max(0, int(info.file_size))', 'format_structure'),
        ('file_intelligence/local_ocr.py', '"max_input_pixels": OCR_MAX_INPUT_PIXELS,', 'owner_adjustable'),
        ('file_intelligence/setup_wizard.gd', 'progress.max_value = 100', 'format_structure'),
        ('voice/voice_bridge.gd', 'req.timeout = timeout', 'owner_adjustable'),
        ('voice/voice_logger.gd', 'var cap := OwnerResourcePolicy.value("voice_log_bytes")', 'owner_adjustable'),
        ('voice/voice_manager.gd', 'var sample := int(clampf(tone * env * gain, -1.0, 1.0) * 32767.0)', 'format_structure'),
    ]
    for path, statement, category in reviewed:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + ' FIXED_LIMIT = 17', policy)[0] == 'unclassified'
        assert MODULE.classify('other/' + path, statement, policy)[0] == 'unclassified'
    unresolved = [
        ('agent/learning_collector.py', 'MAX_HTTP_BYTES = 2 * 1024 * 1024'),
        ('agent/learning_curator.gd', 'const MIN_PROMOTION_SCORE := 0.48'),
        ('agent/research_collector.gd', 'const MAX_ITEMS_PER_SOURCE := 5'),
        ('file_intelligence/extended_formats.py', 'def analyze_epub(path: Path, max_chars: int = 160000) -> tuple[str, dict[str, Any], list[str]]:'),
        ('file_intelligence/project_index_service.py', 'root: str = Field(min_length=1, max_length=8192)'),
        ('voice/android_mic_monitor.gd', 'const MIN_SPEECH_SEC := 0.24'),
        ('voice/voice_bridge.gd', 'func _json_request(path: String, method: HTTPClient.Method, payload: Dictionary, timeout := 30.0) -> Dictionary:'),
        ('voice/voice_logger.gd', 'const MAX_BYTES := 5 * 1024 * 1024'),
        ('voice/voice_manager.gd', '"speed": clampf(speech_speed, 0.82, 1.20),'),
    ]
    for path, statement in unresolved:
        assert MODULE.classify(path, statement, policy)[0] == 'unclassified'


def test_scripts_bulk_review_preserves_runtime_and_security_caps():
    policy = MODULE.load_policy()
    reviewed = [
        ('scripts/android_file_tool_bridge.gd', '{"path":"string","max_items":"int"},', 'format_structure'),
        ('scripts/android_file_tool_bridge.gd', 'return await client.analyze_file(path, str(args.get("question", "")), bool(args.get("visual", true)), int(client.owner_limits().max_text_chars))', 'owner_adjustable'),
        ('scripts/code_specialist.gd', 'if cap > 0 and used >= cap: break', 'owner_adjustable'),
        ('scripts/core_candidate_submitter.gd', '_timer.timeout.connect(_scan_once)', 'format_structure'),
        ('scripts/dream_cycle.gd', 'ideas = ideas.slice(ideas.size() - cap)', 'owner_adjustable'),
        ('scripts/main.gd', 'rename_input.max_length = OwnerResourcePolicy.value("chat_title_chars")', 'owner_adjustable'),
        ('scripts/owner_resource_policy.gd', 'return is_finite(number) and number >= minimum(key) and number < 9223372036854775807.0 and number == floor(number)', 'format_structure'),
        ('scripts/project_index_tool_bridge.gd', '{"path":"string","query":"string","limit":"int"},', 'format_structure'),
        ('scripts/tool_registry.gd', 'req.timeout = timeout', 'owner_adjustable'),
    ]
    for path, statement, category in reviewed:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + ' FIXED_LIMIT = 17', policy)[0] == 'unclassified'
        assert MODULE.classify('other/' + path, statement, policy)[0] == 'unclassified'
    unresolved = [
        ('scripts/android_local_runtime.gd', '"timeout": clampi(timeout, 1, 600),'),
        ('scripts/bundled_core_model.gd', 'var block := source.get_buffer(mini(4 * 1024 * 1024, remaining))'),
        ('scripts/computer_overlay.gd', 'var bounded_steps := clampi(max_steps, 1, 100)'),
        ('scripts/core_candidate_submitter.gd', 'const MAX_SCAN_CANDIDATES := 50'),
        ('scripts/knowledge_pack_installer.gd', 'const MIN_PRODUCTION_CONTENT_BYTES := 1024 * 1024 * 1024'),
        ('scripts/local_semantic_vectorizer.gd', 'const MAX_TOKENS := 768'),
        ('scripts/public_web_manager.gd', 'var sample := raw.to_lower().substr(0, 120000)'),
        ('scripts/self_improver.gd', 'const MAX_GENERATION_ATTEMPTS := 24'),
        ('scripts/tool_registry.gd', 'return {"ok": code == 0, "code": code, "output": "\n".join(output).substr(0, 100000)}'),
    ]
    for path, statement in unresolved:
        assert MODULE.classify(path, statement, policy)[0] == 'unclassified'


def test_evolution_learning_bulk_review_keeps_real_evidence_caps_visible():
    policy = MODULE.load_policy()
    reviewed = [
        ('evolution_engine/evaluation/core_tournament_adapter.gd', 'held_seconds = maxi(0, int(Time.get_unix_time_from_system()) - _pipeline_lock_acquired_at)', 'format_structure'),
        ('evolution_engine/evaluation/core_tournament_adapter.gd', 'while cap > 0 and _pending_winners.size() > cap:', 'owner_adjustable'),
        ('evolution_engine/integration/community_learning_bridge.gd', '_timer.timeout.connect(_on_timer)', 'format_structure'),
        ('agent/learning_curator.gd', '"minimum_promotion_score": MIN_PROMOTION_SCORE,', 'format_structure'),
    ]
    for path, statement, category in reviewed:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
        assert MODULE.classify('other/' + path, statement, policy)[0] == 'unclassified'
    unresolved = [
        ('agent/learning_curator.gd', 'const MIN_PROMOTION_SCORE := 0.48'),
        ('evolution_engine/core/experiment_registry.gd', '"goal": goal.substr(0, 2000),'),
        ('evolution_engine/evaluation/core_tournament_adapter.gd', '"generation_errors": generation_errors.slice(0, mini(generation_errors.size(), 20)),'),
        ('evolution_engine/integration/community_learning_bridge.gd', '_timer.wait_time = clampf(interval_seconds, 30.0, 3600.0)'),
        ('evolution_engine/learning/candidate_ledger.gd', 'failure_error = str(failure.get("error", "")).substr(0, 800)'),
        ('evolution_engine/learning/community_language_curator.gd', '"features": _compact_strings(event.get("features", []), 16, 80),'),
        ('evolution_engine/learning/context_bridge.gd', 'var safe_memory_limit := clampi(memory_limit, 1, MAX_CONTEXT_ITEMS)'),
        ('evolution_engine/learning/experience_bridge.gd', '"goal": goal.substr(0, 2000),'),
        ('evolution_engine/learning/learning_signal.gd', 'const MAX_MEMORY_ROWS := 12'),
    ]
    for path, statement in unresolved:
        assert MODULE.classify(path, statement, policy)[0] == 'unclassified'


def test_desktop_runtime_bulk_review_keeps_fixed_operational_caps_visible():
    policy = MODULE.load_policy()
    reviewed = [
        ('scripts/agent_core.gd', '"confidence": clampf(float(parsed.get("confidence", 0.0)), 0.0, 1.0),', 'format_structure'),
        ('scripts/ai_client.gd', 'func search_knowledge(query: String, limit: int = -1) -> Array:', 'owner_adjustable'),
        ('scripts/aurora_core_runtime.gd', '"retry_after_unix": _ollama_retry_after_unix', 'format_structure'),
        ('scripts/computer_client.gd', 'var bounded_timeout := ComputerRequestGuard.execution_timeout(timeout)', 'owner_adjustable'),
        ('scripts/desktop_local_runtime.gd', '"max_tokens": max_tokens,', 'owner_adjustable'),
        ('scripts/knowledge_base_overlay.gd', 'if limit > 0 and out.size() >= limit:', 'owner_adjustable'),
        ('scripts/runtime_extension_manager.gd', 'return clean.substr(0, 32) + "_" + sha.substr(0, 12)', 'format_structure'),
        ('scripts/sandbox_manager.gd', 'var bounded_timeout := ComputerRequestGuard.execution_timeout(timeout)', 'owner_adjustable'),
        ('scripts/self_improvement_overlay.gd', 'history.resize(cap)', 'owner_adjustable'),
        ('scripts/settings_overlay.gd', 'archive_listing_percent.max_value = 100.0', 'format_structure'),
    ]
    for path, statement, category in reviewed:
        assert MODULE.classify(path, statement, policy)[0] == category
        assert MODULE.classify(path, statement + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
        assert MODULE.classify('other/' + path, statement, policy)[0] == 'unclassified'
    hard_line = next(line.strip() for line in (ROOT / 'scripts/agent_core.gd').read_text(encoding='utf-8').splitlines()
                     if 'Не удаляй данные, не обходи аутентификацию/CAPTCHA' in line)
    assert MODULE.classify('scripts/agent_core.gd', hard_line, policy)[0] == 'hard_boundary'
    assert MODULE.classify('scripts/agent_core.gd', hard_line + '; FIXED_LIMIT = 17', policy)[0] == 'unclassified'
    unresolved = [
        ('scripts/agent_core.gd', 'var max_steps := 18'),
        ('scripts/ai_client.gd', 'request_node.timeout = 3.0'),
        ('scripts/aurora_core_runtime.gd', 'request_node.timeout = OLLAMA_TIMEOUT_SECONDS'),
        ('scripts/computer_client.gd', 'const MAX_SANDBOX_TIMEOUT := 300'),
        ('scripts/desktop_local_runtime.gd', 'req.timeout = timeout'),
        ('scripts/knowledge_base_overlay.gd', 'const MAX_FOLDER_FILES := 750'),
        ('scripts/runtime_extension_manager.gd', 'const MAX_SOURCE_BYTES := 512 * 1024'),
        ('scripts/sandbox_manager.gd', 'const MAX_WINDOWS_EXEC_TIMEOUT := 300'),
        ('scripts/self_improvement_overlay.gd', 'str(candidate.get("reason", "")).substr(0, 700)'),
        ('scripts/settings_overlay.gd', 'timeout.value = 20'),
        ('scripts/settings_overlay.gd', 'slider.max_value = maximum'),
    ]
    for path, statement in unresolved:
        assert MODULE.classify(path, statement, policy)[0] == 'unclassified'


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
