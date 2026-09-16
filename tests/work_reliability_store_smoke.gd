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

func _write_json(path: String, value) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  "))
	file.flush()
	file.close()
	return true

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_base = "user://work_reliability_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]

	# create -> save -> execute/progress -> restart -> interrupted recovery
	var store := _store("lifecycle")
	var project := store.create_project("Reliable Work", "local only", "project-key")
	var project_again := store.create_project("duplicate", "ignored", "project-key")
	if str(project.get("id", "")) != str(project_again.get("id", "")):
		_fail("Project idempotency failed", 2)
		return
	var project_id := str(project.get("id", ""))
	store.add_file(project_id, "C:/AuroraFox/input.txt")
	store.add_file(project_id, "C:/AuroraFox/input.txt")
	if (store.get_project(project_id).get("files", []) as Array).size() != 1:
		_fail("Project file deduplication failed", 3)
		return
	var task := store.create_task(project_id, "do work", "result.md", "task-key")
	var same_task := store.create_task(project_id, "do work twice", "other.md", "task-key")
	var task_id := str(task.get("id", ""))
	if task_id != str(same_task.get("id", "")):
		_fail("Task idempotency failed", 4)
		return
	if not store.start_task(project_id, task_id, "exec-1"):
		_fail("queued -> running rejected", 5)
		return
	store.update_task(project_id, task_id, {"progress": 42, "message": "working"})
	store.note_action(project_id, task_id, "project_apply_file", "exec-1:1", "unsafe")
	if not store.force_save():
		_fail("Work store save failed", 6)
		return
	store.queue_free()
	await process_frame

	var reloaded := _store("lifecycle")
	var recovered_task := reloaded.get_task(project_id, task_id)
	if str(recovered_task.get("status", "")) != AuroraWorkStore.STATE_INTERRUPTED:
		_fail("Running task was not marked interrupted after restart", 7)
		return
	if not bool(recovered_task.get("requires_user_action", false)):
		_fail("Unsafe uncertain action did not require user action", 8)
		return
	if str(recovered_task.get("attempt_retry_safety", "")) != "unsafe":
		_fail("Restart did not persist unsafe attempt safety", 42)
		return
	if reloaded.retry_task(project_id, task_id):
		_fail("Unsafe interrupted task was blindly retryable", 9)
		return

	# Defense in depth: a pending user-verification bit blocks direct RUNNING too.
	var direct_blocked := reloaded.create_task(project_id, "must verify")
	var direct_blocked_id := str(direct_blocked.get("id", ""))
	reloaded.update_task(project_id, direct_blocked_id, {"requires_user_action": true})
	if reloaded.start_task(project_id, direct_blocked_id, "must-not-run"):
		_fail("requires_user_action task entered running directly", 43)
		return

	# deterministic state machine, pause/resume/cancel/retry and terminal behavior.
	var safe := reloaded.create_task(project_id, "safe work", "", "safe-task")
	var safe_id := str(safe.get("id", ""))
	if not reloaded.pause_task(project_id, safe_id):
		_fail("queued -> paused rejected", 10)
		return
	if not reloaded.resume_task(project_id, safe_id):
		_fail("paused -> queued resume rejected", 11)
		return
	if not reloaded.start_task(project_id, safe_id, "exec-safe"):
		_fail("resumed task did not start", 12)
		return
	if int(reloaded.get_task(project_id, safe_id).get("attempts", 0)) != 1:
		_fail("Attempt counter incorrect", 13)
		return
	if not reloaded.fail_task(project_id, safe_id, "password=hunter2 token=verysecret123", true):
		_fail("running -> failed rejected", 14)
		return
	var failed := reloaded.get_task(project_id, safe_id)
	if str(failed.get("last_error", "")).contains("hunter2") or str(failed.get("last_error", "")).contains("verysecret123"):
		_fail("Secret leaked into Work error surface", 15)
		return
	reloaded.update_task(project_id, safe_id, {"last_action": "old", "last_action_id": "old:1", "last_action_retry_safety": "unsafe", "attempt_retry_safety": "unsafe"})
	if not reloaded.retry_task(project_id, safe_id):
		_fail("Safe failed task did not support explicit retry", 16)
		return
	var retried_meta := reloaded.get_task(project_id, safe_id)
	if str(retried_meta.get("attempt_retry_safety", "")) != "safe" or not str(retried_meta.get("last_action_id", "")).is_empty():
		_fail("Explicit retry did not reset previous attempt metadata", 44)
		return
	if not reloaded.start_task(project_id, safe_id, "exec-safe-2"):
		_fail("Retried task did not start", 17)
		return
	if not reloaded.complete_task(project_id, safe_id, "ok"):
		_fail("running -> completed rejected", 18)
		return
	if reloaded.transition_task(project_id, safe_id, AuroraWorkStore.STATE_RUNNING):
		_fail("completed -> running was incorrectly allowed", 19)
		return
	if reloaded.retry_task(project_id, safe_id):
		_fail("completed task was incorrectly retryable", 20)
		return
	var cancellable := reloaded.create_task(project_id, "cancel me")
	var cancel_id := str(cancellable.get("id", ""))
	if not reloaded.cancel_task(project_id, cancel_id):
		_fail("Queued cancellation failed", 21)
		return
	if str(reloaded.get_task(project_id, cancel_id).get("status", "")) != AuroraWorkStore.STATE_CANCELLED:
		_fail("Cancellation terminal state incorrect", 22)
		return

	# Legacy migration: whole-attempt metadata is authoritative. A legacy task
	# that explicitly says the whole attempt was safe can recover safely; if that
	# field is absent, last-action="safe" is not enough to prove earlier steps.
	var legacy_path := "%s/legacy.json" % _base
	var legacy_root := "%s/legacy_projects" % _base
	var duplicate_data := {
		"active_project_id": "stale-project",
		"projects": [
			{
				"id": "dup-project", "title": "A", "context": "legacy context", "files": ["a", "a"],
				"tasks": [
					{"id": "dup-task", "prompt": "one", "status": "running", "last_action_retry_safety": "safe", "attempt_retry_safety": "safe"},
					{"id": "dup-task", "prompt": "two", "status": "unknown"},
					{"id": "legacy-unknown", "prompt": "three", "status": "running", "last_action_retry_safety": "safe"},
					"corrupt-record"
				]
			},
			{"id": "dup-project", "title": "B", "files": [], "tasks": []},
			42
		]
	}
	if not _write_json(legacy_path, duplicate_data):
		_fail("Could not create migration fixture", 23)
		return
	var migrated := AuroraWorkStore.new()
	migrated.store_path = legacy_path
	migrated.work_root = legacy_root
	root.add_child(migrated)
	var migrated_projects := migrated.all_projects()
	if migrated_projects.size() != 2:
		_fail("Malformed project isolation/migration failed", 24)
		return
	var first: Dictionary = migrated_projects[0]
	var second: Dictionary = migrated_projects[1]
	if str(first.get("id", "")) == str(second.get("id", "")):
		_fail("Duplicate project IDs survived migration", 25)
		return
	var legacy_tasks: Array = first.get("tasks", [])
	if legacy_tasks.size() != 3 or str(legacy_tasks[0].get("id", "")) == str(legacy_tasks[1].get("id", "")):
		_fail("Duplicate/malformed task migration failed", 26)
		return
	if str(legacy_tasks[0].get("status", "")) != AuroraWorkStore.STATE_INTERRUPTED:
		_fail("Legacy running task recovery failed", 27)
		return
	if bool(legacy_tasks[0].get("requires_user_action", true)):
		_fail("Explicitly safe whole legacy attempt incorrectly requires user action", 28)
		return
	var unknown_legacy: Dictionary = legacy_tasks[2]
	if str(unknown_legacy.get("status", "")) != AuroraWorkStore.STATE_INTERRUPTED:
		_fail("Legacy running task without attempt metadata was not interrupted", 38)
		return
	if str(unknown_legacy.get("attempt_retry_safety", "")) != "unsafe" or not bool(unknown_legacy.get("requires_user_action", false)):
		_fail("Legacy running task without attempt metadata did not fail closed", 39)
		return
	if migrated.retry_task(str(first.get("id", "")), str(unknown_legacy.get("id", ""))):
		_fail("Legacy unknown running task was blindly retryable", 40)
		return
	if "legacy_attempt_retry_safety_unknown" not in migrated.recovery_notes:
		_fail("Legacy unknown attempt safety was not observable in recovery notes", 41)
		return
	if migrated.get_project(migrated.active_project_id).is_empty():
		_fail("Stale active project reference not repaired", 29)
		return

	# Corrupted/truncated primary recovers last known-good backup instead of losing all work.
	var resilient := _store("corruption")
	var resilient_project := resilient.create_project("Keep me")
	var resilient_id := str(resilient_project.get("id", ""))
	resilient.update_project(resilient_id, "Keep me updated", "backup checkpoint")
	var corrupt_path := resilient.store_path
	var backup_path := corrupt_path + ".bak"
	if not FileAccess.file_exists(backup_path):
		_fail("Atomic store backup was not created", 30)
		return
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	if corrupt_file == null:
		_fail("Could not corrupt primary fixture", 31)
		return
	corrupt_file.store_string("{\"projects\":[")
	corrupt_file.close()
	resilient.queue_free()
	await process_frame
	var recovered := _store("corruption")
	if not recovered.recovered_from_backup:
		_fail("Truncated primary did not recover backup", 32)
		return
	if recovered.all_projects().is_empty():
		_fail("Corruption recovery lost all projects", 33)
		return
	if not FileAccess.file_exists(corrupt_path + ".corrupt"):
		_fail("Corrupt primary was not preserved for diagnosis", 34)
		return

	# Stress: dozens of projects / hundreds of tasks with one batched durable save.
	var stress := _store("stress")
	stress.begin_batch()
	for p in range(20):
		var stress_project := stress.create_project("P-%d" % p, "context")
		var sid := str(stress_project.get("id", ""))
		for t in range(25):
			var item := stress.create_task(sid, "Task %d" % t, "", "p%d-t%d" % [p, t])
			if item.is_empty():
				_fail("Stress task creation failed", 35)
				return
			if t % 3 == 0:
				stress.update_task(sid, str(item.get("id", "")), {"progress": 10 + t})
	if not stress.end_batch():
		_fail("Stress store save failed", 36)
		return
	stress.queue_free()
	await process_frame
	var stress_loaded := _store("stress")
	var count := 0
	for item in stress_loaded.all_projects():
		count += (item.get("tasks", []) as Array).size()
	if stress_loaded.all_projects().size() != 20 or count != 500:
		_fail("Stress restart integrity failed: projects=%d tasks=%d" % [stress_loaded.all_projects().size(), count], 37)
		return

	print("AURORA_WORK_RELIABILITY_STORE_OK projects=20 tasks=500")
	quit(0)