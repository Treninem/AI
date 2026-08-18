class_name AuroraVoiceBridge
extends Node

signal backend_ready(info: Dictionary)
signal backend_lost
signal wake_detected(text: String)
signal transcript_ready(text: String)
signal barge_in
signal user_speech_started
signal user_speech_finished
signal backend_event(event: Dictionary)

const HTTP_BASE := "http://127.0.0.1:8765"
const WS_URL := "ws://127.0.0.1:8765/ws"

var socket := WebSocketPeer.new()
var backend_pid := 0
var connected := false
var _retry := 0.0
var _stopping := false
var android_runtime := AndroidLocalRuntime.new()

func _ready() -> void:
	add_child(android_runtime)
	set_process(true)
	if OS.get_name() == "Windows":
		_start_backend_if_installed()
		_connect_ws()
	elif OS.get_name() == "Android":
		await get_tree().process_frame
		backend_ready.emit({"runtime":"android-native", "capabilities":android_runtime.capabilities()})

func _exit_tree() -> void:
	_stopping = true
	if OS.get_name() == "Windows":
		var req := HTTPRequest.new()
		add_child(req)
		req.request(HTTP_BASE + "/shutdown", PackedStringArray(), HTTPClient.METHOD_POST, "")

func _process(delta: float) -> void:
	if OS.get_name() != "Windows": return
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not connected: connected = true
		while socket.get_available_packet_count() > 0:
			_handle_packet(socket.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		if connected:
			connected = false
			backend_lost.emit()
		if not _stopping:
			_retry -= delta
			if _retry <= 0.0:
				_retry = 2.0
				_connect_ws()

func _start_backend_if_installed() -> void:
	var pythonw := ProjectSettings.globalize_path("res://voice/.venv/Scripts/pythonw.exe")
	var python := ProjectSettings.globalize_path("res://voice/.venv/Scripts/python.exe")
	var server := ProjectSettings.globalize_path("res://voice/python/aurora_voice_server.py")
	if not FileAccess.file_exists(server): return
	var executable := pythonw if FileAccess.file_exists(pythonw) else python
	if not FileAccess.file_exists(executable): return
	OS.set_environment("AURORAFOX_USER_DIR", ProjectSettings.globalize_path("user://"))
	backend_pid = OS.create_process(executable, PackedStringArray([server]), false)

func _connect_ws() -> void:
	if socket.get_ready_state() in [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CONNECTING]: return
	socket = WebSocketPeer.new()
	var err := socket.connect_to_url(WS_URL)
	if err != OK: _retry = 1.0

func _handle_packet(text: String) -> void:
	var data = JSON.parse_string(text)
	if not data is Dictionary: return
	backend_event.emit(data)
	match str(data.get("event", "")):
		"backend_ready": backend_ready.emit(data)
		"wake_detected": wake_detected.emit(str(data.get("text", "")))
		"transcript": transcript_ready.emit(str(data.get("text", "")))
		"barge_in": barge_in.emit()
		"user_speech_started": user_speech_started.emit()
		"user_speech_finished": user_speech_finished.emit()

func send_command(command: String, data: Dictionary = {}) -> void:
	if OS.get_name() != "Windows" or socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return
	var payload := data.duplicate(true)
	payload["command"] = command
	socket.send_text(JSON.stringify(payload))

func set_mode(mode: String, device: Variant = null, options: Dictionary = {}) -> void:
	if OS.get_name() != "Windows": return
	var data := options.duplicate(true)
	data["mode"] = mode
	data["device"] = device
	send_command("set_mode", data)

func set_tts_state(playing: bool, spoken_text := "") -> void:
	if OS.get_name() == "Windows":
		send_command("tts_state", {"playing": playing, "text": spoken_text})

func health() -> Dictionary:
	if OS.get_name() == "Android":
		return {"ok": android_runtime.is_available(), "runtime": "android-native", "capabilities": android_runtime.capabilities()}
	return await _json_request("/health", HTTPClient.METHOD_GET, {})

func devices() -> Dictionary:
	if OS.get_name() != "Windows": return {"ok": true, "devices": []}
	return await _json_request("/devices", HTTPClient.METHOD_GET, {})

func synthesize(text: String, emotion: String, intensity: float, options: Dictionary = {}) -> Dictionary:
	if OS.get_name() == "Android":
		return android_runtime.synthesize_speech(text, float(options.get("speed", 1.0)), emotion, intensity)
	var body := options.duplicate(true)
	body.merge({"text": text, "emotion": emotion, "intensity": intensity}, true)
	return await _json_request("/say", HTTPClient.METHOD_POST, body, 240.0)

func transcribe_file(path: String) -> Dictionary:
	if OS.get_name() == "Android":
		var model := "user://models/whisper-model.bin"
		return android_runtime.transcribe(ProjectSettings.globalize_path(model), ProjectSettings.globalize_path(path), "ru")
	return await _json_request("/stt_path", HTTPClient.METHOD_POST, {"path": ProjectSettings.globalize_path(path)}, 300.0)

func get_phrase(category: String) -> String:
	if OS.get_name() == "Android": return ""
	var result := await _json_request("/phrase/" + category.uri_encode(), HTTPClient.METHOD_GET, {})
	return str(result.get("text", "")) if result.get("ok", false) else ""

func clear_cache() -> Dictionary:
	if OS.get_name() == "Android": return {"ok": true}
	return await _json_request("/cache/clear", HTTPClient.METHOD_POST, {})

func _json_request(path: String, method: HTTPClient.Method, payload: Dictionary, timeout := 30.0) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	var err := req.request(HTTP_BASE + path, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": error_string(err)}
	var result: Array = await req.request_completed
	req.queue_free()
	var code := int(result[1])
	var raw := (result[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		if code >= 200 and code < 300: return parsed
		return {"ok": false, "http": code, "error": str(parsed.get("detail", raw))}
	return {"ok": false, "http": code, "error": raw}
