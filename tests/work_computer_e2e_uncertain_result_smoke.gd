extends SceneTree

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _init() -> void:
	var manager := AuroraWorkManager.new()
	root.add_child(manager)
	await process_frame

	# An accepted unsafe primitive can fail after changing external state. The
	# exception name is not an authority signal; retry_safety=unsafe must make
	# every failed result uncertain and block blind replay.
	if not manager._tool_result_uncertain({
		"ok": false,
		"error": "PyAutoGUIException",
		"message": "arbitrary new worker exception",
		"retryable": false,
		"retry_safety": "unsafe",
	}):
		_fail("unknown failed unsafe result was treated as deterministic", 2)
		return

	# A pre-execution permission/validation rejection has no retry_safety marker
	# and is known not to have started an external primitive.
	if manager._tool_result_uncertain({
		"ok": false,
		"error": "permission_denied",
		"retryable": false,
	}):
		_fail("permission rejection was incorrectly treated as uncertain", 3)
		return

	# Busy is returned before execution of the requested action and is therefore
	# deterministic for that action, unlike action_in_progress for the same ID.
	if manager._tool_result_uncertain({
		"ok": false,
		"error": "computer_busy",
		"retryable": false,
		"executed": false,
	}):
		_fail("non-started busy action was incorrectly treated as uncertain", 4)
		return

	if not manager._tool_result_uncertain({
		"ok": false,
		"error": "action_in_progress",
		"retryable": false,
		"retry_safety": "unsafe",
		"uncertain_external_state": true,
	}):
		_fail("duplicate in-flight unsafe action did not require observation", 5)
		return

	manager.queue_free()
	await process_frame
	print("AURORA_WORK_COMPUTER_UNCERTAIN_RESULT_SMOKE_OK")
	quit(0)
