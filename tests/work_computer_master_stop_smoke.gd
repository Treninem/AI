extends SceneTree

class FakeAutonomySettings:
	extends Node
	var master_enabled := false
	func get_settings() -> Dictionary:
		return {"master_enabled": master_enabled}

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := Node.new()
	main.name = "FakeMain"
	root.add_child(main)

	var settings := FakeAutonomySettings.new()
	settings.name = "AutonomySettings"
	main.add_child(settings)

	var work := AuroraWorkManager.new()
	work.name = "WorkManager"
	main.add_child(work)

	var computer := ComputerClient.new()
	computer.name = "ComputerClient"
	main.add_child(computer)
	await process_frame

	if work._master_enabled():
		_fail("WorkManager ignored master_enabled=false from real AutonomySettings node name", 2)
		return
	if computer._master_enabled():
		_fail("ComputerClient ignored master_enabled=false from real AutonomySettings node name", 3)
		return
	if ComputerClient.master_enabled_from(work):
		_fail("Shared master-stop resolver ignored disabled state", 4)
		return

	settings.master_enabled = true
	if not work._master_enabled():
		_fail("WorkManager did not observe master resume", 5)
		return
	if not computer._master_enabled():
		_fail("ComputerClient did not observe master resume", 6)
		return

	main.queue_free()
	await process_frame
	print("AURORA_WORK_COMPUTER_MASTER_STOP_SMOKE_OK")
	quit(0)
