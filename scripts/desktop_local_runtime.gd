class_name DesktopLocalRuntime
extends Node

const HOST := "127.0.0.1"
const PORT := 8766
const BASE_URL := "http://127.0.0.1:8766"
const MODEL_ALIAS := "AuroraFox-Core"
const STARTUP_ATTEMPTS := 480
const JOINED_WARMUP_ATTEMPTS := 120
const DEFAULT_CHAT_MAX_TOKENS := 768
const TERSE_CHAT_MAX_TOKENS := 128
const DEFAULT_CHAT_TIMEOUT_SECONDS := 90.0
const DEFAULT_CONTEXT_SIZE := 4096
const DEFAULT_PARALLEL_SLOTS := 1
const DEFAULT_THREADS := 4
const DEFAULT_BATCH_SIZE := 64
const DEFAULT_UBATCH_SIZE := 32

var server_pid := 0
var active_model := ""
var starting := false
var _active_streams: Array[HTTPClient] = []
var _stream_cancel_epoch := 0

func _exit_tree() -> void:
	# Tree teardown is the one path that must always terminate an owned process,
	# even when the model is still loading.
	stop(true)

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
	var structured_request := _is_strict_structured_request(messages)
	var max_tokens := _generation_budget(options, terse_request)
	if max_tokens == -2:
		return {"ok": false, "error": "Invalid Core token budget: expected integer -1..2147483647", "model_failure": false, "retryable": false, "failure_scope": "request_budget"}
	var request_timeout := maxf(0.0, float(options.get("timeout_seconds", DEFAULT_CHAT_TIMEOUT_SECONDS)))
	var wait_limits := CoreWaitPolicy.limits()
	var stall_timeout := float(wait_limits.stall_timeout_seconds)
	# Preserve an explicit per-request override without making it a total deadline.
	if options.has("timeout_seconds"): stall_timeout = request_timeout
	var total_timeout := float(wait_limits.total_timeout_seconds)
	var response_bytes := int(wait_limits.response_max_bytes)
	var payload := {
		"model": MODEL_ALIAS,
		"messages": messages,
		"temperature": float(options.get("temperature", 0.2)),
		"max_tokens": max_tokens,
		"stream": true,
		"return_progress": true
	}
	# Exact terse and strict structured responses do not benefit from hidden
	# reasoning tokens that can consume the whole request deadline before any
	# visible JSON is emitted. Current bundled llama.cpp maps the OpenAI-style
	# "none" override to enable_thinking=false. Normal conversations retain the
	# full reasoning path and strict JSON keeps the normal 2048-token ceiling.
	if (terse_request or structured_request) and not options.has("reasoning_effort"):
		payload["reasoning_effort"] = "none"
	elif options.has("reasoning_effort"):
		payload["reasoning_effort"] = str(options.get("reasoning_effort", ""))
	var response := await _request_progress_json(payload, stall_timeout, total_timeout, response_bytes)
	if not bool(response.get("ok", false)): return response
	var data: Dictionary = response.get("data", {})
	var choices: Array = data.get("choices", [])
	if choices.is_empty() or not choices[0] is Dictionary:
		return {"ok": false, "runtime": "aurora_core_desktop", "error": "AuroraFox Core вернул ответ без choices", "raw": data, "failure_scope": "request", "model_failure": false, "retryable": true}
	var message = choices[0].get("message", {})
	if not message is Dictionary:
		return {"ok": false, "runtime": "aurora_core_desktop", "error": "AuroraFox Core вернул некорректное сообщение", "raw": data, "failure_scope": "request", "model_failure": false, "retryable": true}
	return {"ok": true, "runtime": "aurora_core_desktop", "content": str(message.get("content", "")), "raw": data, "model": MODEL_ALIAS, "model_path": model_path, "max_tokens": max_tokens, "terse_request": terse_request, "structured_request": structured_request}

func ensure_server(model_absolute_path: String) -> Dictionary:
	if not is_available():
		return {"ok": false, "runtime": "aurora_core_desktop", "error": "Встроенный AuroraFox Core Engine отсутствует или повреждён", "installer": installer_path()}

	# Multiple messages can arrive while the first on-demand startup is loading.
	# Join the same bounded startup instead of spawning competing engine processes.
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
		"--parallel", str(DEFAULT_PARALLEL_SLOTS),
		"--threads", str(DEFAULT_THREADS),
		"--threads-batch", str(DEFAULT_THREADS),
		"--batch-size", str(DEFAULT_BATCH_SIZE),
		"--ubatch-size", str(DEFAULT_UBATCH_SIZE),
		"--alias", MODEL_ALIAS,
		"--jinja"
	])
	# Opt-in CI synthetic benchmark log; normal private chat enables no file log.
	var benchmark_log := OS.get_environment("AURORAFOX_BENCHMARK_CORE_LOG_PATH")
	if not benchmark_log.is_empty():
		args.append_array(PackedStringArray(["--log-file", benchmark_log]))
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
	for _attempt in range(JOINED_WARMUP_ATTEMPTS):
		if not starting:
			if server_pid > 0 and OS.is_process_running(server_pid) and active_model == model_absolute_path:
				var final_health := await _request_json("/health", HTTPClient.METHOD_GET, {}, 2.0)
				if bool(final_health.get("ok", false)):
					return {"ok": true, "runtime": "aurora_core_desktop", "reused": true, "joined_warmup": true}
			return {"ok": false, "runtime": "aurora_core_desktop", "error": "Фоновая подготовка AuroraFox Core завершилась неуспешно"}
		if active_model != model_absolute_path and not active_model.is_empty():
			return {"ok": false, "runtime": "aurora_core_desktop", "error": "AuroraFox Core занят подготовкой другого внутреннего профиля"}
		await get_tree().create_timer(0.25).timeout
	return {
		"ok": false,
		"runtime": "aurora_core_desktop",
		"error": "AuroraFox Core продолжает подготовку в фоне; повторите запрос через несколько секунд",
		"failure_scope": "startup",
		"model_failure": false,
		"retryable": true,
		"background_warmup_continues": true
	}

func cancel_active_requests() -> void:
	_stream_cancel_epoch += 1
	for client in _active_streams: client.close()

func stop(force := false) -> void:
	cancel_active_requests()
	# A foreground chat can time out its short join while the background loader
	# still legitimately owns the same llama-server startup. Generic recovery
	# must not kill that process and reset a slow machine back to zero. Explicit
	# teardown remains available through force=true from _exit_tree().
	if starting and not force:
		return
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
		"request_wait_policy": "confirmed_progress",
		"owner_wait_limits": CoreWaitPolicy.limits(),
		"owner_generation_tokens": {"chat": OwnerResourcePolicy.value("chat_max_tokens"), "terse": OwnerResourcePolicy.value("terse_max_tokens")},
		"context_size": DEFAULT_CONTEXT_SIZE,
		"parallel_slots": DEFAULT_PARALLEL_SLOTS,
		"threads": DEFAULT_THREADS,
		"batch_size": DEFAULT_BATCH_SIZE,
		"ubatch_size": DEFAULT_UBATCH_SIZE
	}

func _is_explicit_terse_request(messages: Array) -> bool:
	var prompt := ""
	for message in messages:
		if message is Dictionary and str(message.get("role", "")) == "system" and str(message.get("content", "")).contains("[AURORA_DIRECT_CHAT]"):
			return true
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

func _is_strict_structured_request(messages: Array) -> bool:
	var prompt := ""
	for i in range(messages.size() - 1, -1, -1):
		if messages[i] is Dictionary and str(messages[i].get("role", "")) == "user":
			prompt = str(messages[i].get("content", "")).to_lower()
			break
	return (
		prompt.contains("return strict json only")
		or prompt.contains("return one strict json object only")
		or prompt.contains("верни только строгий json")
	)

func _request_json(path: String, method: HTTPClient.Method, payload: Dictionary, timeout: float) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := req.request(BASE_URL + path, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "runtime": "aurora_core_desktop", "error": "Core Engine request: %s" % error_string(err), "failure_scope": "request", "model_failure": false, "retryable": true}
	var result: Array = await req.request_completed
	req.queue_free()
	var transport_result := int(result[0])
	var code := int(result[1])
	var raw := (result[3] as PackedByteArray).get_string_from_utf8()
	if transport_result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "runtime": "aurora_core_desktop", "http": code, "transport_result": transport_result, "error": "Core Engine request failed: transport result %d" % transport_result, "failure_scope": "request", "model_failure": false, "retryable": true}
	var parsed = null
	if not raw.strip_edges().is_empty():
		parsed = JSON.parse_string(raw)
	if code >= 200 and code < 300:
		if not parsed is Dictionary:
			var detail := "empty response" if raw.strip_edges().is_empty() else "invalid JSON response"
			return {"ok": false, "runtime": "aurora_core_desktop", "http": code, "error": "Core Engine returned %s" % detail, "raw": OwnerResourcePolicy.clip(raw, "core_http_error_chars"), "failure_scope": "request", "model_failure": false, "retryable": true}
		return {"ok": true, "http": code, "data": parsed, "raw": raw}
	return {"ok": false, "runtime": "aurora_core_desktop", "http": code, "error": OwnerResourcePolicy.clip(raw, "core_http_error_chars")}

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


func _request_progress_json(payload: Dictionary, stall_seconds: float, total_seconds: float, byte_budget: int, port: int = PORT) -> Dictionary:
	var client := HTTPClient.new()
	var stream := CoreProgressStream.new()
	stream.configure(Time.get_ticks_msec(), stall_seconds, total_seconds, byte_budget)
	var epoch := _stream_cancel_epoch
	_active_streams.append(client)
	var failure := ""
	var scope := "request"
	var response_code := 0
	var sent := false
	var headers_read := false
	var err := client.connect_to_host(HOST, port)
	if err != OK: failure = "Core connection failed: %s" % error_string(err)
	while failure.is_empty() and not stream.done:
		if epoch != _stream_cancel_epoch:
			failure = "Core request cancelled"
			scope = "cancelled"
			break
		var timeout_reason := stream.timeout_reason(Time.get_ticks_msec())
		if not timeout_reason.is_empty():
			failure = "Core request deadline: %s" % timeout_reason
			scope = timeout_reason
			break
		err = client.poll()
		if err != OK:
			failure = "Core transport failed: %s" % error_string(err)
			break
		var status := client.get_status()
		if status == HTTPClient.STATUS_CONNECTED and not sent:
			err = client.request(HTTPClient.METHOD_POST, "/v1/chat/completions", PackedStringArray(["Content-Type: application/json", "Accept: text/event-stream"]), JSON.stringify(payload))
			if err != OK: failure = "Core request failed: %s" % error_string(err)
			sent = true
		if client.has_response() and not headers_read:
			headers_read = true
			response_code = client.get_response_code()
			if response_code < 200 or response_code >= 300:
				failure = "Core HTTP error %d" % response_code
		if status == HTTPClient.STATUS_BODY and failure.is_empty():
			var bytes := client.read_response_body_chunk()
			if not bytes.is_empty(): stream.feed(bytes, Time.get_ticks_msec())
			if not stream.error.is_empty():
				failure = stream.error
				scope = "response_budget" if failure.contains("byte budget") else "protocol"
		elif sent and headers_read and status in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
			failure = "Core stream ended before a complete response"
		elif sent and status == HTTPClient.STATUS_DISCONNECTED:
			failure = "Core disconnected before a complete response"
		elif status in [HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
			failure = "Core connection failed with status %d" % status
		if failure.is_empty() and not stream.done: await get_tree().process_frame
	client.close()
	_active_streams.erase(client)
	if not failure.is_empty():
		return {"ok": false, "runtime": "aurora_core_desktop", "http": response_code, "error": failure, "failure_scope": scope, "model_failure": false, "retryable": scope == "request", "cancelled": scope == "cancelled", "prompt_tokens_processed": stream.processed, "generated_bytes": stream.generated_bytes}
	return {"ok": true, "http": response_code, "data": stream.result(), "progress": {"prompt_tokens_processed": stream.processed, "generated_bytes": stream.generated_bytes, "received_bytes": stream.received_bytes}}

func _generation_budget(options: Dictionary, terse_request: bool) -> int:
	var default_max_tokens := OwnerResourcePolicy.value("terse_max_tokens" if terse_request else "chat_max_tokens")
	var candidate = options.get("max_tokens", default_max_tokens)
	if not (candidate is int or candidate is float): return -2
	var number := float(candidate)
	if not is_finite(number) or number != floor(number) or number < -1 or number > 2147483647.0: return -2
	var requested_tokens := int(candidate)
	# llama.cpp -1 disables the token ceiling, not the real model context capacity.
	return -1 if requested_tokens <= 0 else requested_tokens
