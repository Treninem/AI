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
	if str(info.get("runtime", "")) != "AuroraFox Core":
		_fail("Unexpected primary runtime: " + JSON.stringify(info), 3)
		return
	if OS.get_name() == "Windows":
		var desktop: Dictionary = info.get("desktop", {})
		if str(desktop.get("backend", "")) != "AuroraFox Core Engine":
			_fail("Windows Core Engine contract missing: " + JSON.stringify(desktop), 4)
			return
		if ai.core_engine_installer().is_empty():
			_fail("Core Engine installer was not discoverable", 5)
			return

	var source := "user://core_contract_training_any_name.json"
	var f := FileAccess.open(source, FileAccess.WRITE)
	if f == null:
		_fail("Cannot create temporary knowledge dataset", 6)
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
		_fail("Schema-free JSON import failed: " + JSON.stringify(imported), 7)
		return
	var search: Array = ai.search_knowledge("AuroraFox Core Knowledge contract", 4)
	if search.is_empty():
		_fail("Imported Core Knowledge cannot be retrieved", 8)
		return
	var sources: Array = ai.knowledge_sources()
	var found := false
	for row in sources:
		if row is Dictionary and str(row.get("source", "")) == source:
			found = true
			break
	if not found:
		_fail("Knowledge source inventory did not include imported dataset", 9)
		return

	# Re-import must replace the source rather than multiply old chunks forever.
	var before := int(ai.knowledge_stats().get("chunks", 0))
	var imported_again: Dictionary = ai.learn_from_file(source)
	if not bool(imported_again.get("ok", false)):
		_fail("Knowledge re-import failed", 10)
		return
	var after := int(ai.knowledge_stats().get("chunks", 0))
	if after != before:
		_fail("Knowledge re-import changed total chunk count; source replacement contract failed: %d -> %d" % [before, after], 11)
		return

	var cleaned := ai.remove_knowledge_source(source)
	if not bool(cleaned.get("ok", false)):
		_fail("Temporary knowledge source cleanup failed", 12)
		return
	if FileAccess.file_exists(source): DirAccess.remove_absolute(ProjectSettings.globalize_path(source))

	# With fallback explicitly disabled and no required test model, a failed chat
	# must remain a Core failure and never silently contact Ollama.
	var response: Dictionary = await ai.chat([{"role": "user", "content": "core contract"}], 0.0)
	if str(response.get("runtime", "")).begins_with("ollama"):
		_fail("Core contract unexpectedly used Ollama with fallback disabled", 13)
		return

	print("AURORA_CORE_BOOTSTRAP_CONTRACT_OK")
	print(JSON.stringify(info))
	ai.queue_free()
	await process_frame
	quit(0)
