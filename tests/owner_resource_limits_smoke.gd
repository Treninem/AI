extends SceneTree

# Keep genuine production memory algorithms; isolate filesystem/deferred IO only.
class IsolatedMemory extends MemoryStore:
	func _schedule_persistence(_memory_changed: bool, _knowledge_changed: bool) -> void:
		pass
	func _queue_item_vector(item: Dictionary, collection: String) -> void:
		_index_queue.append({"id": item.id, "collection": collection, "content": OwnerResourcePolicy.clip(str(item.content), "index_text_chars")})
	func _save_vector_index() -> void:
		pass

class IsolatedExperience extends ExperienceStore:
	func _save_array(_path: String, _data: Array) -> void:
		pass

class LoopFixtureAI extends AIClient:
	var calls := 0
	var response: Dictionary = {"ok": true, "content": '{"tool":"fixture","args":{}}'}
	func chat(_messages: Array, _temperature: float = 0.2) -> Dictionary:
		calls += 1
		return response

class TextOnlyCore extends AgentCore:
	func run_task(_task: String, _context: Array = [], _guard: Callable = Callable()) -> String:
		return "Готово: действие выполнено."

class UnobservedComputerUI extends "res://scripts/computer_overlay.gd":
	var fixture_core: AgentCore
	func _ready() -> void:
		pass
	func _agent_core() -> AgentCore:
		return fixture_core
	func _computer_primitives_ready() -> bool:
		return true
	func _sync_computer_permission() -> void:
		pass

class RoutingFileClient extends FileIntelligenceClient:
	var captured_chars := 0
	var captured_items := 0
	func owner_limits() -> Dictionary:
		return {"max_text_chars": 300000, "tree_max_items": 9000}
	func analyze_file(_path: String, _question := "", _visual := true, max_chars := 160000) -> Dictionary:
		captured_chars = max_chars
		return {"ok": true}
	func tree(_path: String, max_items := 2000) -> Dictionary:
		captured_items = max_items
		return {"ok": true}

class IsolatedKnowledgeUI extends KnowledgeBaseOverlay:
	func _ready() -> void:
		pass
	func _is_supported(path: String) -> bool:
		return path.get_extension() == "txt"

class IsolatedImprovementUI extends SelfImprovementOverlay:
	func _save_history() -> void:
		pass

class IsolatedCoordinator extends AuroraAutonomousCoordinator:
	func _save_state() -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := "user://owner_resource_fixture.cfg"
	var original := OwnerResourcePolicy._cached.duplicate()
	OwnerResourcePolicy._cached = OwnerResourcePolicy.DEFAULTS.duplicate()
	assert(OwnerResourcePolicy.save({"task_trace_chars": 50000, "index_batch": 129}, path) == OK)
	assert(OwnerResourcePolicy.limits(path).task_trace_chars == 50000)
	assert(OwnerResourcePolicy.save({"memory_max_items": 0}, path) == OK)
	assert(OwnerResourcePolicy.limits(path).task_trace_chars == 50000) # Partial save preserves fields.
	assert(OwnerResourcePolicy.save({"index_batch": 0}, path) == ERR_INVALID_PARAMETER)
	assert(OwnerResourcePolicy.save({"task_trace_chars": -1}, path) == ERR_INVALID_PARAMETER)
	assert(OwnerResourcePolicy.save({"task_trace_chars": 1.5}, path) == ERR_INVALID_PARAMETER)
	assert(OwnerResourcePolicy.save({"task_trace_chars": NAN}, path) == ERR_INVALID_PARAMETER)
	assert(OwnerResourcePolicy.save({"unknown": 1}, path) == ERR_INVALID_PARAMETER)
	assert(OwnerResourcePolicy.save({"chat_max_tokens": 2147483648}, path) == ERR_INVALID_PARAMETER)
	assert(OwnerResourcePolicy.save({"task_trace_chars": 10}, "user://missing_resource_fixture_dir/value.cfg") != OK)
	var coordinator := IsolatedCoordinator.new()
	OwnerResourcePolicy._cached.coordinator_detail_chars = 2
	OwnerResourcePolicy._cached.coordinator_detail_items = 1
	var compact: Dictionary = coordinator._compact({"ok": false, "score": 0.75, "items": ["long", "other"]})
	assert(compact.ok == false and compact.score == 0.75 and compact.items == ["lo"])
	OwnerResourcePolicy._cached.coordinator_event_items = 2
	for i in range(3): coordinator._record_event("fixture", {"id": i})
	assert(coordinator._events.size() == 2 and coordinator._events[0].details.id == 1)
	OwnerResourcePolicy._cached.coordinator_event_items = 0
	OwnerResourcePolicy._cached.coordinator_detail_chars = 0
	OwnerResourcePolicy._cached.coordinator_detail_items = 0
	coordinator._record_event("fixture", {"text": "complete", "items": [1, 2]})
	assert(coordinator._events.size() == 3 and coordinator._events[-1].details.text == "complete")
	assert(coordinator._events[-1].details.items == [1, 2])
	coordinator.research.free()
	coordinator.free()
	var source_dir := "user://owner_copy_fixture_source"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source_dir))
	for filename in ["a.txt", "b.txt"]:
		var fixture_file := FileAccess.open(source_dir.path_join(filename), FileAccess.WRITE)
		fixture_file.store_string("abc")
		fixture_file.close()
	for bridge in [TrustedProjectSandboxBridge.new(), WindowsTrustedProjectBridge.new()]:
		var target_dir := "user://owner_copy_fixture_" + str(bridge.get_instance_id())
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_dir))
		var copy_state := {"files": 0, "bytes": 0, "skipped": 0, "errors": [], "stopped": false}
		bridge._copy_directory_limited(source_dir, target_dir, copy_state, 0, 0)
		assert(copy_state.files == 2 and copy_state.bytes == 6 and not copy_state.stopped)
		copy_state = {"files": 0, "bytes": 0, "skipped": 0, "errors": [], "stopped": false}
		bridge._copy_directory_limited(source_dir, target_dir, copy_state, 1, 0)
		assert(copy_state.files == 1 and copy_state.stopped)
		copy_state = {"files": 0, "bytes": 0, "skipped": 0, "errors": [], "stopped": false}
		bridge._copy_directory_limited(source_dir, target_dir, copy_state, 0, 2)
		assert(copy_state.files == 0 and copy_state.stopped)
		for filename in ["a.txt", "b.txt"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(target_dir.path_join(filename)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(target_dir))
		bridge.free()
	var knowledge_ui := IsolatedKnowledgeUI.new()
	root.add_child(knowledge_ui)
	var selected_files: Array = []
	var coverage := await knowledge_ui._collect_supported(source_dir, selected_files, 0)
	assert(selected_files.size() == 2 and not coverage.limit_reached and coverage.errors.is_empty())
	selected_files.clear()
	coverage = await knowledge_ui._collect_supported(source_dir, selected_files, 1)
	assert(selected_files.size() == 1 and coverage.limit_reached)
	selected_files.clear()
	coverage = await knowledge_ui._collect_supported(source_dir, selected_files, 2)
	assert(selected_files.size() == 2 and not coverage.limit_reached)
	selected_files.clear()
	knowledge_ui.import_cancel_requested = true
	coverage = await knowledge_ui._collect_supported(source_dir, selected_files, 0)
	assert(selected_files.is_empty() and coverage.cancelled)
	knowledge_ui.import_cancel_requested = false
	for i in range(130):
		var scan_file := FileAccess.open(source_dir.path_join("scan_%d.txt" % i), FileAccess.WRITE)
		scan_file.store_string("fixture")
		scan_file.close()
	selected_files.clear()
	knowledge_ui.call_deferred("set", "import_cancel_requested", true)
	coverage = await knowledge_ui._collect_supported(source_dir, selected_files, 0)
	assert(coverage.cancelled and selected_files.size() < 132)
	for i in range(130): DirAccess.remove_absolute(ProjectSettings.globalize_path(source_dir.path_join("scan_%d.txt" % i)))
	knowledge_ui.free()
	var improvement_ui := IsolatedImprovementUI.new()
	OwnerResourcePolicy._cached.improvement_ui_detail_chars = 2
	OwnerResourcePolicy._cached.improvement_ui_detail_items = 1
	OwnerResourcePolicy._cached.improvement_ui_history_items = 2
	assert(improvement_ui._compact({"content": "complete", "ok": false}).content == "co")
	assert(improvement_ui._compact([1, 2]) == [1])
	for i in range(3): improvement_ui._add_history("fixture", false, {"id": i})
	assert(improvement_ui.history.size() == 2 and improvement_ui.history[0].details.id == 2)
	OwnerResourcePolicy._cached.improvement_ui_detail_chars = 0
	OwnerResourcePolicy._cached.improvement_ui_detail_items = 0
	OwnerResourcePolicy._cached.improvement_ui_history_items = 0
	assert(improvement_ui._compact({"content": "complete"}).content == "complete")
	assert(improvement_ui._compact([1, 2]) == [1, 2])
	improvement_ui._add_history("fixture", false, {})
	assert(improvement_ui.history.size() == 3)
	improvement_ui.free()
	for filename in ["a.txt", "b.txt"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(source_dir.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(source_dir))
	var voice_logger = load("res://voice/voice_logger.gd").new()
	voice_logger.log_path = "user://owner_voice_logger_fixture.log"
	OwnerResourcePolicy._cached.voice_log_bytes = 0
	OwnerResourcePolicy._cached.voice_log_chars = 0
	voice_logger.write("fixture", "visible complete message")
	voice_logger.write("fixture", "token=fixture-sensitive-value")
	var diagnostic := FileAccess.get_file_as_string(voice_logger.log_path)
	assert(diagnostic.contains("visible complete message") and not diagnostic.contains("fixture-sensitive-value"))
	OwnerResourcePolicy._cached.voice_log_bytes = 1
	voice_logger._rotate_if_needed()
	assert(FileAccess.file_exists(voice_logger.log_path + ".1"))
	assert(not FileAccess.file_exists(voice_logger.log_path))
	voice_logger.free()
	for suffix in ["", ".1"]: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://owner_voice_logger_fixture.log" + suffix))
	var native_tools := AndroidFileToolBridge.new()
	native_tools.client.free()
	var text_core := TextOnlyCore.new()
	for component in [text_core.experience, text_core.cognition, text_core.dream_cycle, text_core.team]: text_core.add_child(component)
	var unobserved := UnobservedComputerUI.new()
	unobserved.add_child(unobserved.computer)
	unobserved.fixture_core = text_core
	unobserved.enabled = true
	var text_result := await unobserved.execute_goal("fixture action")
	assert(not text_result.ok and not text_result.verified)
	assert(text_result.status == "UNVERIFIED" and text_result.error == "action_outcome_unverified")
	assert(text_result.response == "Готово: действие выполнено.")
	unobserved.free()
	text_core.free()

	var routing_client := RoutingFileClient.new()
	native_tools.client = routing_client
	assert((await native_tools._analyze_file({"path": "user://fixture.txt"})).ok)
	assert(routing_client.captured_chars == 300000)
	assert((await native_tools._file_tree({"path": "user://", "max_items": 8000})).ok)
	assert(routing_client.captured_items == 8000)
	routing_client.free()
	native_tools.free()
	var long_text := "Привет 🌍".repeat(3000)
	assert(OwnerResourcePolicy.clip(long_text, "task_trace_chars").length() == 12000)
	OwnerResourcePolicy._cached.task_trace_chars = 0
	assert(OwnerResourcePolicy.clip(long_text, "task_trace_chars") == long_text)
	OwnerResourcePolicy._cached.task_trace_chars = 2
	assert(OwnerResourcePolicy.clip("АБВ", "task_trace_chars") == "АБ")
	OwnerResourcePolicy._cached.direct_history_items = 0
	assert(OwnerResourcePolicy.count(30, "direct_history_items") == 30)
	var vectorizer := AuroraLocalSemanticVectorizer.new()
	OwnerResourcePolicy._cached.vector_features = 1
	assert(vectorizer.embed("alpha") == vectorizer.embed("alpha beta gamma"))
	OwnerResourcePolicy._cached.vector_features = 0
	OwnerResourcePolicy._cached.vector_tokens = 1
	assert(vectorizer.embed("alpha") == vectorizer.embed("alpha beta gamma"))
	OwnerResourcePolicy._cached.vector_tokens = 0
	assert(vectorizer.embed("alpha") != vectorizer.embed("alpha beta gamma"))
	OwnerResourcePolicy._cached.vector_tokens = 768
	OwnerResourcePolicy._cached.vector_features = 4096
	var agent := AgentCore.new()
	var messages: Array = []
	var history: Array = []
	for i in range(6): history.append({"role": "user", "content": "АБВГД"})
	OwnerResourcePolicy._cached.direct_history_chars = 3
	agent._append_direct_conversation_context(messages, history)
	assert(messages.size() == 6 and messages[0].content == "АБВ")
	OwnerResourcePolicy._cached.agent_history_items = 0
	OwnerResourcePolicy._cached.attachment_items = 0
	OwnerResourcePolicy._cached.attachment_excerpt_chars = 0
	OwnerResourcePolicy._cached.context_message_chars = 0
	messages.clear()
	agent._append_conversation_context(messages, [{"role": "user", "content": "x", "attachments": [{"name": "a", "excerpt": long_text}, {"name": "b", "excerpt": long_text}]}])
	assert(messages[0].content.contains(long_text) and messages[0].content.contains("тип:"))
	OwnerResourcePolicy._cached.tool_result_chars = 0
	OwnerResourcePolicy._cached.tool_result_items = 0
	assert(agent._compact_result({"text": long_text}).text == long_text)
	assert(agent._compact_result(range(40)).size() == 40)
	OwnerResourcePolicy._cached.tool_result_chars = 3
	assert(agent._compact_result({"text": "АБВГД"}).text == "АБВ")
	assert(agent._compact_result({"ok": true, "count": 1234, "nested": {"text": "АБВГД"}}) == {"ok": true, "count": 1234, "nested": {"text": "АБВ"}})
	var desktop := DesktopLocalRuntime.new()
	assert(desktop._generation_budget({}, false) == 768)
	OwnerResourcePolicy._cached.chat_max_tokens = 20000
	assert(desktop._generation_budget({}, false) == 20000)
	assert(desktop._generation_budget({"max_tokens": 16}, false) == 16)
	assert(desktop._generation_budget({"max_tokens": 2147483648}, false) == -2)
	assert(desktop._generation_budget({"max_tokens": 1.5}, false) == -2)
	OwnerResourcePolicy._cached.chat_max_tokens = 0
	assert(desktop._generation_budget({}, false) == -1)
	var store := IsolatedMemory.new()
	OwnerResourcePolicy._cached.memory_max_items = 0
	OwnerResourcePolicy._cached.knowledge_max_items = 0
	OwnerResourcePolicy._cached.dedupe_window = 2
	OwnerResourcePolicy._cached.index_text_chars = 0
	for i in range(5): store.remember("fixture", "record" + str(i), "fixture")
	assert(store.memory.size() == 5)
	OwnerResourcePolicy._cached.dedupe_window = 0
	OwnerResourcePolicy.revision += 1
	store.remember("fixture", "record0", "fixture")
	assert(store.memory.size() == 5) # Rebuild expands dedupe coverage after live policy change.
	store.learn(long_text, "fixture")
	assert(store.knowledge[0].content == long_text)
	assert(store._index_queue[-1].content == long_text)
	OwnerResourcePolicy._cached.index_batch = 2
	store._drain_local_index()
	assert(store.vectors.size() == 2 and store._index_queue.size() == 5)
	var old_signature := store._vector_policy_signature
	OwnerResourcePolicy._cached.vector_tokens = 0
	OwnerResourcePolicy.revision += 1
	store._sync_owner_resources()
	assert(store._vector_policy_signature != old_signature and store.vectors.is_empty())
	assert(store._index_queue.size() == store.memory.size() + store.knowledge.size())
	OwnerResourcePolicy._cached.memory_max_items = 3
	store.remember("fixture", "new-record", "fixture")
	assert(store.memory.size() == 3)
	var operation_path := "user://owner_operation_limits_fixture.cfg"
	var file_policy := FileIntelligenceClient.new()
	file_policy.owner_limits_path = operation_path
	var original_file_limits := file_policy.owner_limits()
	assert(file_policy.apply_owner_limits({"max_file_bytes": 1, "ocr_max_render_pixels": 1, "max_text_chars": 50001}, true, false).ok)
	var reloaded_file_policy := FileIntelligenceClient.new()
	reloaded_file_policy.owner_limits_path = operation_path
	assert(reloaded_file_policy.owner_limits().max_file_bytes == 1 and reloaded_file_policy.owner_limits().max_text_chars == 50001)
	var web_policy := PublicWebManager.new()
	web_policy.owner_limits_path = operation_path
	var original_web_settings: Dictionary = {}
	for key in web_policy.OWNER_LIMIT_DEFAULTS:
		var setting := "aurorafox/web/" + str(key)
		original_web_settings[key] = {"present": ProjectSettings.has_setting(setting), "value": ProjectSettings.get_setting(setting)}
	assert(web_policy.apply_owner_limits({"max_extracted_chars": 1, "max_response_bytes": 1, "max_url_length": 1, "request_timeout_seconds": 0.0}, true).ok)
	var reloaded_web_policy := PublicWebManager.new()
	reloaded_web_policy.owner_limits_path = operation_path
	assert(reloaded_web_policy.owner_limits().max_extracted_chars == 1 and reloaded_web_policy.owner_limits().request_timeout_seconds == 0.0)
	# Saving web does not overwrite the file group in the shared private config.
	assert(OwnerLimitPersistence.load_group("files", operation_path).values.max_text_chars == 50001)
	assert(not file_policy.apply_owner_limits({"max_text_chars": NAN}, true, false).ok)
	assert(not web_policy.apply_owner_limits({"max_urls_per_message": 1.5}, true).ok)
	assert(not file_policy.apply_owner_limits({"unknown": 1}, true, false).ok)
	assert(not web_policy.apply_owner_limits({"unknown": 1}, true).ok)
	assert(OwnerLimitPersistence.load_group("files", operation_path).values.max_text_chars == 50001)
	file_policy.owner_limits_path = "user://missing_owner_policy_fixture_dir/limits.cfg"
	assert(not file_policy.apply_owner_limits({"max_text_chars": 70001}, true, false).ok)
	assert(file_policy.owner_limits().max_text_chars == 50001)
	web_policy.owner_limits_path = file_policy.owner_limits_path
	assert(not web_policy.apply_owner_limits({"max_extracted_chars": 70001}, true).ok)
	assert(web_policy.max_extracted_chars == 1)
	var restored_file_limits := {}
	for key in file_policy.OWNER_LIMIT_DEFAULTS: restored_file_limits[key] = original_file_limits[key]
	file_policy.apply_owner_limits(restored_file_limits, false, false)
	for key in original_web_settings:
		var setting := "aurorafox/web/" + str(key)
		if original_web_settings[key].present: ProjectSettings.set_setting(setting, original_web_settings[key].value)
		else: ProjectSettings.clear(setting)
	file_policy.free()
	reloaded_file_policy.free()
	web_policy.free()
	reloaded_web_policy.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(operation_path))
	var json_path := "user://owner_resource_json_fixture.json"
	var json_file := FileAccess.open(json_path, FileAccess.WRITE)
	json_file.store_string('{"a":[{"b":"Привет"}],"c":3}')
	json_file.close()
	var reader := AuroraJsonStreamReader.new()
	var accept_value := func(_json_path, _value): return {"ok": true}
	OwnerResourcePolicy._cached.json_depth = 1
	assert(not reader.parse_file(json_path, accept_value).ok)
	OwnerResourcePolicy._cached.json_depth = 0
	OwnerResourcePolicy._cached.json_scalar_bytes = 2
	assert(not reader.parse_file(json_path, accept_value).ok)
	OwnerResourcePolicy._cached.json_scalar_bytes = 0
	OwnerResourcePolicy._cached.json_records = 1
	assert(not reader.parse_file(json_path, accept_value).ok)
	OwnerResourcePolicy._cached.json_records = 0
	assert(reader.parse_file(json_path, accept_value).ok)
	# Changing owner settings during a parse applies to the next parse only.
	assert(reader.parse_file(json_path, func(_json_path, _value):
		OwnerResourcePolicy._cached.json_records = 1
		return {"ok": true}
	).ok)
	assert(not reader.parse_file(json_path, accept_value).ok)
	var rich_path := "user://owner_resource_rtf_fixture.rtf"
	var rich_file := FileAccess.open(rich_path, FileAccess.WRITE)
	rich_file.store_string('{\\rtf1 abcdef}')
	rich_file.close()
	var importer := KnowledgeDocumentImporter.new()
	OwnerResourcePolicy._cached.knowledge_rich_chars = 2
	var limited_rtf := importer.extract(rich_path)
	assert(limited_rtf.ok and limited_rtf.text == "ab" and limited_rtf.truncated)
	OwnerResourcePolicy._cached.knowledge_rich_chars = 0
	var full_rtf := importer.extract(rich_path)
	assert(full_rtf.ok and full_rtf.text == "abcdef" and not full_rtf.truncated)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(json_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(rich_path))
	var docx_path := "user://owner_resource_docx_fixture.docx"
	var document_zip := ZIPPacker.new()
	assert(document_zip.open(ProjectSettings.globalize_path(docx_path)) == OK)
	assert(document_zip.start_file("word/document.xml") == OK)
	var xml := '<w:document><w:p>' + "data ".repeat(1000) + '</w:p></w:document>'
	assert(document_zip.write_file(xml.to_utf8_buffer()) == OK)
	assert(document_zip.close_file() == OK)
	assert(document_zip.close() == OK)
	OwnerResourcePolicy._cached.knowledge_xml_member_bytes = 32
	var rejected_docx := importer.extract(docx_path)
	assert(not rejected_docx.ok and rejected_docx.error.contains("owner byte budget"))
	OwnerResourcePolicy._cached.knowledge_xml_member_bytes = 0
	var complete_docx := importer.extract(docx_path)
	assert(complete_docx.ok and complete_docx.text.length() > 4000)
	var epub_path := "user://owner_resource_epub_fixture.epub"
	var epub_zip := ZIPPacker.new()
	assert(epub_zip.open(ProjectSettings.globalize_path(epub_path)) == OK)
	for name in ["a.xhtml", "b.xhtml"]:
		assert(epub_zip.start_file(name) == OK)
		assert(epub_zip.write_file(('<p>' + name + '</p>').to_utf8_buffer()) == OK)
		assert(epub_zip.close_file() == OK)
	assert(epub_zip.close() == OK)
	var directory := KnowledgeZipPreflight.new().inspect(epub_path, 1)
	assert(not directory.ok and directory.error.contains("owner entry budget"))
	OwnerResourcePolicy._cached.knowledge_epub_items = 1
	OwnerResourcePolicy._cached.knowledge_epub_bytes = 0
	var partial_epub := importer.extract(epub_path)
	assert(partial_epub.ok and partial_epub.entries_read == 1 and partial_epub.truncated)
	OwnerResourcePolicy._cached.knowledge_epub_items = 0
	OwnerResourcePolicy._cached.knowledge_epub_bytes = 1
	var blocked_epub := importer.extract(epub_path)
	assert(not blocked_epub.ok and blocked_epub.truncated and blocked_epub.error.contains("owner extraction budget"))
	OwnerResourcePolicy._cached.knowledge_epub_bytes = 0
	var complete_epub := importer.extract(epub_path)
	assert(complete_epub.ok and complete_epub.entries_read == 2 and not complete_epub.truncated)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(docx_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(epub_path))
	var registry := AuroraEvolutionExperimentRegistry.new()
	OwnerResourcePolicy._cached.evolution_recent_items = 0
	OwnerResourcePolicy._cached.evolution_phase_items = 0
	var current_experiment := registry.begin("fixture", "fixture")
	for i in range(70): registry.begin("fixture", str(i))
	for i in range(30): registry.advance(current_experiment.id, str(i))
	assert(registry.recent(0).size() == 71 and registry.get_record(current_experiment.id).phase_history.size() == 31)
	OwnerResourcePolicy._cached.evolution_phase_items = 2
	registry.advance(current_experiment.id, "last")
	assert(registry.get_record(current_experiment.id).phase_history.size() == 2)
	OwnerResourcePolicy._cached.evolution_recent_items = 2
	registry.begin("fixture", "last")
	assert(registry.recent(0).size() == 2)
	var adapter := AuroraEvolutionCoreTournamentAdapter.new()
	adapter._owns_pipeline_lock = true
	adapter._active_pipeline_lock_token = 1
	adapter._authorization_guard = func(): return false
	assert(not adapter._lock_token_current(1))
	adapter._authorization_guard = func(): return true
	assert(adapter._lock_token_current(1) and not adapter._lock_token_current(2))
	var now := int(Time.get_unix_time_from_system())
	OwnerResourcePolicy._cached.evolution_pending_items = 0
	for i in range(7): adapter._pending_winners[str(i)] = {"created_unix": now - i}
	adapter._pending_winners["expired"] = {"created_unix": now - OwnerResourcePolicy.DEFAULTS.evolution_pending_ttl_seconds - 1}
	adapter._trim_pending()
	assert(adapter._pending_winners.size() == 7 and not adapter._pending_winners.has("expired"))
	OwnerResourcePolicy._cached.evolution_pending_ttl_seconds = 0
	adapter._pending_winners["old"] = {"created_unix": now - OwnerResourcePolicy.DEFAULTS.evolution_pending_ttl_seconds - 1}
	adapter._trim_pending()
	assert(adapter._pending_winners.has("old"))
	OwnerResourcePolicy._cached.evolution_pending_items = 2
	adapter._trim_pending()
	assert(adapter._pending_winners.size() == 2 and adapter._pending_winners.has("0"))
	var attachments := AttachmentManager.new()
	var skill_steps: Array = []
	var skill_tools: Array = []
	for i in range(70): skill_steps.append("step" + str(i))
	for i in range(40): skill_tools.append("tool" + str(i))
	var imported_skill := {"name": long_text, "summary": long_text, "steps": skill_steps, "tools": skill_tools, "confidence": 1.0}
	var default_skill := attachments._sanitize_imported_skill(imported_skill)
	assert(default_skill.steps.size() == 64 and default_skill.tools.size() == 32 and default_skill.name.length() == 120)
	for key in ["skill_step_items", "skill_tool_items", "skill_name_chars", "skill_summary_chars", "skill_goal_chars", "skill_step_chars"]: OwnerResourcePolicy._cached[key] = 0
	var complete_skill := attachments._sanitize_imported_skill(imported_skill)
	assert(complete_skill.steps.size() == 70 and complete_skill.tools.size() == 40 and complete_skill.name == long_text)
	assert(complete_skill.confidence == 0.70) # Operational unlimited never grants imported claims full trust.
	attachments.intelligence.free()
	attachments.free()
	var chats := ChatStore.new()
	OwnerResourcePolicy._cached.chat_attachment_chars = 0
	assert(chats._compact_attachments([{ "content": long_text }])[0].excerpt == long_text)
	OwnerResourcePolicy._cached.chat_attachment_chars = 2
	assert(chats._compact_attachments([{ "content": "АБВГД" }])[0].excerpt == "АБ")
	chats.free()
	var work_store := AuroraWorkStore.new()
	OwnerResourcePolicy._cached.work_error_chars = 0
	var normalized := work_store._sanitize_task({"id": "fixture", "last_error": "token=private-secret " + long_text}, "project", {})
	assert(normalized.last_error.contains("[REDACTED]") and not normalized.last_error.contains("private-secret"))
	assert(normalized.last_error.contains(long_text))
	OwnerResourcePolicy._cached.work_error_chars = 2
	assert(work_store._sanitize_task({"id": "fixture", "last_error": "АБВГД"}, "project", {}).last_error == "АБ")
	work_store.free()
	var curator := AuroraLearningCurator.new()
	OwnerResourcePolicy._cached.learning_context_data_chars = 1
	var research_item := {"source": "fixture", "title": long_text, "summary": long_text, "url": "https://example.org/"}
	assert(curator._knowledge_text(research_item).begins_with(curator.UNTRUSTED_DATA_PREFIX))
	OwnerResourcePolicy._cached.learning_context_data_chars = 0
	OwnerResourcePolicy._cached.learning_title_chars = 0
	OwnerResourcePolicy._cached.learning_summary_chars = 0
	assert(curator._knowledge_text(research_item).contains(long_text))
	for i in range(5):
		curator._seen[str(i)] = {"content_sha256": str(i)}
		curator._seen_content[str(i)] = str(i)
		curator._claim_evidence[str(i)] = {"updated_unix": i}
		curator._gap_questions.append({"id": str(i), "status": "open", "priority": i, "updated_unix": i})
		curator._audit_events.append({"id": str(i)})
	for key in ["learning_seen_items", "learning_claim_items", "learning_gap_items", "learning_audit_items"]: OwnerResourcePolicy._cached[key] = 0
	curator._trim_seen()
	curator._trim_claim_evidence()
	curator._trim_gap_questions()
	curator._trim_audit_events()
	assert(curator._seen.size() == 5 and curator._claim_evidence.size() == 5 and curator._audit_events.size() == 5)
	assert(curator.open_questions(0).size() == 5)
	for key in ["learning_seen_items", "learning_claim_items", "learning_gap_items", "learning_audit_items"]: OwnerResourcePolicy._cached[key] = 2
	curator._trim_seen()
	curator._trim_claim_evidence()
	curator._trim_gap_questions()
	curator._trim_audit_events()
	assert(curator._seen.size() == 2 and curator._seen_content.size() == 2 and curator._claim_evidence.size() == 2)
	assert(curator._gap_questions.size() == 2 and curator._gap_questions[0].id == "4")
	assert(curator._audit_events.size() == 2 and curator._audit_events[0].id == "3")
	curator.free()
	var specialist := CodeSpecialist.new()
	var files: Array = [{"path": "a.py", "content": long_text}, {"path": "b.py", "content": long_text}]
	assert(specialist._files_context(files, 0).contains("b.py"))
	assert(specialist._files_context(files, 32).length() <= 32)
	assert(specialist._files_context(files, 1).is_empty())
	var large_source := "# padding\n".repeat(15000) + "def retained_public():\n    return 1\n"
	assert(specialist._missing_python_public_functions(large_source, "", "python") == ["retained_public"])
	var evidence := IsolatedExperience.new()
	OwnerResourcePolicy._cached.experience_failure_items = 0
	for i in range(305): evidence.record_failure("fixture", str(i))
	assert(evidence.failures.size() == 305)
	OwnerResourcePolicy._cached.experience_failure_items = 2
	evidence.record_failure("fixture", "last")
	assert(evidence.failures.size() == 2 and evidence.failures[-1].note == "last")
	OwnerResourcePolicy._cached.experience_checkpoint_items = 0
	OwnerResourcePolicy._cached.experience_result_chars = 0
	for i in range(505): evidence.checkpoint("fixture", i, "fixture", {}, "Я".repeat(4001))
	assert(evidence.checkpoints.size() == 505 and evidence.checkpoints[0].result_summary.length() > 4000)
	OwnerResourcePolicy._cached.experience_checkpoint_items = 2
	evidence.checkpoint("fixture", 506, "fixture", {}, "last")
	assert(evidence.checkpoints.size() == 2)
	OwnerResourcePolicy._cached.agent_max_steps = 0
	assert(agent._step_budget() == 0)
	agent.max_steps = 2
	assert(agent._step_budget() == 2) # Explicit caller override survives global unbounded.
	var fixture_ai := LoopFixtureAI.new()
	var cognition := CognitionLayer.new()
	cognition.setup(fixture_ai)
	fixture_ai.response = {"ok": false, "error": "fixture unavailable"}
	var unavailable := await cognition.verify_answer("fixture", "unverified", [])
	assert(not unavailable.ok and unavailable.confidence == 0.0 and unavailable.final_answer == "unverified")
	for content in ["bad json", "{}", '{"ok":true,"confidence":"high"}', '{"ok":true,"confidence":1.5,"final_answer":"x","issues":[]}']:
		fixture_ai.response = {"ok": true, "content": content}
		var invalid := await cognition.verify_answer("fixture", "unverified", [])
		assert(not invalid.ok and invalid.confidence == 0.0 and invalid.final_answer == "unverified")
	fixture_ai.response = {"ok": true, "content": '{"ok":true,"confidence":0.9,"final_answer":"verified","issues":[]}'}
	assert((await cognition.verify_answer("fixture", "unverified", [])).final_answer == "verified")
	cognition.free()
	fixture_ai.calls = 0
	fixture_ai.response = {"ok": true, "content": '{"tool":"fixture","args":{}}'}
	var fixture_tools := ToolRegistry.new()
	fixture_tools.register_tool("fixture", "in-memory regression only", {}, func(_args): return {"ok": true})
	agent.ai = fixture_ai
	agent.memory = store
	agent.tools = fixture_tools
	agent.experience.free()
	agent.experience = evidence
	agent.enable_planning = false
	agent.enable_specialist_team = false
	agent.enable_self_check = false
	agent.enable_skill_learning = false
	agent.enable_dream_cycle = false
	var bounded: String = await agent.run_task("fixture", [], Callable())
	assert(fixture_ai.calls == 2 and bounded.contains("лимит"))
	agent.max_steps = 18
	fixture_ai.calls = 0
	var guarded: String = await agent.run_task("fixture", [], func(stage, details):
		return {"allowed": false, "reason": "fixture-stop"} if stage == "before_model" and int(details.get("step", 0)) > 2 else {"allowed": true}
	)
	assert(fixture_ai.calls == 2 and guarded == AgentCore.EXECUTION_CONTROL_PREFIX + "fixture-stop")
	specialist.free()
	fixture_tools.free()
	fixture_ai.free()
	evidence.free()
	OwnerResourcePolicy._cached = original
	OwnerResourcePolicy.revision += 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	agent.free()
	desktop.free()
	store.free()
	print("AURORA_OWNER_RESOURCE_LIMITS_OK")
	quit(0)
