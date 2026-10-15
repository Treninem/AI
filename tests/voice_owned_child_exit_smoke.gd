extends SceneTree


class QuietVoiceBridge:
	extends AuroraVoiceBridge

	func _ready() -> void:
		# Exercise teardown without starting the packaged backend or microphone.
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var python := OS.get_environment("AURORA_TEST_PYTHON")
	if python.is_empty() or not FileAccess.file_exists(python):
		push_error("VOICE_CHILD_EXIT_FAIL: AURORA_TEST_PYTHON must name an existing Python executable")
		quit(2)
		return
	var arguments := PackedStringArray(["-c", "import time; time.sleep(45)"])
	var owned_pid := OS.create_process(python, arguments, false)
	var unrelated_pid := OS.create_process(python, arguments, false)
	if owned_pid <= 0 or unrelated_pid <= 0:
		_stop_test_child(owned_pid)
		_stop_test_child(unrelated_pid)
		push_error("VOICE_CHILD_EXIT_FAIL: could not start disposable children")
		quit(3)
		return
	var bridge := QuietVoiceBridge.new()
	root.add_child(bridge)
	bridge.backend_pid = owned_pid
	bridge.queue_free()
	await process_frame
	var owned_stopped := not OS.is_process_running(owned_pid)
	var unrelated_preserved := OS.is_process_running(unrelated_pid)
	_stop_test_child(owned_pid)
	_stop_test_child(unrelated_pid)
	if not owned_stopped or not unrelated_preserved:
		push_error("VOICE_CHILD_EXIT_FAIL: owned child survived or unrelated child was stopped")
		quit(4)
		return
	print("AURORA_VOICE_OWNED_CHILD_EXIT_OK")
	quit(0)


func _stop_test_child(pid: int) -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
