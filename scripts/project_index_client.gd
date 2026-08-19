class_name ProjectIndexClient
extends Node

const BASE_URL := "http://127.0.0.1:8768"

var backend_pid := 0

func _ready() -> void:
	if OS.get_name() == "Windows": _start_backend()

func _exit_tree() -> void:
	if OS.get_name() == "Windows" and backend_pid > 0:
		OS.kill(backend_pid)
		backend_pid = 0

func health() -> Dictionary:
	if OS.get_name() != "Windows": return {"ok": false, "error": "Project index is currently Windows-only"}
	return await _request("/health", HTTPClient.METHOD_GET, {}, 5.0)

func index_project(root: String, max_files := 30000, force := false) -> Dictionary:
	if OS.get_name() != "Windows": return {"ok": false, "error": "Project index is currently Windows-only"}
	return await _request("/index", HTTPClient.METHOD_POST, {
		"root": _globalize(root), "max_files": clampi(max_files, 1, 100000), "force": force
	}, 900.0)

func search(root: String, query: String, limit := 20, language := "") -> Dictionary:
	if OS.get_name() != "Windows": return {"ok": false, "results": [], "error": "Project index is currently Windows-only"}
	return await _request("/search", HTTPClient.METHOD_POST, {
		"root": _globalize(root) if not root.is_empty() else "",
		"query": query,
		"limit": clampi(limit, 1, 100),
		"language": language
	}, 60.0)

func search_symbols(root: String, query: String, limit := 50) -> Dictionary:
	if OS.get_name() != "Windows": return {"ok": false, "results": [], "error": "Project index is currently Windows-only"}
	return await _request("/symbols", HTTPClient.METHOD_POST, {
		"root": _globalize(root) if not root.is_empty() else "", "query": query, "limit": clampi(limit, 1, 200)
	}, 60.0)

func status(root := "") -> Dictionary:
	if OS.get_name() != "Windows": return {"ok": false, "error": "Project index is currently Windows-only"}
	var suffix := ""
	if not root.is_empty(): suffix = "?root=" + _globalize(root).uri_encode()
	return await _request("/status" + suffix, HTTPClient.METHOD_GET, {}, 30.0)

func clear(root := "") -> Dictionary:
	if OS.get_name() != "Windows": return {"ok": true}
	var suffix := ""
	if not root.is_empty(): suffix = "?root=" + _globalize(root).uri_encode()
	return await _request("/clear" + suffix, HTTPClient.METHOD_POST, {}, 30.0)

func _start_backend() -> void:
	var root := _runtime_root()
	if root.is_empty(): return
	var service := root.path_join("project_index_service.py")
	var pythonw := root.path_join(".venv/Scripts/pythonw.exe")
	var python := root.path_join(".venv/Scripts/python.exe")
	var executable := pythonw if FileAccess.file_exists(pythonw) else python
	if not FileAccess.file_exists(service) or not FileAccess.file_exists(executable): return
	OS.set_environment("AURORAFOX_USER_DIR", ProjectSettings.globalize_path("user://"))
	backend_pid = OS.create_process(executable, PackedStringArray([service]), false)

func _runtime_root() -> String:
	for root in [OS.get_executable_path().get_base_dir().path_join("file_intelligence"), ProjectSettings.globalize_path("res://file_intelligence")]:
		if FileAccess.file_exists(root.path_join("project_index_service.py")) and (FileAccess.file_exists(root.path_join(".venv/Scripts/pythonw.exe")) or FileAccess.file_exists(root.path_join(".venv/Scripts/python.exe"))):
			return root
	return ""

func _globalize(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path

func _request(path: String, method: HTTPClient.Method, payload: Dictionary, timeout := 60.0) -> Dictionary:
	var last_error := ""
	for attempt in range(2):
		var req := HTTPRequest.new()
		req.timeout = timeout
		add_child(req)
		var headers := PackedStringArray(["Content-Type: application/json"])
		var body := "" if payload.is_empty() else JSON.stringify(payload)
		var err := req.request(BASE_URL + path, headers, method, body)
		if err == OK:
			var result: Array = await req.request_completed
			req.queue_free()
			var code := int(result[1])
			var raw := (result[3] as PackedByteArray).get_string_from_utf8()
			var parsed = JSON.parse_string(raw)
			if code >= 200 and code < 300 and parsed is Dictionary: return parsed
			if code > 0:
				return {"ok": false, "http": code, "error": str(parsed.get("detail", raw)) if parsed is Dictionary else raw.substr(0, 4000)}
			last_error = "Project index backend is not ready"
		else:
			last_error = error_string(err)
			req.queue_free()
		if attempt == 0:
			if backend_pid <= 0: _start_backend()
			await get_tree().create_timer(0.8).timeout
	return {"ok": false, "error": last_error}
