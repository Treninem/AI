class_name DesktopLocalRuntime
extends Node

const HOST := "127.0.0.1"
const PORT := 8766
const BASE_URL := "http://127.0.0.1:8766"
const MODEL_ALIAS := "AuroraFox-Core"
const STARTUP_ATTEMPTS := 480
const DEFAULT_CHAT_MAX_TOKENS := 2048
const TERSE_CHAT_MAX_TOKENS := 128
const DEFAULT_CHAT_TIMEOUT_SECONDS := 180.0
const DEFAULT_CONTEXT_SIZE := 16384

var server_pid := 0
var active_model := ""
var starting := false

func _exit_tree() -> void:
	stop()

func is_available() -> bool:
	return OS.get_name() == "Windows" and not engine_path().is_empty()

func engine_path() -> String:
	if OS.get_name() != "Windows": return ""
	for root in _candidate_roots():
		var direct := root.path_join("engine/llama-server.exe")
		if FileAccess.file_exists(direct): return direct
		var nested := _find_server_recursive(root.path_join("engine"), 2)
		if not nested.is_empty(): return nested
	return ""

func installer_path() -> String:
	if OS.get_name() != "Windows": return ""
	for root in _candidate_roots():
		var path := root.path_join("install_core.ps1")
		if FileAccess.file_exists(path): return path
	return ""

func chat(model_path: String, messages: Array, options: Dictionary = {}) -> Dictionary:
	if OS.get_name() != "Windows": return {"ok": false, "runtime": "aurora_core_desktop", "error": "Desktop Core runtime is Windows-only"}
	var absolute_model := ProjectSettings.globalize_path(model_path) if model_path.begins_with("user://") or model_path.begins_with("res://") else model_path
	if not FileAccess.file_exists(absolute_model): return {"ok": false, "runtime": "aurora_core_desktop", "error": "Встроенный AuroraFox Core отсутствует или повреждён. Восстановите установку AuroraFox.", "model_path": model_path}
	var ready := await ensure_server(absolute_model)
	if not bool(ready.get("ok", false)): return ready
	var terse_request := _is_explicit_terse_request(messages)
	var default_max_tokens := TERSE_CHAT_MAX_TOKENS if terse_request else DEFAULT_CHAT_MAX_TOKENS
	var max_tokens := clampi(int(options.get("max_tokens", default_max_tokens)), 64, 8192)
	var request_timeout := clampf(float(options.get("timeout_seconds", DEFAULT_CHAT_TIMEOUT_SECONDS)), 5.0, 600.0)
	var payload := {
		"model": MODEL_ALIAS,
		"messages": messages,
		"temperature": float(options.get("temperature", 0.2)),
		"max_tokens": max_tokens,
		"stream": false
	}
	# Explicitly terse user requests do not benefit from hundreds of hidden
	# reasoning tokens. Current bundled llama.cpp understands the OpenAI-style
	# reasoning_effort override and maps "none" to enable_thinking=false. This
	# improves exact-format compliance and latency without disabling reasoning
	# for normal, complex AuroraFox conversations.
	if terse_request and not options.has("reasoning_effort"):
		payload["reasoning_effort"] = "none"
	elif options.has("reasoning_effort"):
		payload["reasoning_effort"] = str(options.get("reasoning_effort", ""))
	var response := await _request_json("/v1/chat/completions", HTTPClient.METHOD_POST, payload, request_timeout)
	if not bool(response.get("ok", false)): return response
	var data: Dictionary = response.get("data", {})
	var choices: Array = data.get("choices", [])
	if choices.is_empty() or not choices[0] is Dictionary:
		return {"ok": false, "runtime": "aurora_core_desktop", "error": "AuroraFox Core вернул ответ без choices", "raw": data}
	var message = choices[0].get("message", {})
	if not message is Dictionary:
		return {"ok": false, "runtime": "aurora_core_desktop", "error": "AuroraFox Core вернул некорректное сообщение", "raw": data}
	return {"ok": true, "runtime": "aurora_core_desktop", "content": str(message.get("content", "")), "raw": data, "model": MODEL_ALIAS, "model_path": model_path, "max_tokens": max_tokens, "terse_request": terse_request}

func ensure_server(model_absolute_path: String) -> Dictionary:
	if not is_available():
		return {"ok": false, "runtime": "aurora_core_desktop", "error": "Встроенный AuroraFox Core Engine отсутствует или повреждён", "installer": installer_path()}

	# WindowsStartupCoordinator warms the Core in the background. A real user
	# message can arrive while that same model is still loading. Never stop that
	# startup or return "already starting"; join it and let the first message use
	# the server as soon as /health becomes ready.
	if starting:
		return await _wait_for_existing_start(model_absolute_path)

	if server_pid > 0 and OS.is_process_running(server_pid) and active_model == model_absolute_path:
		var health := await _request_json("/health", HTTPClient.METHOD_GET, {}, 2.0)
		if bool(health.get("ok", false)): return {"ok": true, "runtime": "aurora_core_desktop", "reused": true}
		stop()

	starting = true
	var exe := engine_path()
	var args := PackedStringArray([
		"-m", model_absolute_path,
		"--host", HOST,
		"--port", str(PORT),
		"--ctx-size", str(DEFAULT_CONTEXT_SIZE),
		"--alias", MODEL_ALIAS,
		"--jinja"
	])
	server_pid = OS.create_process(exe, args, false)
	if server_pid <= 0:
		starting = false
		return {"ok": false, "runtime": "aurora_core_desktop", "error": "Не удалось запустить встроенный AuroraFox Core Engine", "engine": exe}
	active_model = model_absolute_path
	for _attempt in range(STARTUP_ATTEMPTS):
		if server_pid <= 0 or not OS.is_process_running(server_pid):
			starting = false
			server_pid = 0
			return {"ok": false, "runtime": "aurora_core_desktop", "error": "AuroraFox Core Engine завершился во время загрузки встроенного AI"}
		var health := await _request_json("/health", HTTPClient.METHOD_GET, {}, 1.0)
		if bool(health.get("ok", false)):
			starting = false
			return {"ok": true, "runtime": "aurora_core_desktop", "engine": exe, "pid": server_pid}
		await get_tree().create_timer(0.25).timeout
	starting = false
	stop()
	return {"ok": false, "runtime": "aurora_core_desktop", "error": "AuroraFox Core не успел подготовиться за 120 секунд"}

func _wait_for_existing_start(model_absolute_path: String) -> Dictionary:
	for _attempt in range(STARTUP_ATTEMPTS):
		if not starting:
			if server_pid > 0 and OS.is_process_running(server_pid) and active_model == model_absolute_path:
				var final_health := await _request_json("/health", HTTPClient.METHOD_GET, {}, 2.0)
				if bool(final_health.get("ok", false)):
					return {"ok": true, "runtime": "aurora_core_desktop", "reused": true, "joined_warmup": true}
			return {"ok": false, "runtime": "aurora_core_desktop", "error": "Фоновая подготовка AuroraFox Core завершилась неуспешно"}
		if active_model != model_absolute_path and not active_model.is_empty():
			return {"ok": false, "runtime": "aurora_core_desktop", "error": "AuroraFox Core занят подготовкой другого внутреннего профиля"}
		await get_tree().create_timer(0.25).timeout
	return {"ok": false, "runtime": "aurora_core_desktop", "error": "Ожидание фоновой подготовки AuroraFox Core превысило 120 секунд"}

func stop() -> void:
	if server_pid > 0 and OS.is_process_running(server_pid): OS.kill(server_pid)
	server_pid = 0
	active_model = ""
	starting = false

func runtime_info() -> Dictionary:
	return {
		"backend": "AuroraFox Core Engine",
		"engine_installed": is_available(),
		"engine_path": engine_path(),
		"installer": installer_path(),
		"running": server_pid > 0 and OS.is_process_running(server_pid),
		"starting": starting,
		"pid": server_pid,
		"active_model": active_model,
		"endpoint": BASE_URL,
		"default_chat_max_tokens": DEFAULT_CHAT_MAX_TOKENS,
		"terse_chat_max_tokens": TERSE_CHAT_MAX_TOKENS,
		"default_chat_timeout_seconds": DEFAULT_CHAT_TIMEOUT_SECONDS,
		"context_size": DEFAULT_CONTEXT_SIZE
	}

func _is_explicit_terse_request(messages: Array) -> bool:
	var prompt := ""
	for i in range(messages.size() - 1, -1, -1):
		if messages[i] is Dictionary and str(messages[i].get("role", "")) == "user":
			prompt = str(messages[i].get("content", "")).to_lower().strip_edges()
			break
	if prompt.is_empty():
		return false
	var markers := [
		"reply only", "reply exactly", "output exactly", "nothing else",
		"one word", "one short", "только с", "ответь ровно", "выведи ровно",
		"ничего больше", "одной короткой", "только маркер", "только кодовое"
	]
	for marker in markers:
		if prompt.contains(marker):
			return true
	return false

func _request_json(path: String, method: HTTPClient.Method, payload: Dictionary, timeout: float) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := req.request(BASE_URL + path, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "runtime": "aurora_core_desktop", "error": "Core Engine request: %s" % error_string(err)}
	var result: Array = await req.request_completed
	req.queue_free()
	var code := int(result[1])
	var raw := (result[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(raw)
	if code >= 200 and code < 300:
		return {"ok": true, "http": code, "data": parsed if parsed is Dictionary else {}, "raw": raw}
	return {"ok": false, "runtime": "aurora_core_desktop", "http": code, "error": raw.substr(0, 3000)}

func _candidate_roots() -> Array[String]:
	return [
		OS.get_executable_path().get_base_dir().path_join("core_runtime"),
		ProjectSettings.globalize_path("res://core_runtime")
	]

func _find_server_recursive(root: String, depth: int) -> String:
	if depth < 0 or not DirAccess.dir_exists_absolute(root): return ""
	var dir := DirAccess.open(root)
	if dir == null: return ""
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty(): break
		if name in [".", ".."]: continue
		var is_dir := dir.current_is_dir()
		var full := root.path_join(name)
		if not is_dir and name.to_lower() == "llama-server.exe":
			dir.list_dir_end()
			return full
		if is_dir and depth > 0:
			var found := _find_server_recursive(full, depth - 1)
			if not found.is_empty():
				dir.list_dir_end()
				return found
	dir.list_dir_end()
	return ""
