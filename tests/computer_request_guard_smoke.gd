extends SceneTree

class MasterFixture extends Node:
	var enabled := true
	func get_settings() -> Dictionary:
		return {"master_enabled": enabled}

func _initialize() -> void:
	call_deferred("_run")

func _start(owner: Node, url: String, token: String, execution_id: String, timeout: float) -> HTTPRequest:
	var request := HTTPRequest.new()
	request.timeout = timeout
	owner.add_child(request)
	var command := [OS.get_environment("AURORAFOX_GUARD_PYTHON"), "owned.py", execution_id]
	var headers := PackedStringArray(["Content-Type: application/json", "X-AuroraFox-Computer-Token: " + token, "X-AuroraFox-Autonomy-Allowed: 1"])
	assert(request.request(url + "/sandbox/exec", headers, HTTPClient.METHOD_POST, JSON.stringify({"command": command, "timeout": 60, "execution_id": execution_id})) == OK)
	return request

func _capture_gui_guard(request: HTTPRequest, owner: Node, allowed: Callable, url: String, token: String, payload: Dictionary, state: Dictionary) -> void:
	state.result = await ComputerRequestGuard.wait(request, owner, allowed, url, token, payload)
	state.done = true

func _gui_case(owner: MasterFixture, url: String, token: String, allowed: Callable, route: String, unsafe: bool, timeout: float) -> void:
	owner.enabled = true
	var raw := {"type": "press" if unsafe else "wait", "keys": ["a"], "seconds": 0, "action_id": "gui-fixture-unsafe" if unsafe else "", "execution_id": "model-supplied", "_unsafe_gui": false}
	OwnerResourcePolicy._cached.computer_worker_seconds = 0
	OwnerResourcePolicy._cached.computer_uia_items = 1001
	raw["_gui_limits"] = {"worker_seconds": 1, "uia_items": 1}
	var payload := ComputerRequestGuard.execution_payload(route, raw)
	assert(payload.execution_id != "model-supplied" and bool(payload._unsafe_gui) == unsafe)
	var request := HTTPRequest.new()
	request.timeout = timeout
	owner.add_child(request)
	var headers := ComputerRequestGuard.append_execution_header(PackedStringArray(["Content-Type: application/json", "X-AuroraFox-Computer-Token: " + token, "X-AuroraFox-Autonomy-Allowed: 1"]), payload)
	var method := HTTPClient.METHOD_GET if route == "/windows" else HTTPClient.METHOD_POST
	assert(request.request(url + route, headers, method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(payload)) == OK)
	var state := {"done": false}
	call_deferred("_capture_gui_guard", request, owner, allowed, url, token, payload, state)
	var root_path := OS.get_environment("AURORAFOX_GUARD_ROOT")
	var digest := str(payload.execution_id).sha256_text()
	var marker := root_path.path_join("gui-started-" + digest)
	var deadline := Time.get_ticks_msec() + 5000
	while not FileAccess.file_exists(marker) and Time.get_ticks_msec() < deadline and not state.done:
		await create_timer(0.02).timeout
	assert(FileAccess.file_exists(marker))
	if route == "/windows":
		var actual_policy = JSON.parse_string(FileAccess.get_file_as_string(root_path.path_join("gui-policy-" + digest)))
		assert(actual_policy is Dictionary and actual_policy.worker_seconds == 0 and actual_policy.uia_items == 1001)
	if timeout > 5.0: owner.enabled = false
	deadline = Time.get_ticks_msec() + 15000
	while not state.done and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	assert(state.done)
	var result: Dictionary = state.result
	assert(result.cancelled and result.termination_confirmed and not result.retryable)
	assert(bool(result.uncertain_external_state) == unsafe)
	if timeout <= 5.0: assert(result.has("transport_result"))
	var heartbeat := root_path.path_join("gui-heartbeat-" + digest)
	var before := FileAccess.get_file_as_string(heartbeat)
	await create_timer(0.1).timeout
	assert(FileAccess.get_file_as_string(heartbeat) == before)
	request.queue_free()
	owner.enabled = true

func _run() -> void:
	var url := OS.get_environment("AURORAFOX_GUARD_URL")
	var token := OS.get_environment("AURORAFOX_GUARD_TOKEN")
	assert(url.begins_with("http://127.0.0.1:"))
	var policy_original := OwnerResourcePolicy._cached.duplicate()
	OwnerResourcePolicy._cached = OwnerResourcePolicy.DEFAULTS.duplicate()
	var owner := MasterFixture.new()
	root.add_child(owner)
	var allowed := func() -> bool: return ComputerClient.master_enabled_from(owner)
	var first := ComputerRequestGuard.execution_payload("/sandbox/exec", {"execution_id": "model-supplied"})
	var second := ComputerRequestGuard.execution_payload("/sandbox/exec", {"execution_id": "model-supplied"})
	assert(first.execution_id != "model-supplied" and first.execution_id != second.execution_id)
	assert(not ComputerRequestGuard.execution_payload("/sandbox/write", {}).has("execution_id"))
	var request := _start(owner, url, token, "guard-master", 60)
	create_timer(0.5).timeout.connect(func() -> void: owner.enabled = false)
	var cancelled: Dictionary = await ComputerRequestGuard.wait(request, owner, allowed, url, token, {"execution_id": "guard-master"})
	assert(cancelled.cancelled and cancelled.termination_confirmed and not cancelled.uncertain_external_state and not cancelled.retryable)
	request.queue_free()
	owner.enabled = true
	var transport := _start(owner, url, token, "guard-transport", 0.2)
	var timed: Dictionary = await ComputerRequestGuard.wait(transport, owner, allowed, url, token, {"execution_id": "guard-transport"})
	assert(timed.cancelled and timed.termination_confirmed and not timed.retryable and timed.has("transport_result"))
	transport.queue_free()
	var uncertain := _start(owner, url, token, "guard-uncertain", 60)
	owner.enabled = false
	var unconfirmed: Dictionary = await ComputerRequestGuard.wait(uncertain, owner, allowed, url + "/unavailable", token, {"execution_id": "guard-uncertain"})
	assert(unconfirmed.cancelled and not unconfirmed.termination_confirmed and unconfirmed.uncertain_external_state and not unconfirmed.retryable)
	assert(await ComputerRequestGuard._cancel_execution(owner, url, token, "guard-uncertain"))
	uncertain.queue_free()
	owner.enabled = true
	var bounded := HTTPRequest.new()
	owner.add_child(bounded)
	OwnerResourcePolicy._cached.computer_response_bytes = 16
	assert(ComputerRequestGuard.configure_request(bounded, 5.0, "computer_default_http_seconds"))
	var headers := PackedStringArray(["Content-Type: application/json", "X-AuroraFox-Computer-Token: " + token, "X-AuroraFox-Autonomy-Allowed: 1"])
	var quick_payload := {"command": [OS.get_environment("AURORAFOX_GUARD_PYTHON"), "-c", "print('x'*3000)"], "timeout": 0, "execution_id": "guard-body"}
	assert(bounded.request(url + "/sandbox/exec", headers, HTTPClient.METHOD_POST, JSON.stringify(quick_payload)) == OK)
	var overflow: Dictionary = await ComputerRequestGuard.wait(bounded, owner, allowed, url, token, quick_payload)
	assert(overflow.cancelled and overflow.termination_confirmed and overflow.transport_result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED)
	bounded.queue_free()
	OwnerResourcePolicy._cached.computer_response_bytes = 0
	await _gui_case(owner, url, token, allowed, "/action", false, 60.0)
	await _gui_case(owner, url, token, allowed, "/action", true, 60.0)
	await _gui_case(owner, url, token, allowed, "/windows", false, 2.0)
	var shutdown := _start(owner, url, token, "guard-shutdown", 60)
	var marker := OS.get_environment("AURORAFOX_GUARD_ROOT").path_join("started-guard-shutdown")
	var deadline := Time.get_ticks_msec() + 5000
	while not FileAccess.file_exists(marker) and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	assert(FileAccess.file_exists(marker))
	assert(ComputerRequestGuard.stop_service_sync(url, token))
	var stopped_reply: Array = await shutdown.request_completed
	var stopped_body = JSON.parse_string((stopped_reply[3] as PackedByteArray).get_string_from_utf8())
	assert(stopped_body is Dictionary and stopped_body.error == "cancelled")
	shutdown.queue_free()
	assert(not ComputerRequestGuard.stop_service_sync("https://example.com", token))
	OwnerResourcePolicy._cached = policy_original
	OwnerResourcePolicy.revision += 1
	owner.queue_free()
	await process_frame
	print("AURORA_COMPUTER_OWNED_CANCEL_OK master_stop=PASS transport=PASS uncertain=PASS shutdown=PASS gui_master=PASS gui_unsafe_review=PASS gui_transport=PASS")
	quit(0)
