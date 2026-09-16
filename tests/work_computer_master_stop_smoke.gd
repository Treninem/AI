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
	# Computer control is a separate explicit permission from the global master
	# autonomy switch. Every fresh process must begin with it disabled.
	ComputerClient.set_computer_control_enabled(false)
	if ComputerClient.computer_control_enabled():
		_fail("Computer control was not default-off", 1)
		return
	ComputerClient.set_computer_control_enabled(true)
	if not ComputerClient.computer_control_enabled():
		_fail("Computer control permission could not be enabled explicitly", 7)
		return
	ComputerClient.set_computer_control_enabled(false)
	if ComputerClient.computer_control_enabled():
		_fail("Computer control permission could not be revoked", 8)
		return

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

	# Master resume never implicitly grants the more specific Computer control
	# permission; the user must enable it separately through the UI contract.
	if ComputerClient.computer_control_enabled():
		_fail("Master resume implicitly enabled Computer control", 9)
		return

	main.queue_free()
	await process_frame
	print("AURORA_WORK_COMPUTER_MASTER_STOP_SMOKE_OK")
	quit(0)
