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
		"unsafe_action_uncertain": false,
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

	# User acknowledgement may explicitly keep retry blocked after observing that
	# a potentially unsafe side effect already happened. Acknowledgement itself
	# must not enqueue or execute anything.
	var blocked_ack := manager.acknowledge_uncertain_action(project_id, unsafe_id, false, "Verified external side effect; do not replay")
	if not bool(blocked_ack.get("ok", false)):
		_fail("explicit retry-block acknowledgement failed", 27)
		return
	var blocked_saved := store.get_task(project_id, unsafe_id)
	if bool(blocked_saved.get("requires_user_action", true)) or bool(blocked_saved.get("retryable", true)):
		_fail("retry-block acknowledgement did not persist conservative state", 28)
		return
	if str(blocked_saved.get("status", "")) != AuroraWorkStore.STATE_CANCELLED:
		_fail("acknowledgement changed terminal task state", 29)
		return
	if store.retry_task(project_id, unsafe_id):
		_fail("blocked acknowledgement unexpectedly enabled retry", 30)
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
		"unsafe_action_uncertain": false,
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
		"unsafe_action_uncertain": false,
	}
	manager._action_sequence[stop_id] = 0
	manager._execution_guard("before_tool", {"tool":"sandbox_exec"}, project_id, stop_id, stop_execution)
	var stop_finish := manager._finish_controlled(project_id, stop_id, stop_execution, "master_stop")
	var stop_saved := store.get_task(project_id, stop_id)
	if str(stop_saved.get("status", "")) != AuroraWorkStore.STATE_INTERRUPTED:
		_fail("unsafe master-stop race was not interrupted", 17)
		return
	if not bool(stop_saved.get("requires_user_action", false)) or bool(stop_finish.get("retryable", true)):
		_fail("unsafe master-stop race did not block blind replay", 18)
		return

	# A computer action gets a Work-owned action_id and an uncertain timeout must
	# stop the task before another model/tool step can blindly replay it.
	var timeout_task := store.create_task(project_id, "computer timeout")
	var timeout_id := str(timeout_task.get("id", ""))
	var timeout_execution := "timeout-exec"
	if not store.start_task(project_id, timeout_id, timeout_execution):
		_fail("timeout task start failed", 19)
		return
	manager._running_tasks[timeout_id] = {
		"project_id": project_id,
		"execution_id": timeout_execution,
		"cancel_requested": false,
		"pause_requested": false,
		"unsafe_action_inflight": false,
		"unsafe_action_uncertain": false,
	}
	manager._action_sequence[timeout_id] = 0
	var before_computer := manager._execution_guard("before_tool", {"tool":"computer_action"}, project_id, timeout_id, timeout_execution)
	var args_patch: Dictionary = before_computer.get("args_patch", {})
	var action_id := str(args_patch.get("action_id", ""))
	if not bool(before_computer.get("allowed", false)) or action_id != timeout_execution + ":1":
		_fail("Work did not provide stable computer action_id", 20)
		return
	var uncertain := manager._execution_guard("after_tool", {"tool":"computer_action", "result":{"ok":false,"error":"timeout","retryable":false}}, project_id, timeout_id, timeout_execution)
	if bool(uncertain.get("allowed", true)) or str(uncertain.get("reason", "")) != "unsafe_action_uncertain":
		_fail("uncertain unsafe result did not stop execution", 21)
		return
	var timeout_finish := manager._finish_controlled(project_id, timeout_id, timeout_execution, str(uncertain.get("reason", "")))
	var timeout_saved := store.get_task(project_id, timeout_id)
	if str(timeout_saved.get("status", "")) != AuroraWorkStore.STATE_INTERRUPTED:
		_fail("uncertain computer action was not interrupted", 22)
		return
	if not bool(timeout_saved.get("requires_user_action", false)) or bool(timeout_saved.get("retryable", true)):
		_fail("uncertain computer action did not require verification", 23)
		return
	if bool(timeout_finish.get("retryable", true)) or not bool(timeout_finish.get("requires_user_action", false)):
		_fail("uncertain computer action response allowed blind retry", 24)
		return
	if store.retry_task(project_id, timeout_id):
		_fail("uncertain action became retryable before acknowledgement", 31)
		return

	# After the user verifies the real external state, they may explicitly allow
	# a future retry. Acknowledgement only changes recovery metadata; it does not
	# start the task. The explicit retry operation remains a separate step.
	var retry_ack := manager.acknowledge_uncertain_action(project_id, timeout_id, true, "Verified no external state change")
	if not bool(retry_ack.get("ok", false)) or not bool(retry_ack.get("retryable", false)):
		_fail("explicit retry acknowledgement failed", 32)
		return
	var acknowledged := store.get_task(project_id, timeout_id)
	if bool(acknowledged.get("requires_user_action", true)) or not bool(acknowledged.get("retryable", false)):
		_fail("retry acknowledgement did not persist verified state", 33)
		return
	if str(acknowledged.get("status", "")) != AuroraWorkStore.STATE_INTERRUPTED:
		_fail("retry acknowledgement started or changed task state", 34)
		return
	if not store.retry_task(project_id, timeout_id):
		_fail("explicitly acknowledged task could not be queued for retry", 35)
		return
	var queued_after_ack := store.get_task(project_id, timeout_id)
	if str(queued_after_ack.get("status", "")) != AuroraWorkStore.STATE_QUEUED:
		_fail("acknowledged retry did not enter queued state", 36)
		return
	var invalid_second_ack := manager.acknowledge_uncertain_action(project_id, timeout_id, true)
	if bool(invalid_second_ack.get("ok", false)):
		_fail("acknowledgement unexpectedly accepted a non-terminal queued task", 37)
		return

	# Deterministic validation failure is not an uncertain external side effect;
	# the guard may return control to the Core to choose a corrected action.
	var rejected_task := store.create_task(project_id, "deterministic reject")
	var rejected_id := str(rejected_task.get("id", ""))
	var rejected_execution := "reject-exec"
	if not store.start_task(project_id, rejected_id, rejected_execution):
		_fail("rejected task start failed", 25)
		return
	manager._running_tasks[rejected_id] = {
		"project_id": project_id,
		"execution_id": rejected_execution,
		"cancel_requested": false,
		"pause_requested": false,
		"unsafe_action_inflight": false,
		"unsafe_action_uncertain": false,
	}
	manager._action_sequence[rejected_id] = 0
	manager._execution_guard("before_tool", {"tool":"computer_action"}, project_id, rejected_id, rejected_execution)
	var rejected := manager._execution_guard("after_tool", {"tool":"computer_action", "result":{"ok":false,"error":"http_error","http":400,"retryable":false}}, project_id, rejected_id, rejected_execution)
	if not bool(rejected.get("allowed", false)):
		_fail("deterministic validation rejection was treated as uncertain", 26)
		return
	manager.cancel_task(project_id, rejected_id)
	manager._finish_controlled(project_id, rejected_id, rejected_execution, "cancelled")

	manager.queue_free()
	print("AURORA_WORK_COMPUTER_CONTROL_SMOKE_OK")
	quit(0)