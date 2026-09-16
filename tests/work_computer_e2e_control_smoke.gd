extends SceneTree

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _init() -> void:
	var manager := AuroraWorkManager.new()
	root.add_child(manager)
	await process_frame
	var store := manager.store

	var project := store.create_project("Control race", "")
	var project_id := str(project.get("id", ""))
	if project_id.is_empty():
		_fail("project create failed", 2)
		return

	# Unsafe action: cancellation can race with an action that may already have
	# changed external state. The task must never become blindly retryable.
	var unsafe_task := store.create_task(project_id, "unsafe race")
	var unsafe_id := str(unsafe_task.get("id", ""))
	var unsafe_execution := "unsafe-exec"
	if not store.start_task(project_id, unsafe_id, unsafe_execution):
		_fail("unsafe task start failed", 3)
		return
	manager._running_tasks[unsafe_id] = {
		"project_id": project_id,
		"execution_id": unsafe_execution,
		"cancel_requested": false,
		"pause_requested": false,
		"unsafe_action_inflight": false,
	}
	manager._action_sequence[unsafe_id] = 0
	var before_unsafe := manager._execution_guard("before_tool", {"tool":"write_file"}, project_id, unsafe_id, unsafe_execution)
	if not bool(before_unsafe.get("allowed", false)):
		_fail("unsafe tool unexpectedly denied before cancel", 4)
		return
	if not manager.cancel_task(project_id, unsafe_id):
		_fail("unsafe cancel request failed", 5)
		return
	var stopped_unsafe := manager._execution_guard("after_tool", {"tool":"write_file", "result":{"ok":true}}, project_id, unsafe_id, unsafe_execution)
	if bool(stopped_unsafe.get("allowed", true)) or str(stopped_unsafe.get("reason", "")) != "cancelled":
		_fail("cancel was not observed immediately after unsafe tool", 6)
		return
	var unsafe_finish := manager._finish_controlled(project_id, unsafe_id, unsafe_execution, "cancelled")
	var unsafe_saved := store.get_task(project_id, unsafe_id)
	if str(unsafe_saved.get("status", "")) != AuroraWorkStore.STATE_CANCELLED:
		_fail("unsafe race did not end cancelled", 7)
		return
	if not bool(unsafe_saved.get("requires_user_action", false)):
		_fail("unsafe race did not require user verification", 8)
		return
	if bool(unsafe_saved.get("retryable", true)) or bool(unsafe_finish.get("retryable", true)):
		_fail("unsafe race remained automatically retryable", 9)
		return
	if store.retry_task(project_id, unsafe_id):
		_fail("store allowed blind retry after unsafe uncertain result", 10)
		return

	# Safe read-like action: cancellation after the action is deterministic and
	# does not create destructive replay risk, so explicit retry may remain safe.
	var safe_task := store.create_task(project_id, "safe race")
	var safe_id := str(safe_task.get("id", ""))
	var safe_execution := "safe-exec"
	if not store.start_task(project_id, safe_id, safe_execution):
		_fail("safe task start failed", 11)
		return
	manager._running_tasks[safe_id] = {
		"project_id": project_id,
		"execution_id": safe_execution,
		"cancel_requested": false,
		"pause_requested": false,
		"unsafe_action_inflight": false,
	}
	manager._action_sequence[safe_id] = 0
	manager._execution_guard("before_tool", {"tool":"read_file"}, project_id, safe_id, safe_execution)
	manager._execution_guard("after_tool", {"tool":"read_file", "result":{"ok":true}}, project_id, safe_id, safe_execution)
	if not manager.cancel_task(project_id, safe_id):
		_fail("safe cancel request failed", 12)
		return
	var safe_finish := manager._finish_controlled(project_id, safe_id, safe_execution, "cancelled")
	var safe_saved := store.get_task(project_id, safe_id)
	if bool(safe_saved.get("requires_user_action", false)):
		_fail("safe cancel incorrectly requires destructive verification", 13)
		return
	if not bool(safe_finish.get("retryable", false)):
		_fail("safe cancel was not marked retryable", 14)
		return
	if not store.retry_task(project_id, safe_id):
		_fail("safe cancelled task could not be explicitly retried", 15)
		return

	# Master-stop after an unsafe action follows the same conservative recovery
	# policy and must become interrupted + user action required.
	var stop_task := store.create_task(project_id, "master stop race")
	var stop_id := str(stop_task.get("id", ""))
	var stop_execution := "stop-exec"
	if not store.start_task(project_id, stop_id, stop_execution):
		_fail("master-stop task start failed", 16)
		return
	manager._running_tasks[stop_id] = {
		"project_id": project_id,
		"execution_id": stop_execution,
		"cancel_requested": false,
		"pause_requested": false,
		"unsafe_action_inflight": false,
	}
	manager._action_sequence[stop_id] = 0
	manager._execution_guard("before_tool", {"tool":"run_process"}, project_id, stop_id, stop_execution)
	var stop_finish := manager._finish_controlled(project_id, stop_id, stop_execution, "master_stop")
	var stop_saved := store.get_task(project_id, stop_id)
	if str(stop_saved.get("status", "")) != AuroraWorkStore.STATE_INTERRUPTED:
		_fail("unsafe master-stop race was not interrupted", 17)
		return
	if not bool(stop_saved.get("requires_user_action", false)) or bool(stop_finish.get("retryable", true)):
		_fail("unsafe master-stop race did not block blind replay", 18)
		return

	manager.queue_free()
	print("AURORA_WORK_COMPUTER_CONTROL_SMOKE_OK")
	quit(0)
