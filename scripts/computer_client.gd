class_name ComputerClient
extends Node

const DEFAULT_TIMEOUT := 8.0
# /screen may perform both screenshot and UIA workers sequentially.
const SCREEN_TIMEOUT := 20.0
# Verified actions may perform screenshot -> action -> screenshot in the service.
const ACTION_TIMEOUT := 32.0
const MAX_SANDBOX_TIMEOUT := 300

static var _shared_service_token := ""
static var _computer_control_enabled := false

var base_url := "http://127.0.0.1:8766"
var backend_pid := 0
var runtime_root := ""
var _service_token := ""
var _request_sequence := 0

func _ready() -> void:
	_service_token = shared_service_token()
	if OS.get_name() == "Windows":
		_start_backend_if_installed()

func _exit_tree() -> void:
	if OS.get_name() == "Windows" and backend_pid > 0:
		OS.kill(backend_pid)
		backend_pid = 0

static func shared_service_token() -> String:
	if _shared_service_token.is_empty():
		var crypto := Crypto.new()
		_shared_service_token = crypto.generate_random_bytes(32).hex_encode()
	return _shared_service_token

static func set_computer_control_enabled(value: bool) -> void:
	_computer_control_enabled = value

static func computer_control_enabled() -> bool:
	return _computer_control_enabled

static func master_enabled_from(node: Node) -> bool:
	var current: Node = node
	for _i in range(8):
		if current == null:
			break
		for node_name in ["AutonomySettings", "AutonomySettingsManager"]:
			var manager = current.get_node_or_null(node_name)
			if manager != null and manager.has_method("get_settings"):
				var settings = manager.call("get_settings")
				if settings is Dictionary:
					return bool(settings.get("master_enabled", true))
		if current.has_method("get_settings"):
			var own_settings = current.call("get_settings")
			if own_settings is Dictionary and own_settings.has("master_enabled"):
				return bool(own_settings.get("master_enabled", true))
		current = current.get_parent()
	return true

func runtime_is_installed() -> bool:
	return OS.get_name() == "Windows" and not _find_runtime().is_empty()

func installer_path() -> String:
	if OS.get_name() != "Windows":
		return ""
	for root in _candidate_roots():
		var path := root.path_join("install_computer.ps1")
		if FileAccess.file_exists(path):
			return path
	return ""

func restart_backend() -> void:
	if OS.get_name() != "Windows":
		return
	if backend_pid > 0:
		OS.kill(backend_pid)
		backend_pid = 0
	_start_backend_if_installed()

func _start_backend_if_installed() -> void:
	if OS.get_name() != "Windows":
		return
	var found := _find_runtime()
	if found.is_empty():
		return
	runtime_root = str(found.get("root", ""))
	OS.set_environment("AURORAFOX_SANDBOX_ROOT", ProjectSettings.globalize_path("user://sandboxes"))
	OS.set_environment("AURORAFOX_COMPUTER_TOKEN", _service_token)
	OS.set_environment("AURORAFOX_PARENT_PID", str(OS.get_process_id()))
	var executable := str(found.get("pythonw", ""))
	if executable.is_empty() or not FileAccess.file_exists(executable):
		executable = str(found.get("python", ""))
	if executable.is_empty() or not FileAccess.file_exists(executable):
		_clear_bootstrap_environment()
		return
	var vendor := str(found.get("vendor", ""))
	var inject_vendor := not vendor.is_empty() and DirAccess.dir_exists_absolute(vendor)
	var had_pythonpath := OS.has_environment("PYTHONPATH")
	var previous_pythonpath := OS.get_environment("PYTHONPATH") if had_pythonpath else ""
	if inject_vendor:
		OS.set_environment("PYTHONPATH", vendor)
	backend_pid = OS.create_process(executable, PackedStringArray([str(found.get("service", ""))]), false)
	_clear_bootstrap_environment()
	if inject_vendor:
		if had_pythonpath:
			OS.set_environment("PYTHONPATH", previous_pythonpath)
		else:
			OS.unset_environment("PYTHONPATH")

func _clear_bootstrap_environment() -> void:
	OS.unset_environment("AURORAFOX_COMPUTER_TOKEN")
	OS.unset_environment("AURORAFOX_PARENT_PID")

func _find_runtime() -> Dictionary:
	for root in _candidate_roots():
		var service := root.path_join("computer_service.py")
		if not FileAccess.file_exists(service):
			continue
		var portable_pythonw := root.path_join("python/pythonw.exe")
		var portable_python := root.path_join("python/python.exe")
		if FileAccess.file_exists(portable_pythonw) or FileAccess.file_exists(portable_python):
			return {
				"root": root,
				"service": service,
				"pythonw": portable_pythonw,
				"python": portable_python,
				"vendor": root.path_join("vendor"),
				"portable": true
			}
		var pythonw := root.path_join(".venv/Scripts/pythonw.exe")
		var python := root.path_join(".venv/Scripts/python.exe")
		if FileAccess.file_exists(service) and (FileAccess.file_exists(pythonw) or FileAccess.file_exists(python)):
			return {"root": root, "service": service, "pythonw": pythonw, "python": python, "vendor": "", "portable": false}
	return {}

func _candidate_roots() -> Array[String]:
	return [
		OS.get_executable_path().get_base_dir().path_join("computer"),
		ProjectSettings.globalize_path("res://computer")
	]

func _json_request(path: String, method: HTTPClient.Method, payload: Dictionary = {}, timeout_seconds: float = DEFAULT_TIMEOUT, require_autonomy: bool = true, require_computer_permission: bool = false) -> Dictionary:
	if OS.get_name() != "Windows":
		return _unsupported()
	if require_autonomy and not _master_enabled():
		return {"ok": false, "error": "master_stop", "message": "Master stop активен", "retryable": false}
	if require_computer_permission and not computer_control_enabled():
		return {"ok": false, "error": "permission_denied", "message": "Computer control is disabled by the user", "retryable": false}
	var req := HTTPRequest.new()
	req.timeout = clampf(timeout_seconds, 1.0, 320.0)
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not _service_token.is_empty():
		headers.append("X-AuroraFox-Computer-Token: " + _service_token)
	if require_autonomy:
		headers.append("X-AuroraFox-Autonomy-Allowed: 1")
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	var err := req.request(base_url + path, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "service_unavailable", "message": "Computer service request failed (%s)" % err, "retryable": true}
	var completed: Array = await req.request_completed
	req.queue_free()
	if completed.size() < 4:
		return {"ok": false, "error": "malformed_response", "message": "Computer service returned an incomplete response", "retryable": true}
	var result_code := int(completed[0])
	var response_code := int(completed[1])
	var raw: PackedByteArray = completed[3]
	return _decode_response(result_code, response_code, raw)

func _decode_response(result_code: int, response_code: int, raw: PackedByteArray) -> Dictionary:
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "transport_failure", "message": "Computer service transport failed (%s)" % result_code, "retryable": true}
	var text := raw.get_string_from_utf8().strip_edges()
	if response_code < 200 or response_code >= 300:
		var error_code := "http_error"
		var detail := "Computer service error"
		if not text.is_empty():
			var parsed = JSON.parse_string(text)
			if parsed is Dictionary:
				var error_body: Dictionary = parsed
				error_code = str(error_body.get("error", "http_error"))
				detail = str(error_body.get("detail", error_body.get("message", detail)))
			else:
				detail = text
		return {
			"ok": false,
			"error": error_code,
			"message": detail.substr(0, 2048),
			"http": response_code,
			"retryable": response_code in [408, 429, 502, 503, 504],
		}
	if text.is_empty():
		return {"ok": false, "error": "empty_response", "message": "Computer service returned an empty response", "http": response_code, "retryable": false}
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		return {"ok": false, "error": "malformed_response", "message": "Computer service returned invalid JSON", "http": response_code, "retryable": false}
	return data

func health() -> Dictionary:
	if OS.get_name() != "Windows":
		return {
			"ok": true,
			"computer_supported": false,
			"platform": OS.get_name().to_lower(),
			"planning_owner": "aurorafox_core",
			"service_side_ai_planning": false,
			"external_ai_required": false,
			"network_required": false,
		}
	return await _json_request("/health", HTTPClient.METHOD_GET, {}, 3.0, false, false)

func capabilities() -> Dictionary:
	if OS.get_name() != "Windows":
		return _unsupported(true)
	var result := await _json_request("/capabilities", HTTPClient.METHOD_GET, {}, 4.0, false, false)
	result["computer_control_enabled"] = computer_control_enabled()
	return result

func screen() -> Dictionary:
	return await _json_request("/screen", HTTPClient.METHOD_GET, {}, SCREEN_TIMEOUT, true, true)

func windows() -> Dictionary:
	return await _json_request("/windows", HTTPClient.METHOD_GET, {}, SCREEN_TIMEOUT, true, true)

func plan(_goal: String) -> Dictionary:
	return {
		"ok": false,
		"error": "local_core_planning_required",
		"message": "Computer planning belongs to AuroraFox Core; the sidecar only executes verified primitives.",
		"retryable": false,
	}

func run(_goal: String, _max_steps: int = 30, _auto_execute: bool = false) -> Dictionary:
	return {
		"ok": false,
		"error": "local_core_planning_required",
		"message": "Use AuroraFox Core/Work to plan, then call Computer primitives explicitly.",
		"retryable": false,
	}

func action(data: Dictionary) -> Dictionary:
	if not _master_enabled():
		return {"ok": false, "error": "master_stop", "message": "Master stop активен", "retryable": false}
	if not computer_control_enabled():
		return {"ok": false, "error": "permission_denied", "message": "Computer control is disabled by the user", "retryable": false}
	var payload := data.duplicate(true)
	if str(payload.get("action_id", "")).strip_edges().is_empty():
		payload["action_id"] = _new_action_id()
	return await _json_request("/action", HTTPClient.METHOD_POST, payload, ACTION_TIMEOUT, true, true)

func sandbox_exec(command: Array[String], cwd: String = ".", timeout: int = 60, allow_network: bool = false) -> Dictionary:
	var bounded_timeout := clampi(timeout, 1, MAX_SANDBOX_TIMEOUT)
	return await _json_request("/sandbox/exec", HTTPClient.METHOD_POST, {
		"command": command,
		"cwd": cwd,
		"timeout": bounded_timeout,
		"allow_network": allow_network,
	}, float(bounded_timeout + 5), true, false)

func sandbox_container_exec(command: Array[String], cwd: String = ".", timeout: int = 60, allow_network: bool = false) -> Dictionary:
	var bounded_timeout := clampi(timeout, 1, MAX_SANDBOX_TIMEOUT)
	return await _json_request("/sandbox/container_exec", HTTPClient.METHOD_POST, {
		"command": command,
		"cwd": cwd,
		"timeout": bounded_timeout,
		"allow_network": allow_network,
	}, float(bounded_timeout + 5), true, false)

func sandbox_write(path: String, content: String) -> Dictionary:
	return await _json_request("/sandbox/write", HTTPClient.METHOD_POST, {"path": path, "content": content}, DEFAULT_TIMEOUT, true, false)

func _master_enabled() -> bool:
	return master_enabled_from(self)

func _unsupported(as_capability: bool = false) -> Dictionary:
	var result := {
		"ok": false,
		"error": "unsupported_platform",
		"message": "Desktop Computer Agent is not supported on %s" % OS.get_name(),
		"retryable": false,
		"computer_supported": false,
		"platform": OS.get_name().to_lower(),
	}
	if as_capability:
		result["ok"] = true
		result["screen"] = false
		result["windows"] = false
		result["mouse"] = false
		result["keyboard"] = false
		result["clipboard"] = false
		result["service_side_planning"] = false
		result["local_core_planning_required"] = true
		result["computer_control_enabled"] = false
	return result

func _new_service_token() -> String:
	return shared_service_token()

func _new_action_id() -> String:
	_request_sequence += 1
	var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%d:%d:%d:%s" % [OS.get_process_id(), Time.get_ticks_usec(), _request_sequence, nonce]
