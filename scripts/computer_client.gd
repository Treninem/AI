class_name ComputerClient
extends Node

var base_url := "http://127.0.0.1:8766"
var backend_pid := 0
var runtime_root := ""

func _ready() -> void:
	if OS.get_name() == "Windows":
		_start_backend_if_installed()

func _exit_tree() -> void:
	if OS.get_name() == "Windows" and backend_pid > 0:
		OS.kill(backend_pid)
		backend_pid = 0

func runtime_is_installed() -> bool:
	return not _find_runtime().is_empty()

func installer_path() -> String:
	for root in _candidate_roots():
		var path := root.path_join("install_computer.ps1")
		if FileAccess.file_exists(path): return path
	return ""

func restart_backend() -> void:
	if backend_pid > 0:
		OS.kill(backend_pid)
		backend_pid = 0
	_start_backend_if_installed()

func _start_backend_if_installed() -> void:
	var found := _find_runtime()
	if found.is_empty(): return
	runtime_root = str(found.get("root", ""))
	OS.set_environment("AURORAFOX_SANDBOX_ROOT", ProjectSettings.globalize_path("user://sandboxes"))
	var executable := str(found.get("pythonw", ""))
	if executable.is_empty() or not FileAccess.file_exists(executable):
		executable = str(found.get("python", ""))
	if executable.is_empty() or not FileAccess.file_exists(executable): return
	backend_pid = OS.create_process(executable, PackedStringArray([str(found.get("service", ""))]), false)

func _find_runtime() -> Dictionary:
	for root in _candidate_roots():
		var service := root.path_join("computer_service.py")
		var pythonw := root.path_join(".venv/Scripts/pythonw.exe")
		var python := root.path_join(".venv/Scripts/python.exe")
		if FileAccess.file_exists(service) and (FileAccess.file_exists(pythonw) or FileAccess.file_exists(python)):
			return {"root": root, "service": service, "pythonw": pythonw, "python": python}
	return {}

func _candidate_roots() -> Array[String]:
	return [
		OS.get_executable_path().get_base_dir().path_join("computer"),
		ProjectSettings.globalize_path("res://computer")
	]

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
