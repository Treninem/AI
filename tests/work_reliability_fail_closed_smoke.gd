extends SceneTree

var _base := ""

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _store(name: String) -> AuroraWorkStore:
	var store := AuroraWorkStore.new()
	store.store_path = "%s/%s.json" % [_base, name]
	store.work_root = "%s/%s_projects" % [_base, name]
	root.add_child(store)
	return store

func _write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	file.close()
	return true

func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_base = "user://work_fail_closed_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var store := _store("state")
	if bool(store.recovery_status().get("blocked", true)):
		_fail("Clean WorkStore boot was recovery-blocked", 2)
		return
	var project := store.create_project("Fail closed", "recovery", "project-key")
	var project_id := str(project.get("id", ""))
	var task := store.create_task(project_id, "pause across restart", "", "task-key")
	var task_id := str(task.get("id", ""))
	if project_id.is_empty() or task_id.is_empty() or not store.pause_task(project_id, task_id):
		_fail("Failed to create and pause Work task", 3)
		return
	if not store.force_save():
		_fail("Failed to persist paused Work task", 4)
		return
	var committed_paused := _read_text(store.store_path)
	if committed_paused.is_empty():
		_fail("Committed Work state is empty", 5)
		return
	if not _write_text(store.store_path + ".tmp", JSON.stringify({"schema_version": AuroraWorkStore.SCHEMA_VERSION, "active_project_id": "stale", "projects": []})):
		_fail("Failed to stage stale Work temp", 6)
		return
	store.queue_free()
	await process_frame

	var restarted := _store("state")
	var paused := restarted.get_task(project_id, task_id)
	if str(paused.get("status", "")) != AuroraWorkStore.STATE_PAUSED:
		_fail("Paused Work task did not survive restart", 7)
		return
	if FileAccess.file_exists(restarted.store_path + ".tmp") or "discarded_stale_temp" not in restarted.recovery_notes:
		_fail("Valid primary did not discard stale temp deterministically", 8)
		return
	if not restarted.resume_task(project_id, task_id):
		_fail("Paused Work task could not resume safely after restart", 9)
		return
	if str(restarted.get_task(project_id, task_id).get("status", "")) != AuroraWorkStore.STATE_QUEUED:
		_fail("Resume after restart did not return task to queued", 10)
		return
	if not restarted.force_save():
		_fail("Failed to persist resumed Work task", 11)
		return
	var known_good := _read_text(restarted.store_path)
	if known_good.is_empty():
		_fail("Known-good Work state missing before corruption test", 12)
		return
	restarted.queue_free()
	await process_frame

	var corrupt_primary := "{\"schema_version\":3,\"projects\":["
	var corrupt_backup := "not-json-backup"
	if not _write_text("%s/state.json" % _base, corrupt_primary) or not _write_text("%s/state.json.bak" % _base, corrupt_backup):
		_fail("Failed to stage both-corrupt Work state", 13)
		return
	var blocked := _store("state")
	var status := blocked.recovery_status()
	if not bool(status.get("blocked", false)) or str(status.get("error", "")) != "unrecoverable_work_store":
		_fail("Both-corrupt Work state did not fail closed", 14)
		return
	if "primary_store_invalid" not in blocked.recovery_notes or "backup_store_invalid" not in blocked.recovery_notes or "unrecoverable_state_fail_closed" not in blocked.recovery_notes:
		_fail("Both-corrupt Work recovery diagnostics are incomplete", 15)
		return
	if not blocked.create_project("must not create").is_empty():
		_fail("Recovery-blocked WorkStore allowed creation of a new project", 16)
		return
	if blocked.force_save():
		_fail("Recovery-blocked WorkStore overwrote persisted corruption", 17)
		return
	if _read_text(blocked.store_path) != corrupt_primary or _read_text(blocked.store_path + ".bak") != corrupt_backup:
		_fail("Fail-closed WorkStore mutated unrecoverable persisted state", 18)
		return
	if not FileAccess.file_exists(blocked.store_path + ".corrupt"):
		_fail("Corrupt primary was not preserved for recovery diagnostics", 19)
		return

	if not _write_text(blocked.store_path + ".bak", known_good):
		_fail("Failed to stage valid backup recovery", 20)
		return
	blocked.reload_from_disk()
	if bool(blocked.recovery_status().get("blocked", true)) or not bool(blocked.recovery_status().get("recovered_from_backup", false)):
		_fail("Valid backup did not clear fail-closed Work recovery", 21)
		return
	if blocked.get_project(project_id).is_empty() or str(blocked.get_task(project_id, task_id).get("status", "")) != AuroraWorkStore.STATE_QUEUED:
		_fail("Valid backup recovery did not preserve Work lifecycle state", 22)
		return

	var malformed_structural := "{\"schema_version\":3,\"projects\":\"not-an-array\"}"
	if not _write_text(blocked.store_path, malformed_structural) or not _write_text(blocked.store_path + ".bak", corrupt_backup):
		_fail("Failed to stage structurally malformed Work state", 23)
		return
	blocked.reload_from_disk()
	if not bool(blocked.recovery_status().get("blocked", false)):
		_fail("Structurally malformed Work state did not fail closed", 24)
		return
	if not _write_text(blocked.store_path + ".bak", known_good):
		_fail("Failed to restore valid Work backup after malformed-state test", 25)
		return
	blocked.reload_from_disk()
	if bool(blocked.recovery_status().get("blocked", true)):
		_fail("WorkStore remained blocked after valid recovery material was restored", 26)
		return

	blocked.queue_free()
	print("AURORA_WORK_FAIL_CLOSED_SMOKE_OK stale_temp=discarded paused_restart=preserved both_corrupt=blocked backup_recovery=ok malformed=blocked")
	quit(0)
