class_name AIClient
extends Node

const DEFAULT_MODEL := "qwen3:8b"
const CHAT_MODEL_PRIORITY := [
	"qwen3",
	"gemma3",
	"llama3.3",
	"llama3.2",
	"llama3.1",
	"llama3",
	"mistral",
	"deepseek",
	"phi4",
	"qwen2.5",
	"qwen2",
	"gemma2",
	"gemma",
	"llama"
]

var base_url := "http://127.0.0.1:11434"
var model := DEFAULT_MODEL
var model_source := "default"
var android_model_path := "user://models/aurorafox-main.gguf"
var android_runtime := AndroidLocalRuntime.new()

func _ready() -> void:
	if android_runtime.get_parent() == null:
		add_child(android_runtime)

func configure(url: String, model_name: String) -> void:
	base_url = url.trim_suffix("/")
	model = model_name.strip_edges() if not model_name.strip_edges().is_empty() else DEFAULT_MODEL
	model_source = "configured"

func configure_android_model(path: String) -> void:
	android_model_path = path

func chat(messages: Array, temperature: float = 0.2) -> Dictionary:
	if OS.get_name() == "Android" and android_runtime.is_available():
		var local_path := ProjectSettings.globalize_path(android_model_path)
		return android_runtime.chat(local_path, messages, {"temperature": temperature})
	return await _chat_ollama(messages, temperature)

func _chat_ollama(messages: Array, temperature: float) -> Dictionary:
	var resolved := await ensure_ollama_model()
	if not resolved.get("ok", false):
		return resolved
	return await _send_ollama_chat(messages, temperature, [])

func _send_ollama_chat(messages: Array, temperature: float, failed_models: Array) -> Dictionary:
	var request_node := HTTPRequest.new()
	request_node.timeout = 180.0
	add_child(request_node)
	var payload := {
		"model": model,
		"messages": messages,
		"stream": false,
		"options": {"temperature": temperature}
	}
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := request_node.request(base_url + "/api/chat", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		request_node.queue_free()
		return {"ok": false, "error": "Не удалось обратиться к Ollama: %s" % error_string(err), "runtime": "ollama"}
	var result: Array = await request_node.request_completed
	request_node.queue_free()
	var response_code := int(result[1])
	var body: PackedByteArray = result[3]
	var body_text := body.get_string_from_utf8()
	if response_code < 200 or response_code >= 300:
		if response_code == 404 and body_text.to_lower().contains("model") and body_text.to_lower().contains("not found"):
			var failed := model
			if failed not in failed_models:
				failed_models.append(failed)
			var info := await _fetch_ollama_models()
			var installed: Array = []
			if info.get("ok", false):
				installed = info.get("installed", [])
				var replacement := choose_chat_model(installed, failed_models)
				if not replacement.is_empty() and replacement != failed:
					model = replacement
					model_source = "existing_ollama_retry"
					return await _send_ollama_chat(messages, temperature, failed_models)
			return {
				"ok": false,
				"error": "Ollama отвечает, но доступная chat-модель не найдена после отказа модели %s. Установленные модели: %s" % [failed, ", ".join(installed) if not installed.is_empty() else "нет моделей"],
				"runtime": "ollama",
				"model": failed,
				"failed_models": failed_models
			}
		return {
			"ok": false,
			"error": "Ollama HTTP %d: %s" % [response_code, body_text],
			"runtime": "ollama",
			"model": model
		}
	var data = JSON.parse_string(body_text)
	if not data is Dictionary:
		return {"ok": false, "error": "Некорректный ответ Ollama", "runtime": "ollama", "model": model}
	var message: Dictionary = data.get("message", {})
	return {
		"ok": true,
		"content": str(message.get("content", "")),
		"raw": data,
		"runtime": "ollama",
		"model": model,
		"model_source": model_source
	}

func is_available() -> bool:
	if OS.get_name() == "Android":
		if not android_runtime.is_available(): return false
		var caps := android_runtime.capabilities()
		return bool(caps.get("llama_cpp", false)) and FileAccess.file_exists(android_model_path)
	var info := await ensure_ollama_model()
	return bool(info.get("ok", false))

func ensure_ollama_model(force_refresh := false) -> Dictionary:
	if OS.get_name() == "Android":
		return {"ok": false, "error": "Ollama is not used on Android"}
	var info := await _fetch_ollama_models()
	if not info.get("ok", false):
		return info
	var installed: Array = info.get("installed", [])
	if installed.has(model) and _is_chat_model(model):
		return {
			"ok": true,
			"server": true,
			"model_available": true,
			"model": model,
			"model_source": model_source,
			"installed": installed
		}
	var selected := choose_chat_model(installed)
	if selected.is_empty():
		return {
			"ok": false,
			"server": true,
			"model_available": false,
			"model": model,
			"installed": installed,
			"error": "Ollama найдена, но в ней нет подходящей chat-модели. Установленные модели: %s" % (", ".join(installed) if not installed.is_empty() else "нет моделей")
		}
	var previous := model
	model = selected
	model_source = "existing_ollama"
	return {
		"ok": true,
		"server": true,
		"model_available": true,
		"model": model,
		"previous_model": previous,
		"auto_selected": true,
		"model_source": model_source,
		"installed": installed,
		"force_refresh": force_refresh
	}

func ollama_status() -> Dictionary:
	if OS.get_name() == "Android":
		return {"ok": false, "error": "Ollama is not used on Android"}
	var info := await _fetch_ollama_models()
	if not info.get("ok", false):
		return info
	var installed: Array = info.get("installed", [])
	var selected := model if installed.has(model) and _is_chat_model(model) else choose_chat_model(installed)
	return {
		"ok": true,
		"server": true,
		"model_available": not selected.is_empty(),
		"configured_model": model,
		"selected_model": selected,
		"installed": installed
	}

func _fetch_ollama_models() -> Dictionary:
	var request_node := HTTPRequest.new()
	request_node.timeout = 5.0
	add_child(request_node)
	var err := request_node.request(base_url + "/api/tags")
	if err != OK:
		request_node.queue_free()
		return {
			"ok": false,
			"server": false,
			"model_available": false,
			"error": "Ollama не отвечает на %s: %s" % [base_url, error_string(err)]
		}
	var result: Array = await request_node.request_completed
	request_node.queue_free()
	var code := int(result[1])
	if code != 200:
		return {"ok": false, "server": false, "model_available": false, "http": code, "error": "Ollama /api/tags HTTP %d" % code}
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary:
		return {"ok": false, "server": true, "model_available": false, "error": "Некорректный ответ Ollama /api/tags"}
	var installed: Array[String] = []
	for entry in parsed.get("models", []):
		if entry is Dictionary:
			var name := str(entry.get("name", entry.get("model", ""))).strip_edges()
			if not name.is_empty() and name not in installed:
				installed.append(name)
	installed.sort()
	return {"ok": true, "server": true, "installed": installed}

func choose_chat_model(installed: Array, excluded: Array = []) -> String:
	if installed.has(model) and _is_chat_model(model) and model not in excluded:
		return model
	if installed.has(DEFAULT_MODEL) and DEFAULT_MODEL not in excluded:
		return DEFAULT_MODEL
	var best := ""
	var best_score := -100000
	for value in installed:
		var candidate := str(value).strip_edges()
		if candidate in excluded or not _is_chat_model(candidate):
			continue
		var lower := candidate.to_lower()
		var score := 10
		for index in range(CHAT_MODEL_PRIORITY.size()):
			if lower.begins_with(str(CHAT_MODEL_PRIORITY[index])):
				score = 1000 - index * 30
				break
		if lower.contains("coder") or lower.contains("code"):
			score -= 120
		if lower.contains("-vl") or lower.contains(":vl") or lower.contains("vision"):
			score -= 80
		if lower.contains("latest"):
			score += 5
		if score > best_score:
			best_score = score
			best = candidate
	return best

func _is_chat_model(name: String) -> bool:
	var lower := name.to_lower()
	if lower.is_empty():
		return false
	for marker in ["embed", "embedding", "nomic-embed", "mxbai-embed", "bge-", "snowflake-arctic-embed"]:
		if lower.contains(marker):
			return false
	return true

func runtime_info() -> Dictionary:
	if OS.get_name() == "Android":
		return {
			"platform": "Android",
			"runtime": "llama.cpp",
			"model_path": android_model_path,
			"plugin": android_runtime.is_available(),
			"capabilities": android_runtime.capabilities()
		}
	return {
		"platform": OS.get_name(),
		"runtime": "Ollama",
		"base_url": base_url,
		"model": model,
		"model_source": model_source
	}
