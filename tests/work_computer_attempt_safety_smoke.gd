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
	var project := store.create_project("Attempt safety", "")
	var project_id := str(project.get("id", ""))

	# A successful unsafe side effect must stay attached to the whole attempt.
	# A later safe read must never erase the destructive-retry risk.
	var history_task := store.create_task(project_id, "unsafe then read then cancel")
	var history_id := str(history_task.get("id", ""))
	var history_exec := "history-exec"
	if not store.start_task(project_id, history_id, history_exec):
		_fail("history task start failed", 2)
		return
	manager._running_tasks[history_id] = _control(project_id, history_exec)
	manager._action_sequence[history_id] = 0
	var before_write := manager._execution_guard("before_tool", {"tool":"write_file"}, project_id, history_id, history_exec)
	if not bool(before_write.get("allowed", false)):
		_fail("unsafe write unexpectedly blocked", 3)
		return
	var after_write := manager._execution_guard("after_tool", {"tool":"write_file", "result":{"ok":true}}, project_id, history_id, history_exec)
	if not bool(after_write.get("allowed", false)):
		_fail("confirmed unsafe write was treated as uncertain", 4)
		return
	if str(store.get_task(project_id, history_id).get("attempt_retry_safety", "")) != "unsafe":
		_fail("confirmed unsafe side effect was not persisted for the attempt", 5)
		return
	manager._execution_guard("before_tool", {"tool":"read_file"}, project_id, history_id, history_exec)
	var after_read := manager._execution_guard("after_tool", {"tool":"read_file", "result":{"ok":true}}, project_id, history_id, history_exec)
	if not bool(after_read.get("allowed", false)):
		_fail("safe read unexpectedly blocked", 6)
		return
	if str(store.get_task(project_id, history_id).get("attempt_retry_safety", "")) != "unsafe":
		_fail("later safe read erased earlier unsafe attempt history", 7)
		return
	if not manager.cancel_task(project_id, history_id):
		_fail("history cancel failed", 8)
		return
	var history_finish := manager._finish_controlled(project_id, history_id, history_exec, "cancelled")
	var history_saved := store.get_task(project_id, history_id)
	if str(history_saved.get("status", "")) != AuroraWorkStore.STATE_CANCELLED:
		_fail("unsafe-history cancel did not reach cancelled", 9)
		return
	if not bool(history_saved.get("requires_user_action", false)) or bool(history_saved.get("retryable", true)):
		_fail("unsafe-history cancel allowed blind replay", 10)
		return
	if bool(history_finish.get("retryable", true)) or not bool(history_finish.get("requires_user_action", false)):
		_fail("unsafe-history cancel response allowed blind replay", 11)
		return

	# A downstream model/artifact failure after a successful side effect is not a
	# normal retryable failure. It must become interrupted until the user verifies
	# what actually happened externally.
	var failure_task := store.create_task(project_id, "unsafe then model fails")
	var failure_id := str(failure_task.get("id", ""))
	var failure_exec := "failure-exec"
	if not store.start_task(project_id, failure_id, failure_exec):
		_fail("failure task start failed", 12)
		return
	manager._running_tasks[failure_id] = _control(project_id, failure_exec)
	manager._action_sequence[failure_id] = 0
	manager._execution_guard("before_tool", {"tool":"computer_action"}, project_id, failure_id, failure_exec)
	var confirmed_click := manager._execution_guard("after_tool", {"tool":"computer_action", "result":{"ok":true,"retry_safety":"unsafe"}}, project_id, failure_id, failure_exec)
	if not bool(confirmed_click.get("allowed", false)):
		_fail("confirmed computer action unexpectedly blocked", 13)
		return
	var failure_result := manager._finish_failed_execution(project_id, failure_id, "model failed", "model failed")
	var failure_saved := store.get_task(project_id, failure_id)
	if str(failure_saved.get("status", "")) != AuroraWorkStore.STATE_INTERRUPTED:
		_fail("downstream failure after unsafe effect was not interrupted", 14)
		return
	if not bool(failure_saved.get("requires_user_action", false)) or bool(failure_saved.get("retryable", true)):
		_fail("downstream failure after unsafe effect remained retryable", 15)
		return
	if bool(failure_result.get("retryable", true)) or not bool(failure_result.get("requires_user_action", false)):
		_fail("downstream failure response allowed blind replay", 16)
		return

	# A deterministic pre-execution rejection must not poison the whole attempt.
	var reject_task := store.create_task(project_id, "rejected unsafe primitive")
	var reject_id := str(reject_task.get("id", ""))
	var reject_exec := "reject-attempt"
	if not store.start_task(project_id, reject_id, reject_exec):
		_fail("reject task start failed", 17)
		return
	manager._running_tasks[reject_id] = _control(project_id, reject_exec)
	manager._action_sequence[reject_id] = 0
	manager._execution_guard("before_tool", {"tool":"computer_action"}, project_id, reject_id, reject_exec)
	var rejected := manager._execution_guard("after_tool", {"tool":"computer_action", "result":{"ok":false,"error":"http_error","http":400,"retryable":false}}, project_id, reject_id, reject_exec)
	if not bool(rejected.get("allowed", false)):
		_fail("pre-execution validation rejection became uncertain", 18)
		return
	if str(store.get_task(project_id, reject_id).get("attempt_retry_safety", "")) != "safe":
		_fail("pre-execution rejection incorrectly poisoned attempt", 19)
		return
	var safe_failure := manager._finish_failed_execution(project_id, reject_id, "validation failed", "validation failed")
	var safe_failure_saved := store.get_task(project_id, reject_id)
	if str(safe_failure_saved.get("status", "")) != AuroraWorkStore.STATE_FAILED or not bool(safe_failure.get("retryable", false)):
		_fail("safe downstream failure lost normal retry contract", 20)
		return

	manager.queue_free()
	await process_frame
	print("AURORA_WORK_COMPUTER_ATTEMPT_SAFETY_OK")
	quit(0)