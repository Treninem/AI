extends SceneTree


class QuietVoiceBridge:
	extends AuroraVoiceBridge

	func _ready() -> void:
		# Exercise teardown without starting the packaged backend or microphone.
		pass


class CountingVoiceBridge:
	extends AuroraVoiceBridge

	var starts := 0
	var connects := 0

	func _start_backend_if_installed() -> void:
		starts += 1

	func _connect_ws() -> void:
		connects += 1


class DisabledVoiceManager:
	extends AuroraVoiceManager

	func _load_settings() -> void:
		settings = DEFAULTS.duplicate(true)
		settings["enabled"] = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var python := OS.get_environment("AURORA_TEST_PYTHON")
	if python.is_empty() or not FileAccess.file_exists(python):
		push_error("VOICE_CHILD_EXIT_FAIL: AURORA_TEST_PYTHON must name an existing Python executable")
		quit(2)
		return
	var arguments := PackedStringArray(["-c", "import time; time.sleep(45)"])
	var manager := DisabledVoiceManager.new()
	var counted_bridge := CountingVoiceBridge.new()
	manager.bridge = counted_bridge
	root.add_child(manager)
	await process_frame
	if counted_bridge.backend_requested or counted_bridge.starts != 0 or counted_bridge.connects != 0:
		push_error("VOICE_DISABLED_START_FAIL: disabled startup launched backend")
		manager.queue_free()
		quit(5)
		return
	manager.set_enabled(true)
	if not counted_bridge.backend_requested or counted_bridge.starts != 1 or counted_bridge.connects != 1:
		push_error("VOICE_REENABLE_FAIL: enabled Voice did not request backend")
		manager.queue_free()
		quit(6)
		return
	var disabled_pid := OS.create_process(python, arguments, false)
	if disabled_pid <= 0:
		push_error("VOICE_DISABLE_FAIL: could not start disposable child")
		manager.queue_free()
		quit(8)
		return
	counted_bridge.backend_pid = disabled_pid
	manager.set_enabled(false)
	for attempt in 40:
		if not OS.is_process_running(disabled_pid):
			break
		await create_timer(0.05).timeout
	var disabled_child_stopped := not OS.is_process_running(disabled_pid)
	_stop_test_child(disabled_pid)
	if counted_bridge.backend_requested or counted_bridge.starts != 1 or not disabled_child_stopped:
		push_error("VOICE_DISABLE_FAIL: disabled Voice can restart backend or retained its child")
		manager.queue_free()
		quit(7)
		return
	print("AURORA_VOICE_DISABLED_LIFECYCLE_OK")
	manager.queue_free()
	await process_frame
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
	# POSIX signal delivery is asynchronous; wait for the observed child state.
	for attempt in 40:
		if not OS.is_process_running(owned_pid):
			break
		await create_timer(0.05).timeout
	var owned_stopped := not OS.is_process_running(owned_pid)
	var unrelated_preserved := OS.is_process_running(unrelated_pid)
	_stop_test_child(owned_pid)
	_stop_test_child(unrelated_pid)
	if not owned_stopped or not unrelated_preserved:
		push_error("VOICE_CHILD_EXIT_FAIL: owned_stopped=%s unrelated_preserved=%s" % [owned_stopped, unrelated_preserved])
		quit(4)
		return
	print("AURORA_VOICE_OWNED_CHILD_EXIT_OK")
	quit(0)


func _stop_test_child(pid: int) -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
