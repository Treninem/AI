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

func _run() -> void:
	var url := OS.get_environment("AURORAFOX_GUARD_URL")
	var token := OS.get_environment("AURORAFOX_GUARD_TOKEN")
	assert(url.begins_with("http://127.0.0.1:"))
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
	owner.queue_free()
	await process_frame
	print("AURORA_COMPUTER_OWNED_CANCEL_OK master_stop=PASS transport=PASS uncertain=PASS shutdown=PASS")
	quit(0)
