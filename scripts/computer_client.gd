class_name ComputerClient
extends Node

var base_url := "http://127.0.0.1:8766"

func _json_request(path: String, method: HTTPClient.Method, payload: Dictionary = {}) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 240.0
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	var err := req.request(base_url + path, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "HTTPRequest error %s" % err}
	var result: Array = await req.request_completed
	req.queue_free()
	var code := int(result[1])
	var raw: PackedByteArray = result[3]
	var text := raw.get_string_from_utf8()
	var data = JSON.parse_string(text)
	if code < 200 or code >= 300:
		return {"ok": false, "error": text, "http": code}
	if data is Dictionary:
		return data
	return {"ok": false, "error": "Invalid response"}

func health() -> Dictionary:
	return await _json_request("/health", HTTPClient.METHOD_GET)

func plan(goal: String) -> Dictionary:
	return await _json_request("/plan", HTTPClient.METHOD_POST, {"goal": goal, "max_steps": 1, "auto_execute": false})

func run(goal: String, max_steps: int = 30, auto_execute: bool = true) -> Dictionary:
	return await _json_request("/run", HTTPClient.METHOD_POST, {"goal": goal, "max_steps": max_steps, "auto_execute": auto_execute})

func action(data: Dictionary) -> Dictionary:
	return await _json_request("/action", HTTPClient.METHOD_POST, data)

func sandbox_exec(command: Array[String], cwd: String = ".", timeout: int = 60) -> Dictionary:
	return await _json_request("/sandbox/exec", HTTPClient.METHOD_POST, {"command": command, "cwd": cwd, "timeout": timeout})

func sandbox_write(path: String, content: String) -> Dictionary:
	return await _json_request("/sandbox/write", HTTPClient.METHOD_POST, {"path": path, "content": content})
