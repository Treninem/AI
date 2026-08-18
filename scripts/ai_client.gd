class_name AIClient
extends Node

var base_url := "http://127.0.0.1:11434"
var model := "qwen3:8b"

func configure(url: String, model_name: String) -> void:
	base_url = url.trim_suffix("/")
	model = model_name

func chat(messages: Array, temperature: float = 0.2) -> Dictionary:
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
	return {"ok": true, "content": str(message.get("content", "")), "raw": data}

func is_available() -> bool:
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
