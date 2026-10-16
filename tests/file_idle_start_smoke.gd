extends SceneTree

class FileStartProbe extends FileIntelligenceClient:
	var start_attempts := 0

	func _start_backend_if_installed() -> void:
		start_attempts += 1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var probe := FileStartProbe.new()
	root.add_child(probe)
	await process_frame
	if probe.start_attempts != 0:
		push_error("File backend started before any file operation")
		quit(1)
		return
	if OS.get_name() == "Windows":
		var applied := probe.apply_owner_limits({"client_health_timeout_seconds": 4}, false, true)
		if not bool(applied.get("ok", false)) or probe.start_attempts != 0:
			push_error("Changing File limits started an idle backend")
			quit(2)
			return
		probe.restart_backend()
		if probe.start_attempts != 1:
			push_error("Explicit File backend restart no longer starts it")
			quit(3)
			return
	var listener := TCPServer.new()
	if listener.listen(FileIntelligenceClient.BACKEND_PORT, "127.0.0.1") != OK:
		push_error("Synthetic File backend port is unavailable")
		quit(4)
		return
	probe.backend_pid = OS.get_process_id()
	var ready := await probe._wait_for_backend_ready(false)
	probe.backend_pid = 0
	listener.stop()
	if not ready:
		push_error("File backend readiness probe missed a listening local service")
		quit(5)
		return
	probe.queue_free()
	await process_frame
	print("AURORA_FILE_IDLE_START_OK")
	quit(0)
