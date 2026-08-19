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
var android_mic: AuroraAndroidMicMonitor

func _ready() -> void:
	add_child(android_runtime)
	set_process(true)
	if OS.get_name() == "Windows":
		_start_backend_if_installed()
		_connect_ws()
	elif OS.get_name() == "Android":
		android_mic = AuroraAndroidMicMonitor.new()
		add_child(android_mic)
		android_mic.wake_detected.connect(func(text):
			wake_detected.emit(str(text))
			backend_event.emit({"event":"wake_detected", "text":str(text), "runtime":"android-native"})
		)
		android_mic.transcript_ready.connect(func(text): transcript_ready.emit(str(text)))
		android_mic.barge_in.connect(func(text):
			barge_in.emit()
			transcript_ready.emit(str(text))
		)
		android_mic.user_speech_started.connect(func(): user_speech_started.emit())
		android_mic.user_speech_finished.connect(func(): user_speech_finished.emit())
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
	OS.set_environment("AURORAFOX_USER_DIR", ProjectSettings.globalize_path("user://"))
	var exe_dir := OS.get_executable_path().get_base_dir()
	var packaged_root := exe_dir.path_join("voice")
	var source_root := ProjectSettings.globalize_path("res://voice")
	var roots: Array[String] = [packaged_root, source_root]

	# XTTS is installed into AuroraFox's managed Python environment on demand.
	# If it is enabled, use that environment first instead of the lightweight
	# PyInstaller backend which intentionally contains only the base voice stack.
	for root in roots:
		if _xtts_enabled(root) and _start_python_backend(root):
			return

	# Default release path: portable base voice backend, no system Python needed.
	_configure_runtime_environment(packaged_root)
	var portable := packaged_root.path_join("AuroraVoiceBackend/AuroraVoiceBackend.exe")
	if FileAccess.file_exists(portable):
		backend_pid = OS.create_process(portable, PackedStringArray(), false)
		if backend_pid > 0: return

	# Development / emergency / advanced-voice fallback: managed Python 3.11.
	for root in roots:
		if _start_python_backend(root):
			return

func _start_python_backend(root: String) -> bool:
	var server := root.path_join("python/aurora_voice_server.py")
	if not FileAccess.file_exists(server): return false
	var pythonw := root.path_join(".venv/Scripts/pythonw.exe")
	var python := root.path_join(".venv/Scripts/python.exe")
	var executable := pythonw if FileAccess.file_exists(pythonw) else python
	if not FileAccess.file_exists(executable): return false
	_configure_runtime_environment(root)
	backend_pid = OS.create_process(executable, PackedStringArray([server]), false)
	return backend_pid > 0

func _xtts_enabled(root: String) -> bool:
	var config_path := root.path_join("config/voice_config.json")
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null: return false
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary: return false
	var xtts = data.get("xtts", {})
	return xtts is Dictionary and bool(xtts.get("enabled", false))

func _configure_runtime_environment(runtime_root: String) -> void:
	_configure_model_cache(runtime_root)
	var ffmpeg_bin := runtime_root.path_join("runtime/ffmpeg/bin")
	if FileAccess.file_exists(ffmpeg_bin.path_join("ffmpeg.exe")):
		OS.set_environment("AURORAFOX_FFMPEG_BIN", ffmpeg_bin)
	var cpml_marker := runtime_root.path_join("runtime/xtts_cpml_accepted.txt")
	if FileAccess.file_exists(cpml_marker):
		OS.set_environment("COQUI_TOS_AGREED", "1")

func _configure_model_cache(runtime_root: String) -> void:
	OS.set_environment("HF_HOME", runtime_root.path_join("models/cache/huggingface"))
	OS.set_environment("HUGGINGFACE_HUB_CACHE", runtime_root.path_join("models/cache/huggingface/hub"))
	OS.set_environment("TORCH_HOME", runtime_root.path_join("models/cache/torch"))

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
	if OS.get_name() == "Android":
		if android_mic != null:
			android_mic.set_mode(mode, float(options.get("sensitivity", 0.5)), bool(options.get("noise_suppression", true)))
		return
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
		return android_runtime.transcribe("", ProjectSettings.globalize_path(path), "ru")
	return await _json_request("/stt_path", HTTPClient.METHOD_POST, {"path": ProjectSettings.globalize_path(path)}, 300.0)

func get_phrase(category: String) -> String:
	if OS.get_name() == "Android": return ""
	var result := await _json_request("/phrase/" + category.uri_encode(), HTTPClient.METHOD_GET, {})
	return str(result.get("text", "")) if result.get("ok", false) else ""

func clear_cache() -> Dictionary:
	if OS.get_name() == "Android": return android_runtime.clear_voice_cache()
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
