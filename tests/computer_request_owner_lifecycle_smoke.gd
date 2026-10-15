extends SceneTree

class WaitProbe extends Node:
	signal finished(result: Dictionary)

	func start(request: HTTPRequest, owner: Node, allowed: Callable) -> void:
		var result: Dictionary = await ComputerRequestGuard.wait(request, owner, allowed, "http://127.0.0.1:1", "", {"execution_id": "synthetic"})
		finished.emit(result)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var owner := Node.new()
	root.add_child(owner)
	var request := HTTPRequest.new()
	owner.add_child(request)
	var allowed := func() -> bool: return owner.is_inside_tree()
	var probe := WaitProbe.new()
	root.add_child(probe)
	probe.call_deferred("start", request, owner, allowed)
	await process_frame
	await process_frame
	owner.queue_free()
	var result: Dictionary = await probe.finished
	if not bool(result.get("cancelled", false)) or bool(result.get("termination_confirmed", true)) or not bool(result.get("uncertain_external_state", false)) or bool(result.get("retryable", true)):
		push_error("Destroyed request owner must fail closed without claiming remote termination")
		quit(1)
		return
	print("AURORA_COMPUTER_REQUEST_OWNER_LIFECYCLE_OK")
	quit(0)
