class_name FileIntelligenceClient
extends Node

const BASE_URL := "http://127.0.0.1:8767"

var backend_pid := 0
var runtime_root := ""

func _ready() -> void:
	if OS.get_name() == "Windows":
		_start_backend_if_installed()

func _exit_tree() -> void:
	if OS.get_name() == "Windows" and backend_pid > 0:
		OS.kill(backend_pid)
		backend_pid = 0

func health() -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Rich File Intelligence backend is not available on this platform yet", "platform": OS.get_name()}
	return await _request("/health", HTTPClient.METHOD_GET, {}, 4.0)

func analyze_file(path: String, question := "", visual := true, max_chars := 160000) -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Rich file analysis is not available on this platform yet", "platform": OS.get_name()}
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	return await _request("/analyze", HTTPClient.METHOD_POST, {
		"path": absolute,
		"question": question,
		"visual": visual,
		"max_chars": clampi(max_chars, 2000, 500000)
	}, 600.0)

func tree(path: String, max_items := 2000) -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Directory intelligence is not available on this platform yet"}
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	return await _request("/tree", HTTPClient.METHOD_POST, {"path": absolute, "max_items": clampi(max_items, 1, 5000)}, 60.0)

func search_cache(query: String, limit := 20) -> Dictionary:
	if OS.get_name() != "Windows": return {"ok": false, "results": []}
	return await _request("/cache/search", HTTPClient.METHOD_POST, {"query": query, "limit": clampi(limit, 1, 100)}, 30.0)

func clear_cache() -> Dictionary:
	if OS.get_name() != "Windows": return {"ok": true, "removed": 0}
	return await _request("/cache/clear", HTTPClient.METHOD_POST, {}, 30.0)

func runtime_is_installed() -> bool:
	return not _find_runtime().is_empty()

func installer_path() -> String:
	for root in _candidate_roots():
		var path := root.path_join("install_files.ps1")
		if FileAccess.file_exists(path): return path
	return ""

func restart_backend() -> void:
	if OS.get_name() != "Windows": return
	if backend_pid > 0:
		OS.kill(backend_pid)
		backend_pid = 0
	_start_backend_if_installed()

func _start_backend_if_installed() -> void:
	var found := _find_runtime()
	if found.is_empty(): return
	runtime_root = str(found.get("root", ""))
	OS.set_environment("AURORAFOX_USER_DIR", ProjectSettings.globalize_path("user://"))
	var executable := str(found.get("pythonw", ""))
	if executable.is_empty() or not FileAccess.file_exists(executable): executable = str(found.get("python", ""))
	if executable.is_empty() or not FileAccess.file_exists(executable): return
	backend_pid = OS.create_process(executable, PackedStringArray([str(found.get("service", ""))]), false)

func _find_runtime() -> Dictionary:
	for root in _candidate_roots():
		var service := root.path_join("file_service.py")
		var pythonw := root.path_join(".venv/Scripts/pythonw.exe")
		var python := root.path_join(".venv/Scripts/python.exe")
		if FileAccess.file_exists(service) and (FileAccess.file_exists(pythonw) or FileAccess.file_exists(python)):
			return {"root": root, "service": service, "pythonw": pythonw, "python": python}
	return {}

func _candidate_roots() -> Array[String]:
	return [
		OS.get_executable_path().get_base_dir().path_join("file_intelligence"),
		ProjectSettings.globalize_path("res://file_intelligence")
	]

func _request(path: String, method: HTTPClient.Method, payload: Dictionary, timeout := 60.0) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	var err := req.request(BASE_URL + path, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "File Intelligence request error: %s" % error_string(err)}
	var result: Array = await req.request_completed
	req.queue_free()
	var code := int(result[1])
	var raw := (result[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		if code >= 200 and code < 300: return parsed
		return {"ok": false, "http": code, "error": str(parsed.get("detail", parsed.get("error", raw)))}
	return {"ok": false, "http": code, "error": raw.substr(0, 4000)}
