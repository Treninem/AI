extends SceneTree

func _init() -> void:
	var ai := AIClient.new()
	ai.model = "qwen3:8b"

	var selected := ai.choose_chat_model([
		"qwen3-embedding:0.6b",
		"gemma3:latest"
	])
	if selected != "gemma3:latest":
		push_error("Expected existing gemma3 chat model, got: " + selected)
		ai.free()
		quit(2)
		return

	selected = ai.choose_chat_model([
		"nomic-embed-text:latest",
		"mxbai-embed-large:latest"
	])
	if not selected.is_empty():
		push_error("Embedding-only Ollama install must not be selected for chat: " + selected)
		ai.free()
		quit(3)
		return

	ai.model = "llama3.2:latest"
	selected = ai.choose_chat_model([
		"gemma3:latest",
		"llama3.2:latest"
	])
	if selected != "llama3.2:latest":
		push_error("Configured installed model should be preserved, got: " + selected)
		ai.free()
		quit(4)
		return

	# Regression: Ollama may report a stale/broken model in /api/tags while
	# /api/chat returns 404 for it. The retry selector must blacklist it.
	ai.model = "qwen3:8b"
	selected = ai.choose_chat_model([
		"qwen3:8b",
		"gemma3:latest",
		"nomic-embed-text:latest"
	], ["qwen3:8b"])
	if selected != "gemma3:latest":
		push_error("Broken qwen3 must be skipped after 404, got: " + selected)
		ai.free()
		quit(5)
		return

	ai.free()
	print("AURORA_OLLAMA_MODEL_SELECTION_SMOKE_OK")
	quit(0)
