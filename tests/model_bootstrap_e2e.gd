extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _run() -> void:
	var ai := AIClient.new()
	root.add_child(ai)

	var status: Dictionary = await ai.ollama_status()
	if not status.get("ok", false):
		_fail("Ollama status failed: " + JSON.stringify(status), 2)
		return
	if not status.get("model_available", false):
		_fail("qwen3:8b is not available after bootstrap: " + JSON.stringify(status), 3)
		return

	var response: Dictionary = await ai.chat([
		{"role": "system", "content": "Reply with one short plain sentence."},
		{"role": "user", "content": "Say that AuroraFox local AI is ready."}
	], 0.0)
	if not response.get("ok", false):
		_fail("AIClient chat failed: " + JSON.stringify(response), 4)
		return
	var content := str(response.get("content", "")).strip_edges()
	if content.is_empty():
		_fail("AIClient returned an empty Ollama response", 5)
		return
	if str(response.get("runtime", "")) != "ollama":
		_fail("AIClient did not use the Ollama runtime", 6)
		return

	print("AURORA_MODEL_BOOTSTRAP_E2E_OK")
	print(content.substr(0, 300))
	ai.queue_free()
	await process_frame
	quit(0)
