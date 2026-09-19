class_name FileIntelligenceClient
extends Node

const BASE_URL := "http://127.0.0.1:8767"
const ANDROID_OCR_EXTENSIONS := ["pdf", "png", "jpg", "jpeg", "webp", "bmp", "tif", "tiff"]
const ANDROID_ANALYSIS_TIMEOUT_MS := 600000

var backend_pid := 0
var runtime_root := ""
var _active_request: HTTPRequest = null
var _active_android_job_id := ""
var _cancel_requested := false

func _ready() -> void:
	if OS.get_name() == "Windows":
		_start_backend_if_installed()

func _exit_tree() -> void:
	if _active_request != null:
		_active_request.cancel_request()
		_active_request = null
	if OS.get_name() == "Android" and not _active_android_job_id.is_empty() and Engine.has_singleton("AuroraFoxRuntime"):
		var plugin := Engine.get_singleton("AuroraFoxRuntime")
		# Godot Android release singletons expose @UsedByGodot methods through
		# call(), but has_method() can incorrectly report false (see
		# AndroidLocalRuntime). The job id exists only after this known API was
		# called successfully, so cancel directly and fail closed nowhere else.
		if plugin != null:
			plugin.call("cancelAnalyzeLocalFile", _active_android_job_id)
		_active_android_job_id = ""
	if OS.get_name() == "Windows" and backend_pid > 0:
		OS.kill(backend_pid)
		backend_pid = 0

func health() -> Dictionary:
	if OS.get_name() == "Android":
		if not Engine.has_singleton("AuroraFoxRuntime"):
			return {"ok": false, "error": "AuroraFoxRuntime Android plugin is unavailable"}
		var plugin := Engine.get_singleton("AuroraFoxRuntime")
		var raw = plugin.call("getCapabilitiesJson")
		var caps = JSON.parse_string(str(raw))
		if not caps is Dictionary:
			return {"ok": false, "error": "Invalid Android runtime capabilities"}
		var file_ready := bool(caps.get("file_intelligence", false))
		var ocr_ready := bool(caps.get("local_ocr", false))
		var warnings: Array[String] = []
		if not file_ready:
			warnings.append("Android File Intelligence runtime is unavailable.")
		elif not ocr_ready:
			warnings.append("Android local OCR models/runtime are unavailable; non-OCR file parsing remains available.")
		return {
			"ok": file_ready,
			"backend": "AuroraFileIntelligence",
			"runtime": "android-native",
			"vision_online": false,
			"vision_model": "",
			"voice_online": bool(caps.get("sherpa_stt", false)),
			"local_tts": bool(caps.get("local_tts", false)),
			"local_ocr": ocr_ready,
			"ocr": caps.get("local_ocr_health", {}),
			"cancellation_supported": bool(caps.get("file_analysis_cancel", false)),
			"external_ai_required": false,
			"capabilities": caps,
			"warnings": warnings
		}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "File Intelligence is not available on this platform", "platform": OS.get_name()}
	var status := await _request("/health", HTTPClient.METHOD_GET, {}, 4.0)
	if bool(status.get("ok", false)):
		status["cancellation_supported"] = true
	return status

func analyze_file(path: String, question := "", visual := true, max_chars := 160000) -> Dictionary:
	_cancel_requested = false
	if OS.get_name() == "Android":
		if not Engine.has_singleton("AuroraFoxRuntime"):
			return {"ok": false, "error": "AuroraFoxRuntime Android plugin is unavailable"}
		var private_path := _android_private_copy(path)
		if private_path.is_empty():
			return {"ok": false, "error": "Не удалось скопировать выбранный файл в приватную песочницу AuroraFox"}
		var plugin := Engine.get_singleton("AuroraFoxRuntime")
		var extension := path.get_extension().to_lower()
		# Do not use Object.has_method() here. In a release Android APK it may
		# hide a callable @UsedByGodot plugin method and incorrectly turn local
		# OCR into an "unsupported" external-AI error.
		if extension in ANDROID_OCR_EXTENSIONS:
			var async_result: Dictionary = await _analyze_android_job(plugin, private_path, question, visual)
			return _decorate_android_result(async_result, path, private_path, max_chars)
		var raw = plugin.call("analyzeLocalFile", private_path, question, visual)
		var parsed = JSON.parse_string(str(raw))
		if parsed is Dictionary:
			return _decorate_android_result(parsed, path, private_path, max_chars)
		return {"ok": false, "error": "Invalid Android File Intelligence response"}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Rich file analysis is not available on this platform", "platform": OS.get_name()}
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	return await _request("/analyze", HTTPClient.METHOD_POST, {
		"path": absolute,
		"question": question,
		"visual": visual,
		"max_chars": clampi(max_chars, 2000, 500000)
	}, 600.0, true)

func cancel_active_analysis() -> Dictionary:
	_cancel_requested = true
	if OS.get_name() == "Android":
		if _active_android_job_id.is_empty() or not Engine.has_singleton("AuroraFoxRuntime"):
			return {"ok": true, "cancel_requested": false, "reason": "no_active_analysis"}
		var plugin := Engine.get_singleton("AuroraFoxRuntime")
		if plugin == null:
			return {"ok": false, "cancel_requested": false, "error": "Android cancellation API is unavailable"}
		var raw = plugin.call("cancelAnalyzeLocalFile", _active_android_job_id)
		var parsed = JSON.parse_string(str(raw))
		return parsed if parsed is Dictionary else {"ok": true, "cancel_requested": true}
	if OS.get_name() == "Windows":
		if _active_request == null:
			return {"ok": true, "cancel_requested": false, "reason": "no_active_analysis"}
		return {"ok": true, "cancel_requested": true, "mode": "client_request_cancel"}
	return {"ok": true, "cancel_requested": false, "reason": "unsupported_platform"}

func tree(path: String, max_items := 2000) -> Dictionary:
	if OS.get_name() == "Android":
		if not path.begins_with("user://") or not Engine.has_singleton("AuroraFoxRuntime"):
			return {"ok": false, "error": "Android directory tree is restricted to user://"}
		var plugin := Engine.get_singleton("AuroraFoxRuntime")
		var raw = plugin.call("treeLocal", ProjectSettings.globalize_path(path), clampi(max_items, 1, 5000))
		return _parse_native(raw)
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Directory intelligence is not available on this platform"}
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	return await _request("/tree", HTTPClient.METHOD_POST, {"path": absolute, "max_items": clampi(max_items, 1, 5000)}, 60.0)

func search_cache(query: String, limit := 20) -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok": false, "results": [], "error": "Cache search is currently Windows-only"}
	return await _request("/cache/search", HTTPClient.METHOD_POST, {"query": query, "limit": clampi(limit, 1, 100)}, 30.0)

func clear_cache() -> Dictionary:
	if OS.get_name() == "Android":
		if not Engine.has_singleton("AuroraFoxRuntime"):
			return {"ok": false, "error": "Android runtime unavailable"}
		var plugin := Engine.get_singleton("AuroraFoxRuntime")
		if not plugin.has_method("clearFileCache"):
			return {"ok": false, "error": "clearFileCache unavailable"}
		return _parse_native(plugin.call("clearFileCache"))
	if OS.get_name() != "Windows":
		return {"ok": true, "removed": 0}
	return await _request("/cache/clear", HTTPClient.METHOD_POST, {}, 30.0)

func runtime_is_installed() -> bool:
	if OS.get_name() == "Android":
		return Engine.has_singleton("AuroraFoxRuntime")
	return not _find_runtime().is_empty()

func installer_path() -> String:
	if OS.get_name() != "Windows":
		return ""
	for root in _candidate_roots():
		var path := root.path_join("install_files.ps1")
		if FileAccess.file_exists(path):
			return path
	return ""

func restart_backend() -> void:
	if OS.get_name() != "Windows":
		return
	if backend_pid > 0:
		OS.kill(backend_pid)
		backend_pid = 0
	_start_backend_if_installed()

func _start_backend_if_installed() -> void:
	var found := _find_runtime()
	if found.is_empty():
		return
	runtime_root = str(found.get("root", ""))
	var executable := str(found.get("pythonw", ""))
	if executable.is_empty() or not FileAccess.file_exists(executable):
		executable = str(found.get("python", ""))
	if executable.is_empty() or not FileAccess.file_exists(executable):
		return
	OS.set_environment("AURORAFOX_USER_DIR", ProjectSettings.globalize_path("user://"))
	var vendor := str(found.get("vendor", ""))
	var inject_vendor := not vendor.is_empty() and DirAccess.dir_exists_absolute(vendor)
	var had_pythonpath := OS.has_environment("PYTHONPATH")
	var previous_pythonpath := OS.get_environment("PYTHONPATH") if had_pythonpath else ""
	if inject_vendor:
		OS.set_environment("PYTHONPATH", vendor)
	backend_pid = OS.create_process(executable, PackedStringArray([str(found.get("service", ""))]), false)
	if inject_vendor:
		if had_pythonpath:
			OS.set_environment("PYTHONPATH", previous_pythonpath)
		else:
			OS.unset_environment("PYTHONPATH")

func _find_runtime() -> Dictionary:
	for root in _candidate_roots():
		var service := root.path_join("file_service.py")
		if not FileAccess.file_exists(service):
			continue
		var portable_pythonw := root.path_join("python/pythonw.exe")
		var portable_python := root.path_join("python/python.exe")
		if FileAccess.file_exists(portable_pythonw) or FileAccess.file_exists(portable_python):
			return {
				"root": root,
				"service": service,
				"pythonw": portable_pythonw,
				"python": portable_python,
				"vendor": root.path_join("vendor"),
				"portable": true
			}
		var pythonw := root.path_join(".venv/Scripts/pythonw.exe")
		var python := root.path_join(".venv/Scripts/python.exe")
		if FileAccess.file_exists(pythonw) or FileAccess.file_exists(python):
			return {"root": root, "service": service, "pythonw": pythonw, "python": python, "vendor": "", "portable": false}
	return {}

func _candidate_roots() -> Array[String]:
	return [
		OS.get_executable_path().get_base_dir().path_join("file_intelligence"),
		ProjectSettings.globalize_path("res://file_intelligence")
	]

func _android_private_copy(path: String) -> String:
	var user_root := ProjectSettings.globalize_path("user://")
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path
	if absolute.begins_with(user_root):
		return absolute
	var src := FileAccess.open(path, FileAccess.READ)
	if src == null and absolute != path:
		src = FileAccess.open(absolute, FileAccess.READ)
	if src == null:
		return ""
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
	if out.is_empty():
		out = "file.bin"
	return out.substr(0, 120)

func _parse_native(raw: Variant) -> Dictionary:
	var parsed = JSON.parse_string(str(raw))
	return parsed if parsed is Dictionary else {"ok": false, "error": "Invalid Android native response"}

func _decorate_android_result(parsed: Dictionary, original_path: String, private_path: String, max_chars: int) -> Dictionary:
	parsed["path"] = original_path
	parsed["private_copy"] = private_path
	if str(parsed.get("content", "")).length() > max_chars:
		parsed["content"] = str(parsed.get("content", "")).substr(0, max_chars) + "\n[Обрезано AuroraFox]"
		parsed["truncated"] = true
	return parsed

func _analyze_android_job(plugin: Object, private_path: String, question: String, visual: bool) -> Dictionary:
	var start_raw = plugin.call("startAnalyzeLocalFile", private_path, question, visual)
	var start = JSON.parse_string(str(start_raw))
	if not start is Dictionary or not bool(start.get("ok", false)):
		return start if start is Dictionary else {"ok": false, "error": "Invalid Android analysis job response"}
	var job_id := str(start.get("job_id", ""))
	if job_id.is_empty():
		return {"ok": false, "error": "Android analysis job id is missing"}
	_active_android_job_id = job_id
	var started_ms := Time.get_ticks_msec()
	var cancel_sent := false
	while Time.get_ticks_msec() - started_ms <= ANDROID_ANALYSIS_TIMEOUT_MS:
		if _cancel_requested and not cancel_sent:
			plugin.call("cancelAnalyzeLocalFile", job_id)
			cancel_sent = true
		var poll_raw = plugin.call("pollAnalyzeLocalFile", job_id)
		var poll = JSON.parse_string(str(poll_raw))
		if not poll is Dictionary:
			_active_android_job_id = ""
			return {"ok": false, "error": "Invalid Android analysis poll response"}
		if not bool(poll.get("pending", false)):
			_active_android_job_id = ""
			var result = poll.get("result", {})
			if result is Dictionary:
				return result
			return {"ok": false, "error": str(poll.get("error", "Android analysis job returned no result"))}
		await get_tree().create_timer(0.05).timeout
	plugin.call("cancelAnalyzeLocalFile", job_id)
	_active_android_job_id = ""
	return {"ok": false, "cancelled": true, "error": "Android file analysis timed out"}

func _request(path: String, method: HTTPClient.Method, payload: Dictionary, timeout := 60.0, track_analysis := false) -> Dictionary:
	var last_error := ""
	for attempt in range(2):
		if track_analysis and _cancel_requested:
			return {"ok": false, "cancelled": true, "error": "File analysis cancelled"}
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
			var result: Array = []
			if track_analysis:
				_active_request = req
				var state := {"done": false, "result": []}
				req.request_completed.connect(func(result_code, response_code, response_headers, response_body):
					state["done"] = true
					state["result"] = [result_code, response_code, response_headers, response_body]
				, CONNECT_ONE_SHOT)
				while not bool(state.get("done", false)):
					if _cancel_requested:
						req.cancel_request()
						if _active_request == req:
							_active_request = null
						req.queue_free()
						return {"ok": false, "cancelled": true, "error": "File analysis cancelled"}
					await get_tree().process_frame
				result = state.get("result", [])
				if _active_request == req:
					_active_request = null
			else:
				result = await req.request_completed
			req.queue_free()
			if result.size() < 4:
				last_error = "File Intelligence returned an incomplete HTTP response"
			else:
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
			if backend_pid <= 0:
				_start_backend_if_installed()
			await get_tree().create_timer(0.9).timeout
	return {"ok": false, "error": last_error if not last_error.is_empty() else "File Intelligence unavailable"}
