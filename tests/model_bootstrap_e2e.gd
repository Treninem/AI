extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _run() -> void:
	var ai := AIClient.new()
	root.add_child(ai)
	ai.set_ollama_fallback(false)
	await process_frame

	var info: Dictionary = ai.runtime_info()
	if bool(info.get("ollama_required", true)):
		_fail("AuroraFox Core still reports Ollama as required: " + JSON.stringify(info), 2)
		return
	if not bool(info.get("operational_without_ollama", false)):
		_fail("AIClient does not advertise local operation without Ollama", 3)
		return
	if str(info.get("runtime", "")) != "AuroraFox Core":
		_fail("Unexpected primary runtime: " + JSON.stringify(info), 4)
		return
	if OS.get_name() == "Windows":
		var desktop: Dictionary = info.get("desktop", {})
		if str(desktop.get("backend", "")) != "AuroraFox Core Engine":
			_fail("Windows Core Engine contract missing: " + JSON.stringify(desktop), 5)
			return
		if ai.core_engine_installer().is_empty():
			_fail("Core Engine installer was not discoverable", 6)
			return

	var source := "user://core_contract_training_any_name.json"
	var f := FileAccess.open(source, FileAccess.WRITE)
	if f == null:
		_fail("Cannot create temporary knowledge dataset", 7)
		return
	f.store_string(JSON.stringify({
		"random_container": {
			"workflow": {"name": "demo", "steps": ["alpha", "beta"]},
			"template": {"question": "ping", "answer": "pong"},
			"fact": "AuroraFox Core Knowledge contract"
		}
	}))
	f.close()

	var imported: Dictionary = ai.learn_from_file(source)
	if not bool(imported.get("ok", false)):
		_fail("Schema-free JSON import failed: " + JSON.stringify(imported), 8)
		return
	var search: Array = ai.search_knowledge("AuroraFox Core Knowledge contract", 4)
	if search.is_empty():
		_fail("Imported Core Knowledge cannot be retrieved", 9)
		return
	var sources: Array = ai.knowledge_sources()
	var found := false
	for row in sources:
		if row is Dictionary and str(row.get("source", "")) == source:
			found = true
			break
	if not found:
		_fail("Knowledge source inventory did not include imported dataset", 10)
		return

	# Re-import must replace the source rather than multiply old chunks forever.
	var before := int(ai.knowledge_stats().get("chunks", 0))
	var imported_again: Dictionary = ai.learn_from_file(source)
	if not bool(imported_again.get("ok", false)):
		_fail("Knowledge re-import failed", 11)
		return
	var after := int(ai.knowledge_stats().get("chunks", 0))
	if after != before:
		_fail("Knowledge re-import changed total chunk count; source replacement contract failed: %d -> %d" % [before, after], 12)
		return

	var cleaned := ai.remove_knowledge_source(source)
	if not bool(cleaned.get("ok", false)):
		_fail("Temporary knowledge source cleanup failed", 13)
		return
	if FileAccess.file_exists(source): DirAccess.remove_absolute(ProjectSettings.globalize_path(source))

	# Fallback disabled: no request may be delegated to Ollama.
	var response: Dictionary = await ai.chat([{"role": "user", "content": "core contract"}], 0.0)
	if str(response.get("runtime", "")).begins_with("ollama"):
		_fail("Core contract unexpectedly used Ollama with fallback disabled", 14)
		return

	# Deterministic outage contract: once a compatibility attempt has failed the
	# circuit is opened immediately, so later user work never waits on the dead
	# adapter. This intentionally does not make a live network request in CI.
	ai.configure("http://127.0.0.1:1", "unreachable-test-model")
	ai.set_ollama_fallback(true)
	ai.core_runtime._record_ollama_failure("deterministic unavailable adapter")
	var outage: Dictionary = await ai.chat([{"role":"user", "content":"compatibility outage contract"}], 0.0)
	if str(outage.get("runtime", "")).begins_with("ollama"):
		_fail("Ollama outage replaced the AuroraFox Core result", 15)
		return
	var outage_info := ai.runtime_info()
	if not bool(outage_info.get("ollama_circuit_open", false)):
		_fail("Ollama outage did not open the non-blocking compatibility circuit", 16)
		return
	var adapter: Dictionary = outage.get("compatibility_adapter", {})
	if not bool(adapter.get("ignored", false)) or not bool(adapter.get("circuit_open", false)):
		_fail("Open compatibility circuit was not ignored by the local-first router", 17)
		return
	ai.set_ollama_fallback(false)

	# Autonomous core evolution may rewrite only a narrow allowlist and must never
	# gain access to updater/security/runtime validation code.
	var pipeline := CoreImprovementPipeline.new()
	if not pipeline._target_allowed("scripts/agent_core.gd"):
		_fail("Core improvement allowlist does not include AgentCore", 18)
		return
	for blocked in ["update/update_manager.gd", "scripts/runtime_extension_manager.gd", "scripts/core_improvement_pipeline.gd", "project.godot"]:
		if pipeline._target_allowed(blocked):
			_fail("Core improvement pipeline allows protected target: " + blocked, 19)
			return
	var selected := pipeline._select_target("улучшить память и поиск знаний", "")
	if selected != "scripts/memory_store.gd":
		_fail("Core improvement target selection contract failed: " + selected, 20)
		return
	pipeline.free()

	print("AURORA_CORE_BOOTSTRAP_CONTRACT_OK")
	print(JSON.stringify(info))
	ai.queue_free()
	await process_frame
	quit(0)
