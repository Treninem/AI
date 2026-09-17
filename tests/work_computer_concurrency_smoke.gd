extends SceneTree

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _control(project_id: String, execution_id: String) -> Dictionary:
	return {
		"project_id": project_id,
		"execution_id": execution_id,
		"cancel_requested": false,
		"pause_requested": false,
		"unsafe_action_inflight": false,
		"unsafe_action_uncertain": false,
		"unsafe_action_seen": false,
	}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var manager := AuroraWorkManager.new()
	root.add_child(manager)
	await process_frame
	var store := manager.store
	var project := store.create_project("Concurrent Work isolation")
	var project_id := str(project.get("id", ""))
	var task_a := store.create_task(project_id, "unsafe desktop task")
	var task_b := store.create_task(project_id, "independent safe task")
	var task_a_id := str(task_a.get("id", ""))
	var task_b_id := str(task_b.get("id", ""))
	if task_a_id.is_empty() or task_b_id.is_empty() or task_a_id == task_b_id:
		_fail("Concurrent fixture task creation failed", 2)
		return
	if not store.start_task(project_id, task_a_id, "exec-a") or not store.start_task(project_id, task_b_id, "exec-b"):
		_fail("Concurrent fixture tasks did not enter running", 3)
		return
	manager._running_tasks[task_a_id] = _control(project_id, "exec-a")
	manager._running_tasks[task_b_id] = _control(project_id, "exec-b")
	manager._action_sequence[task_a_id] = 0
	manager._action_sequence[task_b_id] = 0
	manager._sync_running_flag()

	var a_before := manager._execution_guard("before_tool", {"tool": "computer_action"}, project_id, task_a_id, "exec-a")
	var b_before := manager._execution_guard("before_tool", {"tool": "read_file"}, project_id, task_b_id, "exec-b")
	if not bool(a_before.get("allowed", false)) or str((a_before.get("args_patch", {}) as Dictionary).get("action_id", "")) != "exec-a:1":
		_fail("Task A did not receive its own deterministic action id", 4)
		return
	if not bool(b_before.get("allowed", false)):
		_fail("Independent task B was blocked by task A", 5)
		return
	var persisted_a := store.get_task(project_id, task_a_id)
	var persisted_b := store.get_task(project_id, task_b_id)
	if str(persisted_a.get("last_action_id", "")) != "exec-a:1" or str(persisted_b.get("last_action_id", "")) != "exec-b:1":
		_fail("Concurrent action sequences crossed task boundaries", 6)
		return

	var b_after := manager._execution_guard("after_tool", {"tool": "read_file", "result": {"ok": true}}, project_id, task_b_id, "exec-b")
	if not bool(b_after.get("allowed", false)):
		_fail("Safe task B completion was affected by task A", 7)
		return
	var a_after := manager._execution_guard("after_tool", {"tool": "computer_action", "result": {"ok": false, "error": "timeout", "retryable": false}}, project_id, task_a_id, "exec-a")
	if bool(a_after.get("allowed", true)) or str(a_after.get("reason", "")) != "unsafe_action_uncertain":
		_fail("Unsafe task A uncertainty did not stop only task A", 8)
		return
	var a_finish := manager._finish_controlled(project_id, task_a_id, "exec-a", "unsafe_action_uncertain")
	if not bool(a_finish.get("requires_user_action", false)) or bool(a_finish.get("retryable", true)):
		_fail("Unsafe task A did not fail closed", 9)
		return
	if not manager._running_tasks.has(task_b_id):
		_fail("Finishing task A removed independent task B control state", 10)
		return
	if str(store.get_task(project_id, task_b_id).get("status", "")) != AuroraWorkStore.STATE_RUNNING:
		_fail("Task A failure changed task B persisted state", 11)
		return

	var b_second := manager._execution_guard("before_tool", {"tool": "read_file"}, project_id, task_b_id, "exec-b")
	if not bool(b_second.get("allowed", false)) or str(store.get_task(project_id, task_b_id).get("last_action_id", "")) != "exec-b:2":
		_fail("Task B could not continue with an isolated action sequence", 12)
		return
	manager._execution_guard("after_tool", {"tool": "read_file", "result": {"ok": true}}, project_id, task_b_id, "exec-b")
	if not manager.cancel_task(project_id, task_b_id):
		_fail("Safe task B cancel request failed", 13)
		return
	var b_finish := manager._finish_controlled(project_id, task_b_id, "exec-b", "cancelled")
	if not bool(b_finish.get("retryable", false)) or bool(b_finish.get("requires_user_action", false)):
		_fail("Safe task B cancellation inherited unsafe state from task A", 14)
		return
	if str(store.get_task(project_id, task_a_id).get("status", "")) != AuroraWorkStore.STATE_INTERRUPTED:
		_fail("Task A fail-closed state changed after task B completion", 15)
		return

	manager.queue_free()
	print("AURORA_WORK_COMPUTER_CONCURRENCY_OK tasks=2 isolated_action_ids=true unsafe_state_isolated=true")
	quit(0)
