class_name AndroidLocalRuntime
extends Node

const SINGLETON_NAME := "AuroraFoxRuntime"

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
		"wasm": false
	}
	if _plugin != null and _plugin.has_method("getCapabilities"):
		var raw = _plugin.call("getCapabilities")
		if raw is Dictionary:
			for key in raw.keys(): caps[key] = raw[key]
	return caps

func private_root() -> String:
	if _plugin != null and _plugin.has_method("getPrivateRoot"):
		return str(_plugin.call("getPrivateRoot"))
	return ProjectSettings.globalize_path("user://")

func execute(workspace_root: String, command: Array, cwd: String, timeout: int, mode: String) -> Dictionary:
	if _plugin == null:
		return {
			"ok": false,
			"error": "Android native runtime plugin is not installed in this build",
			"hint": "Build and enable AuroraFoxRuntime Android plugin. File operations still work in the app sandbox."
		}
	if not _plugin.has_method("executeSandbox"):
		return {"ok": false, "error": "Android runtime does not expose executeSandbox"}
	var request := {
		"workspace": ProjectSettings.globalize_path(workspace_root),
		"command": command,
		"cwd": cwd,
		"timeout": clampi(timeout, 1, 600),
		"mode": mode
	}
	var raw = _plugin.call("executeSandbox", JSON.stringify(request))
	if raw is Dictionary: return raw
	if raw is String:
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary: return parsed
	return {"ok": false, "error": "Invalid Android runtime response"}

func chat(model_path: String, messages: Array, options: Dictionary = {}) -> Dictionary:
	if _plugin == null or not _plugin.has_method("chatLocal"):
		return {"ok": false, "error": "Local Android LLM runtime unavailable"}
	var raw = _plugin.call("chatLocal", model_path, JSON.stringify(messages), JSON.stringify(options))
	if raw is Dictionary: return raw
	if raw is String:
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary: return parsed
	return {"ok": false, "error": "Invalid local chat response"}

func transcribe(model_path: String, audio_path: String, language := "ru") -> Dictionary:
	if _plugin == null or not _plugin.has_method("transcribeLocal"):
		return {"ok": false, "error": "Local Android Whisper runtime unavailable"}
	var raw = _plugin.call("transcribeLocal", model_path, audio_path, language)
	if raw is Dictionary: return raw
	if raw is String:
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary: return parsed
	return {"ok": false, "error": "Invalid transcription response"}
