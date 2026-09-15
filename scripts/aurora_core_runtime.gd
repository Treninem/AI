class_name AuroraCoreRuntime
extends Node

const DEFAULT_MODEL_PATH := "user://models/aurorafox-main.gguf"

var model_path := DEFAULT_MODEL_PATH
var android_runtime := AndroidLocalRuntime.new()
var allow_ollama_fallback := true
var ollama_base_url := "http://127.0.0.1:11434"
var ollama_model := "qwen3:8b"

func _ready() -> void:
	if android_runtime.get_parent() == null:
		add_child(android_runtime)

func configure_model(path: String) -> void:
	if not path.strip_edges().is_empty():
		model_path = path

func configure_legacy_ollama(url: String, model_name: String) -> void:
	ollama_base_url = url.trim_suffix("/")
	if not model_name.strip_edges().is_empty():
		ollama_model = model_name.strip_edges()

func chat(messages: Array, temperature := 0.2) -> Dictionary:
	var local := await _chat_local(messages, temperature)
	if bool(local.get("ok", false)):
		return local
	if allow_ollama_fallback and OS.get_name() != "Android":
		var legacy := await _chat_ollama(messages, temperature)
		if bool(legacy.get("ok", false)):
			legacy["fallback_from"] = local.get("runtime", "aurora_core")
			return legacy
	return local

func _chat_local(messages: Array, temperature: float) -> Dictionary:
	if OS.get_name() == "Android":
		if not android_runtime.is_available():
			return {"ok": false, "runtime": "aurora_core", "error": "Встроенное ядро AuroraFox недоступно в этой сборке"}
		var caps := android_runtime.capabilities()
		if not bool(caps.get("llama_cpp", false)):
			return {"ok": false, "runtime": "aurora_core", "error": "Встроенный inference runtime не включен", "capabilities": caps}
		if not FileAccess.file_exists(model_path):
			return {"ok": false, "runtime": "aurora_core", "error": "Локальная модель AuroraFox не установлена", "model_path": model_path}
		var result := android_runtime.chat(ProjectSettings.globalize_path(model_path), messages, {"temperature": temperature})
		result["runtime"] = "aurora_core"
		result["model_path"] = model_path
		return result
	# Desktop native backend is intentionally addressed through AuroraFox Core,
	# not through a mandatory third-party AI client. A packaged llama.cpp/GDExtension
	# backend can implement this interface without changing callers.
	if Engine.has_singleton("AuroraFoxRuntime"):
		var plugin := Engine.get_singleton("AuroraFoxRuntime")
		if plugin != null and plugin.has_method("chatLocal") and FileAccess.file_exists(model_path):
			var raw = plugin.call("chatLocal", ProjectSettings.globalize_path(model_path), JSON.stringify(messages), JSON.stringify({"temperature": temperature}))
			var parsed = JSON.parse_string(str(raw)) if raw is String else raw
			if parsed is Dictionary:
				parsed["runtime"] = "aurora_core"
				parsed["model_path"] = model_path
				return parsed
	return {"ok": false, "runtime": "aurora_core", "error": "Локальное ядро готово к подключению desktop inference backend", "model_path": model_path}

func _chat_ollama(messages: Array, temperature: float) -> Dictionary:
	var request_node := HTTPRequest.new()
	request_node.timeout = 180.0
	add_child(request_node)
	var payload := {"model": ollama_model, "messages": messages, "stream": false, "options": {"temperature": temperature}}
	var err := request_node.request(ollama_base_url + "/api/chat", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		request_node.queue_free()
		return {"ok": false, "runtime": "ollama_legacy", "error": "Необязательный Ollama fallback недоступен"}
	var result: Array = await request_node.request_completed
	request_node.queue_free()
	if int(result[1]) < 200 or int(result[1]) >= 300:
		return {"ok": false, "runtime": "ollama_legacy", "error": "Ollama fallback HTTP %d" % int(result[1])}
	var data = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if not data is Dictionary:
		return {"ok": false, "runtime": "ollama_legacy", "error": "Некорректный ответ Ollama fallback"}
	return {"ok": true, "content": str((data.get("message", {}) as Dictionary).get("content", "")), "raw": data, "runtime": "ollama_legacy", "model": ollama_model}

func runtime_info() -> Dictionary:
	return {"runtime": "AuroraFox Core", "local_first": true, "model_path": model_path, "model_installed": FileAccess.file_exists(model_path), "ollama_required": false, "ollama_fallback": allow_ollama_fallback}
