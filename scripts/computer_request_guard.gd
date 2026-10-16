class_name ComputerRequestGuard
extends RefCounted

static func execution_timeout(requested: int) -> int:
	if requested < 0: return -1
	var maximum := OwnerResourcePolicy.value("sandbox_exec_max_seconds")
	if maximum == 0: return requested
	return maximum if requested == 0 else mini(requested, maximum)

static func execution_http_timeout(seconds: int) -> float:
	return 0.0 if seconds == 0 else float(seconds) + 5.0

static func configure_request(request: HTTPRequest, requested: float, default_key: String) -> bool:
	if not is_finite(requested) or requested < -1.0: return false
	var seconds := float(OwnerResourcePolicy.value(default_key)) if requested == -1.0 else requested
	var maximum := float(OwnerResourcePolicy.value("computer_http_max_seconds"))
	if maximum > 0.0:
		seconds = maximum if seconds == 0.0 else minf(seconds, maximum)
	request.timeout = seconds
	var bytes := OwnerResourcePolicy.value("computer_response_bytes")
	request.body_size_limit = -1 if bytes == 0 else bytes
	return true

static func execution_payload(path: String, payload: Dictionary) -> Dictionary:
	var captured := payload.duplicate(true)
	var route := path.get_slice("?", 0)
	var process := route.ends_with("/sandbox/exec") or route.ends_with("/sandbox/container_exec")
	var gui := route.ends_with("/action") or route.ends_with("/screen") or route.ends_with("/windows")
	if route.ends_with("/sandbox/list"):
		captured["_sandbox_items"] = OwnerResourcePolicy.value("sandbox_tree_items")
	if process:
		captured["output_chars"] = OwnerResourcePolicy.value("computer_output_chars")
		captured["capture_bytes"] = OwnerResourcePolicy.value("computer_capture_bytes")
	if gui:
		captured["_gui_limits"] = {}
		for key in ["uia_items", "uia_windows", "uia_controls", "uia_name_chars", "uia_type_chars", "uia_id_chars", "worker_seconds", "action_results", "action_identities", "action_text_chars", "action_keys", "action_clicks", "action_scroll", "action_seconds", "action_worker_seconds"]:
			captured["_gui_limits"][key] = OwnerResourcePolicy.value("computer_" + key)
	if process or gui:
		# Caller/model input cannot select a previous execution identity.
		captured["execution_id"] = "%d:%d:%s" % [OS.get_process_id(), Time.get_ticks_usec(), Crypto.new().generate_random_bytes(16).hex_encode()]
		captured["_unsafe_gui"] = route.ends_with("/action") and str(captured.get("type", "")).strip_edges().to_lower() not in ["move", "wait", "done"]
	return captured

static func append_execution_header(headers: PackedStringArray, payload: Dictionary) -> PackedStringArray:
	var captured := headers.duplicate()
	if payload.has("execution_id"):
		captured.append("X-AuroraFox-Execution-ID: " + str(payload.execution_id))
	if payload.has("_sandbox_items"):
		captured.append("X-AuroraFox-Sandbox-Items: " + str(payload["_sandbox_items"]))
	if payload.has("_gui_limits"):
		captured.append("X-AuroraFox-GUI-Limits: " + JSON.stringify(payload["_gui_limits"]))
	return captured

static func wait(request: HTTPRequest, owner: Node, allowed: Callable, service_url: String, token: String, payload: Dictionary) -> Dictionary:
	var state := {"done": false, "completed": []}
	request.request_completed.connect(func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
		state.completed = [result, response_code, headers, body]
		state.done = true
	, CONNECT_ONE_SHOT)
	while not state.done:
		if not is_instance_valid(owner) or not is_instance_valid(request) or not allowed.is_valid():
			return {"cancelled": true, "termination_confirmed": false, "uncertain_external_state": true, "retryable": false}
		if not bool(allowed.call()):
			request.cancel_request()
			var cancellation := await _cancel_execution(owner, service_url, token, str(payload.get("execution_id", "")))
			return {"cancelled": true, "termination_confirmed": cancellation, "uncertain_external_state": not cancellation or bool(payload.get("_unsafe_gui", false)), "retryable": false}
		await owner.get_tree().create_timer(0.05).timeout
	if not is_instance_valid(owner) or not is_instance_valid(request) or not allowed.is_valid():
		return {"cancelled": true, "termination_confirmed": false, "uncertain_external_state": true, "retryable": false}
	if not bool(allowed.call()):
		var cancellation := await _cancel_execution(owner, service_url, token, str(payload.get("execution_id", "")))
		return {"cancelled": true, "termination_confirmed": cancellation, "uncertain_external_state": not cancellation or bool(payload.get("_unsafe_gui", false)), "retryable": false}
	var completed: Array = state.completed
	if not completed.is_empty() and int(completed[0]) != HTTPRequest.RESULT_SUCCESS and payload.has("execution_id"):
		var cancellation := await _cancel_execution(owner, service_url, token, str(payload.execution_id))
		return {"cancelled": true, "termination_confirmed": cancellation, "uncertain_external_state": not cancellation or bool(payload.get("_unsafe_gui", false)), "retryable": false, "transport_result": int(completed[0])}
	return {"cancelled": false, "completed": completed}

static func _cancel_execution(owner: Node, service_url: String, token: String, execution_id: String) -> bool:
	if execution_id.is_empty():
		return false # No identity means no proven owned stop; no stop reverses an effect.
	var cancel := HTTPRequest.new()
	cancel.timeout = 10.0 # Bounded stop acknowledgement; never a product execution deadline.
	owner.add_child(cancel)
	var headers := PackedStringArray(["Content-Type: application/json", "X-AuroraFox-Computer-Token: " + token])
	var error := cancel.request(service_url + "/sandbox/cancel", headers, HTTPClient.METHOD_POST, JSON.stringify({"execution_id": execution_id}))
	if error != OK:
		cancel.queue_free()
		return false
	var completed: Array = await cancel.request_completed
	cancel.queue_free()
	if completed.size() < 4 or int(completed[0]) != HTTPRequest.RESULT_SUCCESS or int(completed[1]) != 200:
		return false
	var body = JSON.parse_string((completed[3] as PackedByteArray).get_string_from_utf8())
	return body is Dictionary and bool(body.get("ok", false)) and bool(body.get("termination_confirmed", false))

static func stop_service_sync(service_url: String, token: String) -> bool:
	# Node exit/restart cannot await SceneTree frames. Stop owned jobs before
	# killing the sidecar, while its process/container registry still exists.
	if not service_url.begins_with("http://") or token.is_empty(): return false
	var authority := service_url.trim_prefix("http://").trim_suffix("/").split(":")
	if authority.size() != 2 or authority[0] not in ["127.0.0.1", "localhost"]: return false
	if not str(authority[1]).is_valid_int(): return false
	var port := int(authority[1])
	if port < 1 or port > 65535: return false
	var client := HTTPClient.new()
	var deadline := Time.get_ticks_msec() + 10000
	if client.connect_to_host(str(authority[0]), port) != OK: return false
	while client.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING] and Time.get_ticks_msec() < deadline:
		client.poll()
		OS.delay_msec(5)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		client.close()
		return false
	var headers := PackedStringArray(["Content-Type: application/json", "X-AuroraFox-Computer-Token: " + token])
	if client.request(HTTPClient.METHOD_POST, "/sandbox/cancel_all", headers, "{}") != OK:
		client.close()
		return false
	var body := PackedByteArray()
	while Time.get_ticks_msec() < deadline:
		client.poll()
		if client.get_status() == HTTPClient.STATUS_BODY:
			body.append_array(client.read_response_body_chunk())
		elif client.get_status() == HTTPClient.STATUS_CONNECTED:
			break
		elif client.get_status() != HTTPClient.STATUS_REQUESTING:
			client.close()
			return false
		OS.delay_msec(5)
	var code := client.get_response_code()
	client.close()
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	return code == 200 and parsed is Dictionary and bool(parsed.get("ok", false)) and bool(parsed.get("termination_confirmed", false))
