class_name AuroraApiGatewayManager
extends Node

signal status_changed(online: bool, details: Dictionary)
signal key_created(api_key: String, key_info: Dictionary)
signal gateway_error(message: String)

const SETTINGS_PATH := "user://api_gateway.json"

@export var enabled := true
@export_range(1024, 65535, 1) var port := 8768
@export var host := "127.0.0.1"
@export_range(2.0, 60.0, 1.0) var poll_seconds := 5.0

var online := false
var last_status: Dictionary = {}
var _timer: Timer
var _start_cooldown_until := 0.0

func _ready() -> void:
	if OS.get_name() == "Android":
		return
	_load_settings()
	_timer = Timer.new()
	_timer.wait_time = poll_seconds
	_timer.one_shot = false
	_timer.timeout.connect(_poll)
	add_child(_timer)
	_timer.start()
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	await _poll()
	if enabled and not online:
		start_gateway()

func set_enabled(value: bool) -> void:
	enabled = value
	_save_settings()
	if enabled:
		start_gateway()

func set_port(value: int) -> void:
	port = clampi(value, 1024, 65535)
	_save_settings()

func start_gateway() -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Automatic API startup is currently packaged for Windows"}
	if Time.get_unix_time_from_system() < _start_cooldown_until:
		return {"ok": false, "error": "API startup cooldown"}
	var script := _api_root().path_join("start_api.ps1")
	if not FileAccess.file_exists(script):
		var error := "AuroraFox API start script not found: " + script
		gateway_error.emit(error)
		return {"ok": false, "error": error}
	_start_cooldown_until = Time.get_unix_time_from_system() + 20.0
	var args := PackedStringArray([
		"-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass",
		"-File", script,
		"-HostAddress", host,
		"-Port", str(port)
	])
	var pid := OS.create_process("powershell.exe", args, false)
	if pid <= 0:
		var error := "Failed to start AuroraFox API PowerShell bootstrap"
		gateway_error.emit(error)
		return {"ok": false, "error": error}
	return {"ok": true, "pid": pid, "url": base_url()}

func base_url() -> String:
	return "http://%s:%d" % [host, port]

func _poll() -> void:
	if OS.get_name() == "Android":
		return
	var request := HTTPRequest.new()
	request.timeout = 2.5
	add_child(request)
	var err := request.request(base_url() + "/health")
	if err != OK:
		request.queue_free()
		_set_online(false, {"ok": false, "error": error_string(err)})
		if enabled and Time.get_unix_time_from_system() >= _start_cooldown_until:
			start_gateway()
		return
	var result: Array = await request.request_completed
	request.queue_free()
	var code := int(result[1])
	var raw: PackedByteArray = result[3]
	var text := raw.get_string_from_utf8().strip_edges()
	if code == 200 and not text.is_empty():
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			_set_online(bool(parsed.get("ok", false)), parsed)
			return
	_set_online(false, {"ok": false, "http": code, "error": "Empty or invalid health response"})
	if enabled and Time.get_unix_time_from_system() >= _start_cooldown_until:
		start_gateway()

func _set_online(value: bool, details: Dictionary) -> void:
	var changed := value != online or JSON.stringify(details) != JSON.stringify(last_status)
	online = value
	last_status = details.duplicate(true)
	if changed:
		status_changed.emit(online, last_status)

func create_key(name: String, scopes: Array[String] = []) -> Dictionary:
	var chosen: Array[String] = scopes
	if chosen.is_empty():
		chosen = ["chat", "models.read", "conversations.read", "files", "tools.read", "feedback", "memory.read", "memory.write"]
	var result := _run_keyctl(["create", name, "--scopes", ",".join(chosen)])
	if result.get("ok", false):
		var data: Dictionary = result.get("data", {})
		var token := str(data.get("api_key", ""))
		var info: Dictionary = data.get("key", {})
		if not token.is_empty():
			key_created.emit(token, info)
	return result

func list_keys() -> Dictionary:
	return _run_keyctl(["list"])

func revoke_key(key_id: String) -> Dictionary:
	return _run_keyctl(["revoke", key_id])

func bootstrap_key_path() -> String:
	var profile := OS.get_environment("USERPROFILE")
	if profile.is_empty():
		return ""
	return profile.path_join(".aurorafox").path_join("api").path_join("bootstrap_key.txt")

func _run_keyctl(args: Array[String]) -> Dictionary:
	var python := _api_root().path_join(".venv").path_join("Scripts").path_join("python.exe")
	if not FileAccess.file_exists(python):
		return {"ok": false, "error": "API runtime is not installed yet"}
	var argv := PackedStringArray(["-m", "api.keyctl"])
	argv.append_array(PackedStringArray(args))
	var output: Array = []
	var code := OS.execute(python, argv, output, true, false)
	var text := "\n".join(output).strip_edges()
	if code != 0:
		return {"ok": false, "code": code, "error": text}
	if text.is_empty():
		return {"ok": false, "code": code, "error": "API key command returned an empty response"}
	var parsed = JSON.parse_string(text)
	return {"ok": parsed is Dictionary, "code": code, "data": parsed if parsed is Dictionary else {}, "raw": text}

func _api_root() -> String:
	var packaged := OS.get_executable_path().get_base_dir().path_join("api")
	if FileAccess.file_exists(packaged.path_join("app.py")):
		return packaged
	return ProjectSettings.globalize_path("res://api")

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		return
	enabled = bool(data.get("enabled", enabled))
	port = clampi(int(data.get("port", port)), 1024, 65535)
	host = "127.0.0.1"

func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"enabled": enabled, "host": "127.0.0.1", "port": port}, "\t"))
	file.close()

