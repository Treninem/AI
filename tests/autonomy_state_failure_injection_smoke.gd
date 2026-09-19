extends SceneTree

const STATE_PATH := "user://agent/autonomy_state.json"
const STATE_TEMP_PATH := STATE_PATH + ".tmp"
const STATE_BACKUP_PATH := STATE_PATH + ".bak"

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok

func _snapshot_files() -> Dictionary:
	var snapshot := {}
	for path in [STATE_PATH, STATE_TEMP_PATH, STATE_BACKUP_PATH]:
		if not FileAccess.file_exists(path):
			snapshot[path] = {"exists": false, "content": ""}
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			snapshot[path] = {"exists": true, "content": ""}
			continue
		snapshot[path] = {"exists": true, "content": file.get_as_text()}
		file.close()
	return snapshot

func _cleanup() -> void:
	for path in [STATE_TEMP_PATH, STATE_BACKUP_PATH, STATE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _restore(snapshot: Dictionary) -> void:
	_cleanup()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STATE_PATH.get_base_dir()))
	for path in [STATE_PATH, STATE_TEMP_PATH, STATE_BACKUP_PATH]:
		var saved: Dictionary = snapshot.get(path, {}) if snapshot.get(path, {}) is Dictionary else {}
		if not bool(saved.get("exists", false)):
			continue
		_write_text(path, str(saved.get("content", "")))

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var snapshot := _snapshot_files()
	_cleanup()
	if not _write_text(STATE_PATH, "{broken-primary"):
		_restore(snapshot)
		_fail("Could not create corrupt autonomy primary", 2)
		return
	if not _write_text(STATE_BACKUP_PATH, "{broken-backup"):
		_restore(snapshot)
		_fail("Could not create corrupt autonomy backup", 3)
		return

	var coordinator_script = load("res://agent/autonomous_coordinator.gd")
	if coordinator_script == null or not coordinator_script.can_instantiate():
		_restore(snapshot)
		_fail("Autonomous coordinator cannot be instantiated", 4)
		return
	var coordinator = coordinator_script.new()
	coordinator._state_recovery_blocked = false
	coordinator._load_state()
	if not bool(coordinator._state_recovery_blocked):
		coordinator.free()
		_restore(snapshot)
		_fail("Both-corrupt autonomy state did not fail closed", 5)
		return
	var cycle: Dictionary = await coordinator.run_autonomous_cycle()
	if bool(cycle.get("ok", true)) or str(cycle.get("stage", "")) != "state_recovery":
		coordinator.free()
		_restore(snapshot)
		_fail("Blocked autonomy state still allowed an autonomous cycle", 6)
		return
	if not FileAccess.file_exists(STATE_PATH):
		coordinator.free()
		_restore(snapshot)
		_fail("Corrupt recovery evidence disappeared instead of remaining diagnosable", 7)
		return

	coordinator.free()
	_restore(snapshot)
	print("AURORA_AUTONOMY_STATE_FAILURE_INJECTION_OK both_corrupt=blocked duplicate_cycle=prevented")
	quit(0)
