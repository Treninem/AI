extends SceneTree

func _fail(ai: AIClient, message: String, code: int) -> void:
	push_error(message)
	ai.free()
	quit(code)

func _init() -> void:
	var ai := AIClient.new()

	# Ollama is compatibility-only. The current product no longer discovers or
	# selects an Ollama model for normal chat, so this smoke verifies only the
	# explicit compatibility configuration boundary.
	ai.configure_ollama_compatibility("http://127.0.0.1:11434/", "qwen3:8b")
	if ai.compatibility_url != "http://127.0.0.1:11434":
		_fail(ai, "Compatibility URL must be normalized", 2)
		return
	if ai.compatibility_model != "qwen3:8b":
		_fail(ai, "Configured compatibility model was not preserved", 3)
		return
	if ai.core_runtime.ollama_model != "qwen3:8b":
		_fail(ai, "Compatibility model did not reach legacy runtime adapter", 4)
		return

	ai.configure_ollama_compatibility("http://localhost:11434", "")
	if ai.compatibility_model != AIClient.LEGACY_OLLAMA_DEFAULT_MODEL:
		_fail(ai, "Empty compatibility model must use the legacy default", 5)
		return

	ai.configure_ollama_compatibility("http://localhost:11434", "llama3.2:latest")
	if ai.compatibility_model != "llama3.2:latest" or ai.core_runtime.ollama_model != "llama3.2:latest":
		_fail(ai, "Explicit installed compatibility model must remain configured", 6)
		return

	var info := ai.runtime_info()
	if not bool(info.get("self_primary", false)):
		_fail(ai, "AuroraFox Core must remain primary", 7)
		return
	if bool(info.get("external_ai_required", true)):
		_fail(ai, "Ollama must never become required for AuroraFox", 8)
		return
	if bool(info.get("normal_chat_external_fallback", true)):
		_fail(ai, "Normal chat must not gain an external fallback", 9)
		return
	if not bool(info.get("operational_without_ollama", false)):
		_fail(ai, "AuroraFox must remain operational without Ollama", 10)
		return

	ai.free()
	print("AURORA_OLLAMA_COMPATIBILITY_CONFIG_SMOKE_OK")
	quit(0)
