class_name VoiceClient
extends Node

const BASE_URL := "http://127.0.0.1:8765"
const DEFAULT_SPEAKER := "xenia"

var service_pid: int = 0
var auto_speak := true
var speaker := DEFAULT_SPEAKER

func _ready() -> void:
	_start_service_if_installed()

func _start_service_if_installed() -> void:
	if OS.get_name() != "Windows":
		return
	var python := ProjectSettings.globalize_path("res://voice/.venv/Scripts/python.exe")
	var service := ProjectSettings.globalize_path("res://voice/voice_service.py")
	if not FileAccess.file_exists(python) or not FileAccess.file_exists(service):
		return
	service_pid = OS.create_process(python, PackedStringArray([service]), false)

func is_available() -> bool:
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(BASE_URL + "/health")
	if err != OK:
		http.queue_free()
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	return int(result[1]) == 200

func speak(text: String) -> Dictionary:
	var clean := text.strip_edges()
	if clean.is_empty():
		return {"ok": false, "error": "empty text"}
	var http := HTTPRequest.new()
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify({
		"text": clean,
		"speaker": speaker,
		"sample_rate": 48000
	})
	var err := http.request(BASE_URL + "/tts", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": error_string(err)}
	var result: Array = await http.request_completed
	http.queue_free()
	var code := int(result[1])
	var bytes: PackedByteArray = result[3]
	if code != 200:
		return {"ok": false, "error": bytes.get_string_from_utf8()}
	var path := "user://aurorafox_reply.wav"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot write voice output"}
	file.store_buffer(bytes)
	file.close()
	return {"ok": true, "path": path}

func transcribe(audio_path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(audio_path)
	var http := HTTPRequest.new()
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify({"path": absolute})
	var err := http.request(BASE_URL + "/stt_path", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": error_string(err)}
	var result: Array = await http.request_completed
	http.queue_free()
	var code := int(result[1])
	var raw: PackedByteArray = result[3]
	if code != 200:
		return {"ok": false, "error": raw.get_string_from_utf8()}
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid STT response"}
	return {"ok": true, "text": str(parsed.get("text", ""))}

func play_wav(path: String, parent: Node) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var stream := AudioStreamWAV.load_from_file(absolute)
	if stream == null:
		return false
	var player := AudioStreamPlayer.new()
	parent.add_child(player)
	player.stream = stream
	player.finished.connect(player.queue_free)
	player.play()
	return true
