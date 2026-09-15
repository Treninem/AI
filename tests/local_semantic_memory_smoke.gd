extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _run() -> void:
	var vectorizer := AuroraLocalSemanticVectorizer.new()
	var info := vectorizer.model_info()
	if bool(info.get("network_required", true)) or bool(info.get("external_runtime_required", true)):
		_fail("Local semantic vectorizer unexpectedly requires network/runtime", 2)
		return
	var a := vectorizer.embed("стабильная калибровка полипропиленовой трубки экструзионной линии")
	var b := vectorizer.embed("калибровка трубки на экструдере")
	var unrelated := vectorizer.embed("музыкальная композиция и вокальная партия")
	if vectorizer.similarity(a, b) <= vectorizer.similarity(a, unrelated):
		_fail("Local semantic vectorizer does not rank related Russian text above unrelated text", 3)
		return

	var memory := MemoryStore.new()
	root.add_child(memory)
	await process_frame
	memory.set_legacy_semantic_compat_enabled(true)
	memory.remember("semantic_smoke", "Устойчивая калибровка полипропиленовой трубки на экструзионной линии", "semantic_smoke", 0.9, 0.95)
	memory.reindex_semantic()
	var status := memory.semantic_status()
	if str(status.get("provider", "")) != "aurorafox_local_vector":
		_fail("MemoryStore is not using AuroraFox local vector provider", 4)
		return
	if bool(status.get("network_required", true)) or bool(status.get("external_runtime_required", true)) or bool(status.get("ollama_required", true)):
		_fail("Memory semantic status still depends on external infrastructure", 5)
		return
	if not str(status.get("endpoint", "unexpected")).is_empty():
		_fail("Local semantic memory exposes a network endpoint", 6)
		return
	var found := memory.retrieve("калибровка трубки экструдер", 8, true, false)
	var matched := false
	for item in found:
		if item is Dictionary and str(item.get("source", "")) == "semantic_smoke":
			matched = true
			break
	if not matched:
		_fail("Local semantic memory could not retrieve the inserted related memory", 7)
		return
	memory.queue_free()
	await process_frame
	print("AURORA_LOCAL_SEMANTIC_MEMORY_SMOKE_OK provider=aurorafox_local_vector network=false ollama=false")
	quit(0)
