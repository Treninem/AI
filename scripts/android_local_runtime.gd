class_name AndroidLocalRuntime
extends Node

const SINGLETON_NAME := "AuroraFoxRuntime"
const DEFAULT_CHAT_MAX_TOKENS := 384
const TERSE_CHAT_MAX_TOKENS := 16

var _plugin: Object

func _ready() -> void:
	if Engine.has_singleton(SINGLETON_NAME):
		_plugin = Engine.get_singleton(SINGLETON_NAME)

func is_available() -> bool:
	return _plugin != null

func capabilities() -> Dictionary:
	var caps := {
		"embedded_runtime": is_available(),
		"native_processes": false,
		"container_runtime": false,
		"android_app_sandbox": true,
		"isolated_service": false,
		"llama_cpp": false,
		"whisper_cpp": false,
		"sherpa_stt": false,
		"local_tts": false,
		"wasm": false
	}
	# Android Java singletons dispatch @UsedByGodot methods dynamically. In a
	# release APK Object.has_method() can report false even though call() works.
	if _plugin != null:
		var raw := str(_plugin.call("getCapabilitiesJson"))
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			for key in parsed.keys(): caps[key] = parsed[key]
	return caps

func private_root() -> String:
	if _plugin != null:
		return str(_plugin.call("getPrivateRoot"))
	return ProjectSettings.globalize_path("user://")

func execute(workspace_root: String, command: Array, cwd: String, timeout: int, mode: String) -> Dictionary:
	if _plugin == null:
		return {"ok": false, "error": "Android native runtime plugin is not installed in this build", "hint": "File operations still work in the Android app sandbox."}
	var request := {
		"workspace": ProjectSettings.globalize_path(workspace_root),
		"command": command,
		"cwd": cwd,
		"timeout": clampi(timeout, 1, 600),
		"mode": mode
	}
	return _parse_result(_plugin.call("executeSandbox", JSON.stringify(request)), "Invalid Android runtime response")

func chat(model_path: String, messages: Array, options: Dictionary = {}) -> Dictionary:
	if _plugin == null:
		return {"ok": false, "error": "Local Android LLM runtime unavailable"}
	var request_options := options.duplicate(true)
	var terse_request := _is_explicit_terse_request(messages)
	if not request_options.has("max_tokens") and not request_options.has("num_predict"):
		request_options["max_tokens"] = TERSE_CHAT_MAX_TOKENS if terse_request else DEFAULT_CHAT_MAX_TOKENS
	request_options["terse_request"] = terse_request
	return _parse_result(_plugin.call("chatLocal", model_path, JSON.stringify(messages), JSON.stringify(request_options)), "Invalid local chat response")

func synthesize_speech(text: String, speed := 1.0, emotion := "neutral", intensity := 0.5) -> Dictionary:
	if _plugin == null:
		return {"ok": false, "error": "Local Android TTS runtime unavailable"}
	return _parse_result(
		_plugin.call("synthesizeSpeechLocal", text, float(speed), emotion, float(intensity)),
		"Invalid Android TTS response"
	)

func clear_voice_cache() -> Dictionary:
	if _plugin == null:
		return {"ok": false, "error": "Local Android voice cache API unavailable"}
	return _parse_result(_plugin.call("clearVoiceCache"), "Invalid Android cache response")

func transcribe(model_path: String, audio_path: String, language := "ru") -> Dictionary:
	if _plugin == null:
		return {"ok": false, "error": "Local Android STT runtime unavailable"}
	return _parse_result(_plugin.call("transcribeLocal", model_path, audio_path, language), "Invalid transcription response")

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

func _parse_result(raw: Variant, fallback_error: String) -> Dictionary:
	if raw is Dictionary: return raw
	if raw is String:
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary: return parsed
	return {"ok": false, "error": fallback_error}
