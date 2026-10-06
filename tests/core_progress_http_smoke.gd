extends SceneTree

class TerminalCore extends AuroraCoreRuntime:
	var calls := 0
	var response := {"ok": false, "model_failure": false, "retryable": false, "failure_scope": "cancelled", "cancelled": true, "error": "cancelled"}
	func _available_model_paths() -> Array[String]:
		return ["first", "second"]
	func _chat_local_model(_path: String, _messages: Array, _temperature: float) -> Dictionary:
		calls += 1
		return response.duplicate()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var runtime := DesktopLocalRuntime.new()
	root.add_child(runtime)
	var port := int(OS.get_environment("AURORAFOX_TEST_CORE_PORT"))
	var good: Dictionary = await runtime._request_progress_json({"fixture": "progress", "stream": true, "return_progress": true}, 0.25, 0, 10000, port)
	assert(good.ok and good.data.choices[0].message.content == "Привет 🌍")
	assert(good.progress.prompt_tokens_processed == 8)
	for kind in ["heartbeat", "duplicate"]:
		var bad: Dictionary = await runtime._request_progress_json({"fixture": kind}, 0.18, 0, 10000, port)
		assert(not bad.ok and bad.failure_scope == "no_progress" and not bad.model_failure)
	var total: Dictionary = await runtime._request_progress_json({"fixture": "progress"}, 0.25, 0.18, 10000, port)
	assert(not total.ok and total.failure_scope == "total_budget")
	var capped: Dictionary = await runtime._request_progress_json({"fixture": "progress"}, 0.25, 0, 10, port)
	assert(not capped.ok and capped.error.contains("byte budget"))
	for kind in ["malformed", "truncated", "http_error"]:
		var bad: Dictionary = await runtime._request_progress_json({"fixture": kind}, 0.25, 0, 10000, port)
		assert(not bad.ok and not bad.model_failure)
	var cancellation := create_timer(0.12)
	cancellation.timeout.connect(runtime.cancel_active_requests)
	var cancelled: Dictionary = await runtime._request_progress_json({"fixture": "progress"}, 0.25, 0, 10000, port)
	assert(not cancelled.ok and cancelled.cancelled and cancelled.failure_scope == "cancelled")
	assert(runtime._active_streams.is_empty())
	var core := TerminalCore.new()
	root.add_child(core)
	for scope in ["cancelled", "no_progress", "total_budget", "protocol", "response_budget"]:
		core.calls = 0
		core.response.failure_scope = scope
		var terminal: Dictionary = await core._chat_local([], 0.2)
		assert(not terminal.ok and terminal.failure_scope == scope and core.calls == 1)
	core.calls = 0
	core.response.model_failure = true
	core.response.retryable = true
	await core._chat_local([], 0.2)
	assert(core.calls == 2) # Genuine model failures retain local failover.
	core.queue_free()
	runtime.queue_free()
	print("AURORA_CORE_PROGRESS_HTTP_OK")
	quit(0)
