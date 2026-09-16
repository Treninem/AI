class_name ComputerClient
extends Node

const DEFAULT_TIMEOUT := 8.0
const SCREEN_TIMEOUT := 14.0
const ACTION_TIMEOUT := 14.0
const MAX_SANDBOX_TIMEOUT := 300

var base_url := "http://127.0.0.1:8766"
var backend_pid := 0
var runtime_root := ""
var _service_token := ""
var _request_sequence := 0

func _ready() -> void:
	_service_token = _new_service_token()
	if OS.get_name() == "Windows":
		_start_backend_if_installed()

func _exit_tree() -> void:
	if OS.get_name() == "Windows" and backend_pid > 0:
		OS.kill(backend_pid)
		backend_pid = 0

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
	backend_pid = OS.create_process(executable, PackedStringArray([str(found.get("service", ""))]), false)
	_clear_bootstrap_environment()

func _clear_bootstrap_environment() -> void:
	OS.unset_environment("AURORAFOX_COMPUTER_TOKEN")
	OS.unset_environment("AURORAFOX_PARENT_PID")

func _find_runtime() -> Dictionary:
	for root in _candidate_roots():
		var service := root.path_join("computer_service.py")
		var pythonw := root.path_join(".venv/Scripts/pythonw.exe")
		var python := root.path_join(".venv/Scripts/python.exe")
		if FileAccess.file_exists(service) and (FileAccess.file_exists(pythonw) or FileAccess.file_exists(python)):
			return {"root": root, "service": service, "pythonw": pythonw, "python": python}
	return {}

func _candidate_roots() -> Array[String]:
	return [
		OS.get_executable_path().get_base_dir().path_join("computer"),
		ProjectSettings.globalize_path("res://computer")
	]

func _json_request(path: String, method: HTTPClient.Method, payload: Dictionary = {}, timeout_seconds: float = DEFAULT_TIMEOUT, require_autonomy: bool = true) -> Dictionary:
	if OS.get_name() != "Windows":
		return _unsupported()
	if require_autonomy and not _master_enabled():
		return {"ok": false, "error": "master_stop", "message": "Master stop активен", "retryable": false}
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
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "transport_failure", "message": "Computer service transport failed (%s)" % result_code, "retryable": true}
	var text := raw.get_string_from_utf8().strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "empty_response", "message": "Computer service returned an empty response", "http": response_code, "retryable": response_code >= 500}
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		return {"ok": false, "error": "malformed_response", "message": "Computer service returned invalid JSON", "http": response_code, "retryable": response_code >= 500}
	var response: Dictionary = data
	if response_code < 200 or response_code >= 300:
		var detail = response.get("detail", response.get("message", "Computer service error"))
		return {
			"ok": false,
			"error": str(response.get("error", "http_error")),
			"message": str(detail).substr(0, 2048),
			"http": response_code,
			"retryable": response_code in [408, 429, 502, 503, 504],
		}
	return response

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
	return await _json_request("/health", HTTPClient.METHOD_GET, {}, 3.0, false)

func capabilities() -> Dictionary:
	if OS.get_name() != "Windows":
		return _unsupported(true)
	return await _json_request("/capabilities", HTTPClient.METHOD_GET, {}, 4.0, false)

func screen() -> Dictionary:
	return await _json_request("/screen", HTTPClient.METHOD_GET, {}, SCREEN_TIMEOUT, true)

func windows() -> Dictionary:
	return await _json_request("/windows", HTTPClient.METHOD_GET, {}, SCREEN_TIMEOUT, true)

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
	var payload := data.duplicate(true)
	if str(payload.get("action_id", "")).strip_edges().is_empty():
		payload["action_id"] = _new_action_id()
	return await _json_request("/action", HTTPClient.METHOD_POST, payload, ACTION_TIMEOUT, true)

func sandbox_exec(command: Array[String], cwd: String = ".", timeout: int = 60, allow_network: bool = false) -> Dictionary:
	var bounded_timeout := clampi(timeout, 1, MAX_SANDBOX_TIMEOUT)
	return await _json_request("/sandbox/exec", HTTPClient.METHOD_POST, {
		"command": command,
		"cwd": cwd,
		"timeout": bounded_timeout,
		"allow_network": allow_network,
	}, float(bounded_timeout + 5), true)

func sandbox_container_exec(command: Array[String], cwd: String = ".", timeout: int = 60, allow_network: bool = false) -> Dictionary:
	var bounded_timeout := clampi(timeout, 1, MAX_SANDBOX_TIMEOUT)
	return await _json_request("/sandbox/container_exec", HTTPClient.METHOD_POST, {
		"command": command,
		"cwd": cwd,
		"timeout": bounded_timeout,
		"allow_network": allow_network,
	}, float(bounded_timeout + 5), true)

func sandbox_write(path: String, content: String) -> Dictionary:
	return await _json_request("/sandbox/write", HTTPClient.METHOD_POST, {"path": path, "content": content}, DEFAULT_TIMEOUT, true)

func _master_enabled() -> bool:
	var current: Node = self
	for _i in range(6):
		if current == null:
			break
		var manager = current.get_node_or_null("AutonomySettingsManager")
		if manager != null and manager.has_method("get_settings"):
			var settings = manager.call("get_settings")
			if settings is Dictionary:
				return bool(settings.get("master_enabled", true))
		current = current.get_parent()
	return true

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
	return result

func _new_service_token() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(32).hex_encode()

func _new_action_id() -> String:
	_request_sequence += 1
	return "%d:%d:%d:%s" % [OS.get_process_id(), Time.get_ticks_usec(), _request_sequence, _new_service_token().substr(0, 16)]
