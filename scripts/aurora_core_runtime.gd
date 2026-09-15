class_name AuroraCoreRuntime
extends Node

const DEFAULT_MODEL_PATH := "user://models/aurorafox-main.gguf"
const LOCAL_MODEL_DIR := "user://models"
const MAX_LOCAL_FALLBACK_MODELS := 4
const OLLAMA_TIMEOUT_SECONDS := 12.0
const OLLAMA_MIN_RETRY_SECONDS := 30.0
const OLLAMA_MAX_RETRY_SECONDS := 300.0

var model_path := DEFAULT_MODEL_PATH
var android_runtime := AndroidLocalRuntime.new()
var desktop_runtime := DesktopLocalRuntime.new()
# Ollama is never a required provider. The built-in Core remains primary even
# when the compatibility switch is enabled.
var allow_ollama_fallback := false
var ollama_base_url := "http://127.0.0.1:11434"
var ollama_model := "qwen3:8b"

var _ollama_failures := 0
var _ollama_retry_after_unix := 0.0
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

func chat(messages: Array, temperature := 0.2) -> Dictionary:
	# Local inference always gets the first chance. If the preferred GGUF is
	# unavailable or fails to load, other verified/local GGUF files are tried
	# before any external compatibility adapter.
	var local := await _chat_local(messages, temperature)
	if bool(local.get("ok", false)):
		_last_runtime = str(local.get("runtime", "aurora_core"))
		_last_model_path = str(local.get("model_path", model_path))
		_last_local_error = ""
		return local

	_last_local_error = str(local.get("error", "local runtime unavailable"))
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
	var attempted := 0
	for candidate in candidates:
		if attempted >= MAX_LOCAL_FALLBACK_MODELS:
			break
		attempted += 1
		var result := await _chat_local_model(str(candidate), messages, temperature)
		if bool(result.get("ok", false)):
			result["preferred_model"] = candidate == model_path
			result["local_failover_count"] = failures.size()
			if candidate != model_path:
				result["recovered_with_local_fallback"] = true
			return result
		failures.append({
			"model_path": candidate,
			"runtime": result.get("runtime", "aurora_core"),
			"error": str(result.get("error", "local model failed")).substr(0, 600)
		})
	return {
		"ok": false,
		"runtime": "aurora_core",
		"error": str(failures[0].get("error", "local runtime unavailable")) if not failures.is_empty() else "local runtime unavailable",
		"model_path": model_path,
		"attempted_models": failures
	}

func _chat_local_model(candidate_path: String, messages: Array, temperature: float) -> Dictionary:
	if not FileAccess.file_exists(candidate_path):
		return {"ok": false, "runtime": "aurora_core", "error": "local GGUF missing", "model_path": candidate_path}
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
	var info := {
		"runtime": "AuroraFox Core",
		"local_first": true,
		"model_path": model_path,
		"model_installed": not local_models.is_empty(),
		"available_local_models": local_models,
		"available_local_model_count": local_models.size(),
		"last_model_path": _last_model_path,
		"ollama_required": false,
		"ollama_fallback": allow_ollama_fallback,
		"ollama_circuit_open": _ollama_circuit_open(),
		"ollama_retry_after_unix": _ollama_retry_after_unix,
		"ollama_failures": _ollama_failures,
		"last_runtime": _last_runtime,
		"last_local_error": _last_local_error,
		"last_ollama_error": _last_ollama_error
	}
	if OS.get_name() == "Windows": info["desktop"] = desktop_runtime.runtime_info()
	elif OS.get_name() == "Android": info["android"] = android_runtime.capabilities()
	return info
