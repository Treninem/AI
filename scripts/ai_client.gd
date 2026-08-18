class_name AIClient
extends Node

var base_url := "http://127.0.0.1:11434"
var model := "qwen3:8b"
var android_model_path := "user://models/aurorafox-main.gguf"
var android_runtime := AndroidLocalRuntime.new()

func _ready() -> void:
	if android_runtime.get_parent() == null:
		add_child(android_runtime)

func configure(url: String, model_name: String) -> void:
	base_url = url.trim_suffix("/")
	model = model_name

func configure_android_model(path: String) -> void:
	android_model_path = path

func chat(messages: Array, temperature: float = 0.2) -> Dictionary:
	if OS.get_name() == "Android" and android_runtime.is_available():
		var local_path := ProjectSettings.globalize_path(android_model_path)
		return android_runtime.chat(local_path, messages, {"temperature": temperature})
	return await _chat_ollama(messages, temperature)

func _chat_ollama(messages: Array, temperature: float) -> Dictionary:
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
		return {"ok": false, "error": "HTTPRequest error %s" % err}
	var result: Array = await request_node.request_completed
	request_node.queue_free()
	var response_code := int(result[1])
	var body: PackedByteArray = result[3]
	if response_code < 200 or response_code >= 300:
		return {"ok": false, "error": "Ollama HTTP %d: %s" % [response_code, body.get_string_from_utf8()]}
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		return {"ok": false, "error": "Invalid Ollama response"}
	var message: Dictionary = data.get("message", {})
	return {"ok": true, "content": str(message.get("content", "")), "raw": data, "runtime": "ollama"}

func is_available() -> bool:
	if OS.get_name() == "Android":
		if not android_runtime.is_available(): return false
		var caps := android_runtime.capabilities()
		return bool(caps.get("llama_cpp", false)) and FileAccess.file_exists(android_model_path)
	var request_node := HTTPRequest.new()
	request_node.timeout = 5.0
	add_child(request_node)
	var err := request_node.request(base_url + "/api/tags")
	if err != OK:
		request_node.queue_free()
		return false
	var result: Array = await request_node.request_completed
	request_node.queue_free()
	return int(result[1]) == 200

func runtime_info() -> Dictionary:
	if OS.get_name() == "Android":
		return {
			"platform": "Android",
			"runtime": "llama.cpp",
			"model_path": android_model_path,
			"plugin": android_runtime.is_available(),
			"capabilities": android_runtime.capabilities()
		}
	return {"platform": OS.get_name(), "runtime": "Ollama", "base_url": base_url, "model": model}
