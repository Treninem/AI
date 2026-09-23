class_name AuroraCoreRuntime
extends Node

const DEFAULT_MODEL_PATH := "user://models/aurorafox-main.gguf"
const LOCAL_MODEL_DIR := "user://models"
const MAX_LOCAL_FALLBACK_MODELS := 4
const MODEL_MIN_RETRY_SECONDS := 20.0
const MODEL_MAX_RETRY_SECONDS := 300.0
const OLLAMA_TIMEOUT_SECONDS := 12.0
const OLLAMA_MIN_RETRY_SECONDS := 30.0
const OLLAMA_MAX_RETRY_SECONDS := 300.0

var model_path := DEFAULT_MODEL_PATH
var android_runtime := AndroidLocalRuntime.new()
var desktop_runtime := DesktopLocalRuntime.new()
# Legacy Ollama is an optional compatibility adapter only. AuroraFox-owned
# inference is exposed separately through chat_local_only() and remains the
# normal intelligence path regardless of this switch.
var allow_ollama_fallback := false
var ollama_base_url := "http://127.0.0.1:11434"
var ollama_model := "qwen3:8b"

var _ollama_failures := 0
var _ollama_retry_after_unix := 0.0
var _model_failures: Dictionary = {}
var _last_runtime := ""
var _last_local_error := ""
var _last_ollama_error := ""
var _last_model_path := ""

func _ready() -> void:
	if android_runtime.get_parent() == null: add_child(android_runtime)
	if desktop_runtime.get_parent() == null: add_child(desktop_runtime)

func configure_model(path: String) -> void:
	if not path.strip_edges().is_empty(): model_path = path

func configure_legacy_ollama(url: String, model_name: String) -> void:
	ollama_base_url = url.trim_suffix("/")
	if not model_name.strip_edges().is_empty(): ollama_model = model_name.strip_edges()

func set_ollama_fallback_enabled(enabled: bool) -> void:
	allow_ollama_fallback = enabled
	if not enabled:
		_reset_ollama_circuit()

# Official AuroraFox-owned inference API. It never calls Ollama or any other
# external AI provider, even when a compatibility adapter is enabled.
func chat_local_only(messages: Array, temperature := 0.2) -> Dictionary:
	var local := await _chat_local(messages, temperature)
	if bool(local.get("ok", false)):
		_last_runtime = str(local.get("runtime", "aurora_core"))
		_last_model_path = str(local.get("model_path", model_path))
		_last_local_error = ""
	else:
		_last_local_error = str(local.get("error", "local runtime unavailable"))
	return local

# Explicit compatibility-capable API. Normal AIClient.chat(), AgentCore and
# self-improvement do not use this method. It exists only for callers that
# deliberately request the legacy compatibility behavior.
func chat(messages: Array, temperature := 0.2) -> Dictionary:
	var local := await chat_local_only(messages, temperature)
	if bool(local.get("ok", false)):
		return local

	if allow_ollama_fallback and OS.get_name() != "Android" and not _ollama_circuit_open():
		var legacy := await _chat_ollama(messages, temperature)
		if bool(legacy.get("ok", false)):
			_reset_ollama_circuit()
			_last_runtime = "ollama_legacy"
			legacy["fallback_from"] = local.get("runtime", "aurora_core")
			legacy["local_error_hidden"] = _last_local_error
			return legacy
		_record_ollama_failure(str(legacy.get("error", "compatibility adapter unavailable")))
		# Do not replace the useful local diagnostic with an Ollama/network error.
		local["compatibility_adapter"] = {
			"enabled": true,
			"available": false,
			"ignored": true,
			"retry_after_unix": _ollama_retry_after_unix
		}
	elif allow_ollama_fallback and _ollama_circuit_open():
		local["compatibility_adapter"] = {
			"enabled": true,
			"available": false,
			"ignored": true,
			"circuit_open": true,
			"retry_after_unix": _ollama_retry_after_unix
		}
	return local

func _chat_local(messages: Array, temperature: float) -> Dictionary:
	var candidates := _available_model_paths()
	if candidates.is_empty():
		return {
			"ok": false,
			"runtime": "aurora_core",
			"error": "Локальная модель AuroraFox не установлена",
			"model_path": model_path,
			"attempted_models": []
		}
	var failures: Array = []
	var skipped: Array = []
	var attempted := 0
	for candidate_value in candidates:
		var candidate := str(candidate_value)
		if attempted >= MAX_LOCAL_FALLBACK_MODELS:
			break
		if _model_circuit_open(candidate):
			skipped.append(_model_failure_summary(candidate))
			continue
		attempted += 1
		var result := await _chat_local_model(candidate, messages, temperature)
		if bool(result.get("ok", false)):
			_reset_model_failure(candidate)
			result["preferred_model"] = candidate == model_path
			result["local_failover_count"] = failures.size()
			result["skipped_quarantined_models"] = skipped
			if candidate != model_path:
				result["recovered_with_local_fallback"] = true
			return result
		var error := str(result.get("error", "local model failed"))
		var model_failure := bool(result.get("model_failure", true))
		if model_failure:
			_record_model_failure(candidate, error)
		failures.append({
			"model_path": candidate,
			"runtime": result.get("runtime", "aurora_core"),
			"error": error.substr(0, 600),
			"failure_scope": result.get("failure_scope", "model" if model_failure else "request"),
			"model_failure": model_failure,
			"retryable": result.get("retryable", false),
			"health": _model_failure_summary(candidate)
		})
	var first_error := "local runtime unavailable"
	if not failures.is_empty():
		first_error = str(failures[0].get("error", first_error))
	elif not skipped.is_empty():
		first_error = "Локальные модели временно исключены после ошибок загрузки; AuroraFox повторит их автоматически"
	return {
		"ok": false,
		"runtime": "aurora_core",
		"error": first_error,
		"model_path": model_path,
		"attempted_models": failures,
		"skipped_quarantined_models": skipped
	}

func _chat_local_model(candidate_path: String, messages: Array, temperature: float) -> Dictionary:
	if not FileAccess.file_exists(candidate_path):
		return {"ok": false, "runtime": "aurora_core", "error": "local GGUF missing", "model_path": candidate_path}
	if not _looks_like_gguf(candidate_path):
		return {"ok": false, "runtime": "aurora_core", "error": "local GGUF header/size validation failed", "model_path": candidate_path}
	if OS.get_name() == "Android":
		if not android_runtime.is_available(): return {"ok": false, "runtime": "aurora_core", "error": "Встроенное ядро AuroraFox недоступно в этой Android-сборке", "model_path": candidate_path}
		var caps := android_runtime.capabilities()
		if not bool(caps.get("llama_cpp", false)): return {"ok": false, "runtime": "aurora_core", "error": "Встроенный inference runtime не включен", "capabilities": caps, "model_path": candidate_path}
		var result := android_runtime.chat(ProjectSettings.globalize_path(candidate_path), messages, {"temperature": temperature})
		result["runtime"] = "aurora_core_android"
		result["model_path"] = candidate_path
		return result
	if OS.get_name() == "Windows":
		if Engine.has_singleton("AuroraFoxRuntime"):
			var plugin := Engine.get_singleton("AuroraFoxRuntime")
			if plugin != null and plugin.has_method("chatLocal"):
				var raw = plugin.call("chatLocal", ProjectSettings.globalize_path(candidate_path), JSON.stringify(messages), JSON.stringify({"temperature": temperature}))
				var parsed = JSON.parse_string(str(raw)) if raw is String else raw
				if parsed is Dictionary and bool(parsed.get("ok", false)):
					parsed["runtime"] = "aurora_core_native"
					parsed["model_path"] = candidate_path
					return parsed
		return await desktop_runtime.chat(candidate_path, messages, {"temperature": temperature})
	return {"ok": false, "runtime": "aurora_core", "error": "Локальный Core backend пока не подключён на этой платформе", "platform": OS.get_name(), "model_path": candidate_path}

func _available_model_paths() -> Array[String]:
	var out: Array[String] = []
	if FileAccess.file_exists(model_path):
		out.append(model_path)
	# Keep the verified package Core in the same failover set even when a stale
	# user:// override was selected by an older AuroraFox installation.
	if OS.get_name() == "Windows":
		var packaged := AuroraBundledCoreModel.windows_packaged_path()
		if packaged != model_path and _looks_like_gguf(packaged):
			out.append(packaged)
	var absolute_dir := ProjectSettings.globalize_path(LOCAL_MODEL_DIR)
	if not DirAccess.dir_exists_absolute(absolute_dir):
		return out
	var dir := DirAccess.open(absolute_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if dir.current_is_dir():
			continue
		var lower := name.to_lower()
		if not lower.ends_with(".gguf"):
			continue
		if lower.ends_with(".download.gguf") or lower.ends_with(".import.gguf"):
			continue
		var candidate := LOCAL_MODEL_DIR.path_join(name)
		if candidate != model_path and candidate not in out and _looks_like_gguf(candidate):
			out.append(candidate)
	dir.list_dir_end()
	return out

func _looks_like_gguf(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	if file.get_length() < 1024 * 1024:
		file.close()
		return false
	var magic := file.get_buffer(4).get_string_from_ascii()
	file.close()
	return magic == "GGUF"

func _record_model_failure(path: String, message: String) -> void:
	var identity := _model_identity(path)
	var previous: Dictionary = _model_failures.get(path, {}) if _model_failures.get(path, {}) is Dictionary else {}
	var same_identity := not previous.is_empty() and int(previous.get("size", -1)) == int(identity.get("size", -2)) and int(previous.get("modified", -1)) == int(identity.get("modified", -2))
	var failures := int(previous.get("failures", 0)) + 1 if same_identity else 1
	var exponent := float(mini(maxi(failures - 1, 0), 4))
	var delay := minf(MODEL_MAX_RETRY_SECONDS, MODEL_MIN_RETRY_SECONDS * pow(2.0, exponent))
	_model_failures[path] = {
		"failures": failures,
		"retry_after_unix": Time.get_unix_time_from_system() + delay,
		"size": int(identity.get("size", -1)),
		"modified": int(identity.get("modified", -1)),
		"last_error": message.substr(0, 600),
		"last_failure_at": Time.get_datetime_string_from_system(true)
	}

func _reset_model_failure(path: String) -> void:
	_model_failures.erase(path)

func retry_local_now() -> void:
	# One user-request retry may clear transient startup quarantine and restart
	# the owned Windows backend. Integrity checks and candidate bounds remain in
	# force when the request is attempted again.
	_model_failures.clear()
	_last_local_error = ""
	if OS.get_name() == "Windows":
		desktop_runtime.stop()

func _model_circuit_open(path: String) -> bool:
	if not _model_failures.has(path):
		return false
	var entry: Dictionary = _model_failures.get(path, {})
	var identity := _model_identity(path)
	if int(entry.get("size", -1)) != int(identity.get("size", -2)) or int(entry.get("modified", -1)) != int(identity.get("modified", -2)):
		_model_failures.erase(path)
		return false
	return float(entry.get("retry_after_unix", 0.0)) > Time.get_unix_time_from_system()

func _model_identity(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"size": -1, "modified": -1}
	var size := file.get_length()
	file.close()
	return {"size": size, "modified": int(FileAccess.get_modified_time(path))}

func _model_failure_summary(path: String) -> Dictionary:
	if not _model_failures.has(path):
		return {"model_path": path, "quarantined": false}
	var entry: Dictionary = _model_failures.get(path, {})
	return {
		"model_path": path,
		"quarantined": _model_circuit_open(path),
		"failures": int(entry.get("failures", 0)),
		"retry_after_unix": float(entry.get("retry_after_unix", 0.0)),
		"last_error": str(entry.get("last_error", "")),
		"size": int(entry.get("size", -1)),
		"modified": int(entry.get("modified", -1))
	}

func _model_health_snapshot(paths: Array[String]) -> Array:
	var out: Array = []
	for path in paths:
		out.append(_model_failure_summary(path))
	return out

func _chat_ollama(messages: Array, temperature: float) -> Dictionary:
	var request_node := HTTPRequest.new()
	request_node.timeout = OLLAMA_TIMEOUT_SECONDS
	add_child(request_node)
	var payload := {"model": ollama_model, "messages": messages, "stream": false, "options": {"temperature": temperature}}
	var err := request_node.request(ollama_base_url + "/api/chat", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		request_node.queue_free()
		return {"ok": false, "runtime": "ollama_legacy", "error": "compatibility adapter request unavailable"}
	var result: Array = await request_node.request_completed
	request_node.queue_free()
	if int(result[1]) < 200 or int(result[1]) >= 300:
		return {"ok": false, "runtime": "ollama_legacy", "error": "compatibility adapter HTTP %d" % int(result[1])}
	var data = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if not data is Dictionary:
		return {"ok": false, "runtime": "ollama_legacy", "error": "invalid compatibility adapter response"}
	return {"ok": true, "content": str((data.get("message", {}) as Dictionary).get("content", "")), "raw": data, "runtime": "ollama_legacy", "model": ollama_model}

func _record_ollama_failure(message: String) -> void:
	_ollama_failures += 1
	_last_ollama_error = message
	var exponent := float(mini(maxi(_ollama_failures - 1, 0), 4))
	var delay := minf(OLLAMA_MAX_RETRY_SECONDS, OLLAMA_MIN_RETRY_SECONDS * pow(2.0, exponent))
	_ollama_retry_after_unix = Time.get_unix_time_from_system() + delay

func _reset_ollama_circuit() -> void:
	_ollama_failures = 0
	_ollama_retry_after_unix = 0.0
	_last_ollama_error = ""

func _ollama_circuit_open() -> bool:
	return _ollama_retry_after_unix > Time.get_unix_time_from_system()

func core_engine_installer() -> String:
	return desktop_runtime.installer_path() if OS.get_name() == "Windows" else ""

func runtime_info() -> Dictionary:
	var local_models := _available_model_paths()
	var health := _model_health_snapshot(local_models)
	var quarantined := 0
	for row in health:
		if row is Dictionary and bool(row.get("quarantined", false)):
			quarantined += 1
	var info := {
		"runtime": "AuroraFox Core",
		"local_first": true,
		"self_primary": true,
		"model_path": model_path,
		"model_installed": not local_models.is_empty(),
		"available_local_models": local_models,
		"available_local_model_count": local_models.size(),
		"model_health": health,
		"quarantined_local_model_count": quarantined,
		"last_model_path": _last_model_path,
		"ollama_required": false,
		"external_ai_required": false,
		"ollama_fallback_enabled": allow_ollama_fallback,
		"ollama_failures": _ollama_failures,
		"ollama_circuit_open": _ollama_circuit_open(),
		"ollama_retry_after_unix": _ollama_retry_after_unix,
		"last_runtime": _last_runtime,
		"last_local_error": _last_local_error,
		"last_ollama_error": _last_ollama_error,
		"android": android_runtime.capabilities(),
		"desktop": desktop_runtime.runtime_info()
	}
	return info
