class_name AuroraVoiceLogger
extends Node

const LOG_DIR := "user://logs"
const LOG_PATH := "user://logs/aurora_voice.log"
const MAX_BYTES := 5 * 1024 * 1024

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	_rotate_if_needed()
	await get_tree().process_frame
	AuroraVoice.backend_status.connect(_on_backend_status)
	AuroraVoice.bridge.backend_event.connect(_on_backend_event)
	AuroraVoice.speech_queue.speech_error.connect(func(message): write("TTS_ERROR", message))
	AuroraVoice.wake_word_detected.connect(func(): write("WAKE", "Fox/Лиса detected"))
	write("CLIENT_START", "platform=" + OS.get_name())

func _exit_tree() -> void:
	write("CLIENT_STOP", "platform=" + OS.get_name())

func write(kind: String, message: String) -> void:
	# Do not log raw recognized speech, microphone buffers, TTS text or credentials.
	var clean := _redact(message).replace("\r", " ").replace("\n", " ").substr(0, 1200)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null: return
	f.seek_end()
	f.store_line("%s [%s] %s" % [Time.get_datetime_string_from_system(true), kind, clean])
	f.close()
	_rotate_if_needed()

func _on_backend_status(ready: bool, info: Dictionary) -> void:
	if ready:
		write("BACKEND_READY", "runtime=%s" % str(info.get("runtime", info.get("backend", "local"))))
	else:
		write("BACKEND_LOST", "local voice backend disconnected")

func _on_backend_event(event: Dictionary) -> void:
	var kind := str(event.get("event", ""))
	if kind in ["transcript", "wake_detected"]:
		return
	if kind in ["microphone_error", "stt_error", "backend_error", "fallback"]:
		write(kind.to_upper(), str(event.get("message", event.get("error", ""))))

func _rotate_if_needed() -> void:
	var f := FileAccess.open(LOG_PATH, FileAccess.READ)
	if f == null or f.get_length() <= MAX_BYTES: return
	f.close()
	var old := ProjectSettings.globalize_path(LOG_PATH + ".1")
	if FileAccess.file_exists(LOG_PATH + ".1"): DirAccess.remove_absolute(old)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(LOG_PATH), old)

func _redact(text: String) -> String:
	var lower := text.to_lower()
	if lower.contains("token=") or lower.contains("password=") or lower.contains("authorization:"):
		return "[sensitive diagnostic redacted]"
	return text
