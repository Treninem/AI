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
	if OS.get_name() == "Android":
		if not Engine.has_singleton("AuroraFoxRuntime"):
			return {"ok": false, "error": "AuroraFoxRuntime Android plugin is unavailable"}
		var plugin := Engine.get_singleton("AuroraFoxRuntime")
		var raw = plugin.call("getCapabilitiesJson") if plugin.has_method("getCapabilitiesJson") else "{}"
		var caps = JSON.parse_string(str(raw))
		if not caps is Dictionary:
			return {"ok": false, "error": "Invalid Android runtime capabilities"}
		var file_ready := bool(caps.get("file_intelligence", false))
		return {
			"ok": file_ready,
			"backend": "AuroraFileIntelligence",
			"runtime": "android-native",
			"vision_online": false,
			"vision_model": "",
			"voice_online": bool(caps.get("sherpa_stt", false)),
			"local_tts": bool(caps.get("local_tts", false)),
			"capabilities": caps,
			"warnings": ["Android File Intelligence currently provides native document/media metadata and local STT, but no deep local vision/OCR backend."] if file_ready else []
		}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "File Intelligence is not available on this platform", "platform": OS.get_name()}
	return await _request("/health", HTTPClient.METHOD_GET, {}, 4.0)

func analyze_file(path: String, question := "", visual := true, max_chars := 160000) -> Dictionary:
	if OS.get_name() == "Android":
		if not Engine.has_singleton("AuroraFoxRuntime"):
			return {"ok": false, "error": "AuroraFoxRuntime Android plugin is unavailable"}
		var private_path := _android_private_copy(path)
		if private_path.is_empty():
			return {"ok": false, "error": "Не удалось скопировать выбранный файл в приватную песочницу AuroraFox"}
		var plugin := Engine.get_singleton("AuroraFoxRuntime")
		if not plugin.has_method("analyzeLocalFile"):
			return {"ok": false, "error": "Android runtime does not expose File Intelligence"}
		var raw = plugin.call("analyzeLocalFile", private_path, question, visual)
		var parsed = JSON.parse_string(str(raw))
		if parsed is Dictionary:
			parsed["path"] = path
			parsed["private_copy"] = private_path
			if str(parsed.get("content", "")).length() > max_chars:
				parsed["content"] = str(parsed.get("content", "")).substr(0, max_chars) + "\n[Обрезано AuroraFox]"
				parsed["truncated"] = true
			return parsed
		return {"ok": false, "error": "Invalid Android File Intelligence response"}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Rich file analysis is not available on this platform", "platform": OS.get_name()}
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	return await _request("/analyze", HTTPClient.METHOD_POST, {
		"path": absolute,
		"question": question,
		"visual": visual,
		"max_chars": clampi(max_chars, 2000, 500000)
	}, 600.0)

func tree(path: String, max_items := 2000) -> Dictionary:
	if OS.get_name() == "Android":
		if not path.begins_with("user://") or not Engine.has_singleton("AuroraFoxRuntime"):
			return {"ok": false, "error": "Android directory tree is restricted to user://"}
		var plugin := Engine.get_singleton("AuroraFoxRuntime")
		if not plugin.has_method("treeLocal"): return {"ok": false, "error": "Android treeLocal is unavailable"}
		var raw = plugin.call("treeLocal", ProjectSettings.globalize_path(path), clampi(max_items, 1, 5000))
		return _parse_native(raw)
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Directory intelligence is not available on this platform"}
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	return await _request("/tree", HTTPClient.METHOD_POST, {"path": absolute, "max_items": clampi(max_items, 1, 5000)}, 60.0)

func search_cache(query: String, limit := 20) -> Dictionary:
	if OS.get_name() != "Windows": return {"ok": false, "results": [], "error": "Cache search is currently Windows-only"}
	return await _request("/cache/search", HTTPClient.METHOD_POST, {"query": query, "limit": clampi(limit, 1, 100)}, 30.0)

func clear_cache() -> Dictionary:
	if OS.get_name() == "Android":
		if not Engine.has_singleton("AuroraFoxRuntime"): return {"ok": false, "error": "Android runtime unavailable"}
		var plugin := Engine.get_singleton("AuroraFoxRuntime")
		if not plugin.has_method("clearFileCache"): return {"ok": false, "error": "clearFileCache unavailable"}
		return _parse_native(plugin.call("clearFileCache"))
	if OS.get_name() != "Windows": return {"ok": true, "removed": 0}
	return await _request("/cache/clear", HTTPClient.METHOD_POST, {}, 30.0)

func runtime_is_installed() -> bool:
	if OS.get_name() == "Android":
		return Engine.has_singleton("AuroraFoxRuntime")
	return not _find_runtime().is_empty()

func installer_path() -> String:
	if OS.get_name() != "Windows": return ""
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

func _android_private_copy(path: String) -> String:
	var user_root := ProjectSettings.globalize_path("user://")
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path
	if absolute.begins_with(user_root): return absolute
	var src := FileAccess.open(path, FileAccess.READ)
	if src == null and absolute != path: src = FileAccess.open(absolute, FileAccess.READ)
	if src == null: return ""
	var target_dir := "user://file_inputs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_dir))
	var safe_name := _safe_filename(path.get_file())
	var target := "%s/%d_%s" % [target_dir, Time.get_ticks_msec(), safe_name]
	var dst := FileAccess.open(target, FileAccess.WRITE)
	if dst == null:
		src.close()
		return ""
	var total := src.get_length()
	while src.get_position() < total:
		var remaining := total - src.get_position()
		dst.store_buffer(src.get_buffer(mini(1024 * 1024, remaining)))
	src.close()
	dst.close()
	return ProjectSettings.globalize_path(target)

func _safe_filename(value: String) -> String:
	var out := value
	for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		out = out.replace(bad, "_")
	out = out.strip_edges()
	if out.is_empty(): out = "file.bin"
	return out.substr(0, 120)

func _parse_native(raw: Variant) -> Dictionary:
	var parsed = JSON.parse_string(str(raw))
	return parsed if parsed is Dictionary else {"ok": false, "error": "Invalid Android native response"}

func _request(path: String, method: HTTPClient.Method, payload: Dictionary, timeout := 60.0) -> Dictionary:
	var last_error := ""
	for attempt in range(2):
		var req := HTTPRequest.new()
		req.timeout = timeout
		add_child(req)
		var headers := PackedStringArray(["Content-Type: application/json"])
		var body := "" if payload.is_empty() else JSON.stringify(payload)
		var err := req.request(BASE_URL + path, headers, method, body)
		if err != OK:
			last_error = "File Intelligence request error: %s" % error_string(err)
			req.queue_free()
		else:
			var result: Array = await req.request_completed
			req.queue_free()
			var code := int(result[1])
			var raw := (result[3] as PackedByteArray).get_string_from_utf8()
			var parsed = JSON.parse_string(raw)
			if code >= 200 and code < 300 and parsed is Dictionary:
				return parsed
			if code > 0:
				if parsed is Dictionary:
					return {"ok": false, "http": code, "error": str(parsed.get("detail", parsed.get("error", raw)))}
				return {"ok": false, "http": code, "error": raw.substr(0, 4000)}
			last_error = "File Intelligence backend is not ready"
		if attempt == 0 and OS.get_name() == "Windows" and runtime_is_installed():
			if backend_pid <= 0: _start_backend_if_installed()
			await get_tree().create_timer(0.9).timeout
	return {"ok": false, "error": last_error if not last_error.is_empty() else "File Intelligence unavailable"}
