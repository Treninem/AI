class_name AuroraWorkStore
extends Node

const STORE_PATH := "user://work/workspaces.json"
const WORK_ROOT := "user://work/projects"
const SCHEMA_VERSION := 2

const STATE_QUEUED := "queued"
const STATE_RUNNING := "running"
const STATE_PAUSED := "paused"
const STATE_COMPLETED := "completed"
const STATE_FAILED := "failed"
const STATE_CANCELLED := "cancelled"
const STATE_INTERRUPTED := "interrupted"
const STATE_PARTIAL := "partially_completed"

const VALID_STATES := [
	STATE_QUEUED,
	STATE_RUNNING,
	STATE_PAUSED,
	STATE_COMPLETED,
	STATE_FAILED,
	STATE_CANCELLED,
	STATE_INTERRUPTED,
	STATE_PARTIAL,
]

const VALID_TRANSITIONS := {
	STATE_QUEUED: [STATE_RUNNING, STATE_PAUSED, STATE_COMPLETED, STATE_CANCELLED, STATE_FAILED],
	STATE_RUNNING: [STATE_PAUSED, STATE_COMPLETED, STATE_FAILED, STATE_CANCELLED, STATE_INTERRUPTED, STATE_PARTIAL],
	STATE_PAUSED: [STATE_QUEUED, STATE_RUNNING, STATE_CANCELLED, STATE_INTERRUPTED],
	STATE_COMPLETED: [],
	STATE_FAILED: [],
	STATE_CANCELLED: [],
	STATE_INTERRUPTED: [STATE_PAUSED, STATE_CANCELLED],
	STATE_PARTIAL: [STATE_COMPLETED, STATE_CANCELLED],
}

const RETRYABLE_STATES := [STATE_FAILED, STATE_CANCELLED, STATE_INTERRUPTED, STATE_PARTIAL]
const PROTECTED_TASK_KEYS := ["id", "project_id", "created_at", "attempts", "status"]
const MAX_ERROR_CHARS := 2048
const MAX_SUMMARY_CHARS := 4096

var projects: Array = []
var active_project_id := ""
var store_path := STORE_PATH
var work_root := WORK_ROOT
var recovered_from_backup := false
var recovery_notes: Array[String] = []
var _batch_depth := 0
var _dirty := false

func _ready() -> void:
	_ensure_directories()
	_load()

func create_project(title: String, instructions := "", idempotency_key: String = "") -> Dictionary:
	var clean_key := idempotency_key.strip_edges()
	if not clean_key.is_empty():
		for existing in projects:
			if existing is Dictionary and str(existing.get("idempotency_key", "")) == clean_key:
				return (existing as Dictionary).duplicate(true)
	var now := _now()
	var project := {
		"id": _new_id("project"),
		"title": title.strip_edges() if not title.strip_edges().is_empty() else "Новый проект",
		"instructions": str(instructions).strip_edges(),
		"files": [],
		"tasks": [],
		"idempotency_key": clean_key,
		"created_at": now,
		"updated_at": now,
	}
	projects.push_front(project)
	active_project_id = str(project["id"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(project_dir(active_project_id)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(artifact_dir(active_project_id)))
	_mark_dirty()
	return project.duplicate(true)

func all_projects() -> Array:
	return projects.duplicate(true)

func get_project(project_id: String) -> Dictionary:
	var index := _project_index(project_id)
	if index < 0:
		return {}
	return (projects[index] as Dictionary).duplicate(true)

func get_active_project() -> Dictionary:
	if active_project_id.is_empty() and not projects.is_empty():
		active_project_id = str(projects[0].get("id", ""))
	return get_project(active_project_id)

func active_project() -> Dictionary:
	return get_active_project()

func set_active(project_id: String) -> bool:
	if _project_index(project_id) < 0:
		return false
	active_project_id = project_id
	_mark_dirty()
	return true

func update_project(project_id: String, title_or_patch, instructions: String = "") -> bool:
	var index := _project_index(project_id)
	if index < 0:
		return false
	var project: Dictionary = projects[index]
	if title_or_patch is Dictionary:
		var patch: Dictionary = title_or_patch
		for key in patch.keys():
			var key_text := str(key)
			if key_text in ["id", "created_at", "tasks"]:
				continue
			project[key_text] = patch[key]
	else:
		var title := str(title_or_patch).strip_edges()
		if not title.is_empty():
			project["title"] = title
		project["instructions"] = instructions.strip_edges()
	project["updated_at"] = _now()
	projects[index] = project
	_mark_dirty()
	return true

func add_file(project_id: String, path: String) -> bool:
	var index := _project_index(project_id)
	if index < 0:
		return false
	var normalized := path.strip_edges()
	if normalized.is_empty():
		return false
	var project: Dictionary = projects[index]
	var files: Array = project.get("files", [])
	if normalized not in files:
		files.append(normalized)
	project["files"] = files
	project["updated_at"] = _now()
	projects[index] = project
	_mark_dirty()
	return true

func remove_file(project_id: String, path: String) -> bool:
	var index := _project_index(project_id)
	if index < 0:
		return false
	var project: Dictionary = projects[index]
	var files: Array = project.get("files", [])
	files.erase(path)
	project["files"] = files
	project["updated_at"] = _now()
	projects[index] = project
	_mark_dirty()
	return true

func create_task(project_id: String, prompt: String, output_name := "", idempotency_key: String = "") -> Dictionary:
	var project_index := _project_index(project_id)
	if project_index < 0:
		return {}
	var project: Dictionary = projects[project_index]
	var tasks: Array = project.get("tasks", [])
	var clean_key := idempotency_key.strip_edges()
	if not clean_key.is_empty():
		for existing in tasks:
			if existing is Dictionary and str(existing.get("idempotency_key", "")) == clean_key:
				return (existing as Dictionary).duplicate(true)
	var now := _now()
	var task := {
		"id": _new_id("task"),
		"project_id": project_id,
		"prompt": prompt.strip_edges(),
		"status": STATE_QUEUED,
		"progress": 0,
		"message": "В очереди",
		"output_name": str(output_name).strip_edges(),
		"artifact_path": "",
		"result": "",
		"result_summary": "",
		"error": "",
		"last_error": "",
		"last_action": "",
		"last_action_id": "",
		"last_action_retry_safety": "safe",
		"requires_user_action": false,
		"cancel_requested": false,
		"retryable": true,
		"attempts": 0,
		"execution_id": "",
		"idempotency_key": clean_key,
		"created_at": now,
		"started_at": "",
		"finished_at": "",
		"updated_at": now,
	}
	tasks.push_front(task)
	project["tasks"] = tasks
	project["updated_at"] = now
	projects[project_index] = project
	_mark_dirty()
	return task.duplicate(true)

func get_task(project_id: String, task_id: String) -> Dictionary:
	var location := _task_location(project_id, task_id)
	if location.is_empty():
		return {}
	var project: Dictionary = projects[int(location["project_index"])]
	var tasks: Array = project.get("tasks", [])
	return (tasks[int(location["task_index"])] as Dictionary).duplicate(true)

func update_task(project_id: String, task_id: String, patch: Dictionary) -> bool:
	var location := _task_location(project_id, task_id)
	if location.is_empty():
		return false
	var current := get_task(project_id, task_id)
	if patch.has("status"):
		var new_state := str(patch.get("status", ""))
		if new_state != str(current.get("status", STATE_QUEUED)):
			var rest := patch.duplicate(true)
			rest.erase("status")
			return transition_task(project_id, task_id, new_state, rest, false)
	return _patch_task(location, patch)

func transition_task(project_id: String, task_id: String, new_state: String, patch: Dictionary = {}, explicit_retry: bool = false) -> bool:
	if new_state not in VALID_STATES:
		return false
	var location := _task_location(project_id, task_id)
	if location.is_empty():
		return false
	var project_index := int(location["project_index"])
	var task_index := int(location["task_index"])
	var project: Dictionary = projects[project_index]
	var tasks: Array = project.get("tasks", [])
	var task: Dictionary = tasks[task_index]
	var old_state := str(task.get("status", STATE_QUEUED))
	if old_state == new_state:
		return _patch_task(location, patch)
	if explicit_retry:
		if old_state not in RETRYABLE_STATES or new_state != STATE_QUEUED:
			return false
	else:
		var allowed: Array = VALID_TRANSITIONS.get(old_state, [])
		if new_state not in allowed:
			return false

	var now := _now()
	task["status"] = new_state
	task["updated_at"] = now
	if new_state == STATE_RUNNING:
		task["attempts"] = int(task.get("attempts", 0)) + 1
		task["started_at"] = now
		task["finished_at"] = ""
		task["cancel_requested"] = false
		task["requires_user_action"] = false
	elif new_state in [STATE_COMPLETED, STATE_FAILED, STATE_CANCELLED, STATE_INTERRUPTED, STATE_PARTIAL]:
		task["finished_at"] = now
	if explicit_retry:
		task["progress"] = 0
		task["message"] = "Queued for retry"
		task["error"] = ""
		task["last_error"] = ""
		task["finished_at"] = ""
		task["execution_id"] = ""
		task["cancel_requested"] = false

	_apply_safe_patch(task, patch)
	tasks[task_index] = task
	project["tasks"] = tasks
	project["updated_at"] = now
	projects[project_index] = project
	_mark_dirty()
	return true

func start_task(project_id: String, task_id: String, execution_id: String) -> bool:
	var task := get_task(project_id, task_id)
	return transition_task(project_id, task_id, STATE_RUNNING, {
		"execution_id": execution_id,
		"message": "Running",
		"progress": maxi(1, int(task.get("progress", 0))),
	}, false)

func pause_task(project_id: String, task_id: String, message: String = "Paused") -> bool:
	return transition_task(project_id, task_id, STATE_PAUSED, {"message": message}, false)

func resume_task(project_id: String, task_id: String) -> bool:
	var task := get_task(project_id, task_id)
	if task.is_empty():
		return false
	var state := str(task.get("status", ""))
	if state == STATE_PAUSED:
		return transition_task(project_id, task_id, STATE_QUEUED, {"message": "Queued to resume"}, false)
	if state == STATE_INTERRUPTED and not bool(task.get("requires_user_action", false)):
		return retry_task(project_id, task_id)
	return false

func cancel_task(project_id: String, task_id: String, message: String = "Cancelled") -> bool:
	var task := get_task(project_id, task_id)
	if task.is_empty():
		return false
	if str(task.get("status", "")) == STATE_RUNNING:
		return _patch_task(_task_location(project_id, task_id), {"cancel_requested": true, "message": "Cancellation requested"})
	return transition_task(project_id, task_id, STATE_CANCELLED, {"message": message}, false)

func finalize_cancel(project_id: String, task_id: String, message: String = "Cancelled") -> bool:
	return transition_task(project_id, task_id, STATE_CANCELLED, {"message": message, "cancel_requested": true}, false)

func retry_task(project_id: String, task_id: String) -> bool:
	var task := get_task(project_id, task_id)
	if task.is_empty() or bool(task.get("requires_user_action", false)):
		return false
	return transition_task(project_id, task_id, STATE_QUEUED, {}, true)

func fail_task(project_id: String, task_id: String, error_text: String, retryable: bool = true) -> bool:
	var task := get_task(project_id, task_id)
	if task.is_empty():
		return false
	var state := str(task.get("status", ""))
	if state not in [STATE_QUEUED, STATE_RUNNING]:
		return false
	var clean := _redact(error_text).substr(0, MAX_ERROR_CHARS)
	return transition_task(project_id, task_id, STATE_FAILED, {
		"error": clean,
		"last_error": clean,
		"message": "Failed",
		"progress": int(task.get("progress", 0)),
		"retryable": retryable,
	}, false)

func interrupt_task(project_id: String, task_id: String, reason: String, requires_user_action: bool = false) -> bool:
	var clean := _redact(reason).substr(0, MAX_ERROR_CHARS)
	return transition_task(project_id, task_id, STATE_INTERRUPTED, {
		"last_error": clean,
		"error": clean,
		"message": "Interrupted",
		"requires_user_action": requires_user_action,
	}, false)

func mark_partial(project_id: String, task_id: String, summary: String, requires_user_action: bool = false) -> bool:
	return transition_task(project_id, task_id, STATE_PARTIAL, {
		"result_summary": _redact(summary).substr(0, MAX_SUMMARY_CHARS),
		"message": "Partially completed",
		"requires_user_action": requires_user_action,
	}, false)

func complete_task(project_id: String, task_id: String, result: String, artifact_path: String = "") -> bool:
	return transition_task(project_id, task_id, STATE_COMPLETED, {
		"progress": 100,
		"message": "Completed",
		"result": result,
		"result_summary": _redact(result).substr(0, MAX_SUMMARY_CHARS),
		"artifact_path": artifact_path,
		"error": "",
		"last_error": "",
	}, false)

func note_action(project_id: String, task_id: String, action_name: String, action_id: String, retry_safety: String) -> bool:
	var safety := retry_safety if retry_safety in ["safe", "unsafe"] else "unsafe"
	return update_task(project_id, task_id, {
		"last_action": action_name.substr(0, 256),
		"last_action_id": action_id.substr(0, 256),
		"last_action_retry_safety": safety,
	})

func project_dir(project_id: String) -> String:
	return "%s/%s" % [work_root, project_id]

func artifact_dir(project_id: String) -> String:
	return "%s/artifacts" % project_dir(project_id)

func begin_batch() -> void:
	_batch_depth += 1

func end_batch() -> bool:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth == 0 and _dirty:
		return _save()
	return true

func force_save() -> bool:
	return _save()

func reload_from_disk() -> void:
	_load()

func _patch_task(location: Dictionary, patch: Dictionary) -> bool:
	if location.is_empty():
		return false
	var project_index := int(location["project_index"])
	var task_index := int(location["task_index"])
	var project: Dictionary = projects[project_index]
	var tasks: Array = project.get("tasks", [])
	var task: Dictionary = tasks[task_index]
	_apply_safe_patch(task, patch)
	task["updated_at"] = _now()
	tasks[task_index] = task
	project["tasks"] = tasks
	project["updated_at"] = task["updated_at"]
	projects[project_index] = project
	_mark_dirty()
	return true

func _apply_safe_patch(task: Dictionary, patch: Dictionary) -> void:
	for key in patch.keys():
		var key_text := str(key)
		if key_text in PROTECTED_TASK_KEYS:
			continue
		var value = patch[key]
		if key_text in ["error", "last_error", "message"]:
			value = _redact(str(value)).substr(0, MAX_ERROR_CHARS)
		elif key_text in ["result_summary", "last_action"]:
			value = _redact(str(value)).substr(0, MAX_SUMMARY_CHARS)
		elif key_text == "progress":
			value = clampi(int(value), 0, 100)
		task[key_text] = value

func _project_index(project_id: String) -> int:
	for i in range(projects.size()):
		var project = projects[i]
		if project is Dictionary and str(project.get("id", "")) == project_id:
			return i
	return -1

func _task_location(project_id: String, task_id: String) -> Dictionary:
	var project_index := _project_index(project_id)
	if project_index < 0:
		return {}
	var project: Dictionary = projects[project_index]
	var tasks: Array = project.get("tasks", [])
	for task_index in range(tasks.size()):
		var task = tasks[task_index]
		if task is Dictionary and str(task.get("id", "")) == task_id:
			return {"project_index": project_index, "task_index": task_index}
	return {}

func _ensure_directories() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(store_path.get_base_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(work_root))

func _load() -> void:
	projects = []
	active_project_id = ""
	recovered_from_backup = false
	recovery_notes.clear()
	_ensure_directories()
	var loaded := _read_store(store_path)
	if loaded.is_empty() and FileAccess.file_exists(store_path):
		recovery_notes.append("primary_store_invalid")
		_preserve_corrupt_primary()
		loaded = _read_store(_backup_path())
		if not loaded.is_empty():
			recovered_from_backup = true
			recovery_notes.append("recovered_from_backup")
	elif loaded.is_empty() and FileAccess.file_exists(_backup_path()):
		loaded = _read_store(_backup_path())
		if not loaded.is_empty():
			recovered_from_backup = true
			recovery_notes.append("primary_missing_recovered_from_backup")
	if loaded.is_empty():
		return
	var migrated := _sanitize_loaded(loaded)
	if migrated or recovered_from_backup:
		_save()

func _read_store(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	return parsed

func _sanitize_loaded(data: Dictionary) -> bool:
	var migrated := int(data.get("schema_version", 1)) != SCHEMA_VERSION
	var source_projects = data.get("projects", [])
	if not source_projects is Array:
		recovery_notes.append("projects_not_array")
		source_projects = []
		migrated = true
	var used_project_ids := {}
	var used_task_ids := {}
	var clean_projects: Array = []
	for raw_project in source_projects:
		if not raw_project is Dictionary:
			recovery_notes.append("dropped_invalid_project")
			migrated = true
			continue
		var clean := _sanitize_project(raw_project, used_project_ids, used_task_ids)
		if clean.is_empty():
			recovery_notes.append("dropped_invalid_project")
			migrated = true
			continue
		if bool(clean.get("_migrated", false)):
			migrated = true
		clean.erase("_migrated")
		clean_projects.append(clean)
	projects = clean_projects
	active_project_id = str(data.get("active_project_id", ""))
	if _project_index(active_project_id) < 0:
		active_project_id = str(projects[0].get("id", "")) if not projects.is_empty() else ""
		migrated = true
	for project in projects:
		var project_id := str(project.get("id", ""))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(project_dir(project_id)))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(artifact_dir(project_id)))
	return migrated

func _sanitize_project(raw: Dictionary, used_project_ids: Dictionary, used_task_ids: Dictionary) -> Dictionary:
	var migrated := false
	var project_id := str(raw.get("id", "")).strip_edges()
	if project_id.is_empty() or used_project_ids.has(project_id):
		project_id = _new_id("project")
		migrated = true
	used_project_ids[project_id] = true
	var files: Array = []
	var seen_files := {}
	var raw_files = raw.get("files", [])
	if raw_files is Array:
		for item in raw_files:
			var path := str(item).strip_edges()
			if not path.is_empty() and not seen_files.has(path):
				seen_files[path] = true
				files.append(path)
	else:
		migrated = true
	var tasks: Array = []
	var raw_tasks = raw.get("tasks", [])
	if raw_tasks is Array:
		for raw_task in raw_tasks:
			if not raw_task is Dictionary:
				migrated = true
				continue
			var task := _sanitize_task(raw_task, project_id, used_task_ids)
			if bool(task.get("_migrated", false)):
				migrated = true
			task.erase("_migrated")
			tasks.append(task)
	else:
		migrated = true
	var created := str(raw.get("created_at", _now()))
	return {
		"id": project_id,
		"title": str(raw.get("title", "Новый проект")),
		"instructions": str(raw.get("instructions", raw.get("context", ""))),
		"files": files,
		"tasks": tasks,
		"idempotency_key": str(raw.get("idempotency_key", "")),
		"created_at": created,
		"updated_at": str(raw.get("updated_at", created)),
		"_migrated": migrated,
	}

func _sanitize_task(raw: Dictionary, project_id: String, used_task_ids: Dictionary) -> Dictionary:
	var migrated := false
	var task_id := str(raw.get("id", "")).strip_edges()
	if task_id.is_empty() or used_task_ids.has(task_id):
		task_id = _new_id("task")
		migrated = true
	used_task_ids[task_id] = true
	var state := str(raw.get("status", STATE_QUEUED))
	if state not in VALID_STATES:
		state = STATE_FAILED
		migrated = true
	var retry_safety := str(raw.get("last_action_retry_safety", "safe"))
	if retry_safety not in ["safe", "unsafe"]:
		retry_safety = "unsafe"
		migrated = true
	var requires_user_action := bool(raw.get("requires_user_action", false))
	var last_error := _redact(str(raw.get("last_error", raw.get("error", "")))).substr(0, MAX_ERROR_CHARS)
	if state == STATE_RUNNING:
		state = STATE_INTERRUPTED
		last_error = "Application restarted while this task was running. No action was replayed automatically."
		requires_user_action = retry_safety == "unsafe"
		migrated = true
	var created := str(raw.get("created_at", _now()))
	return {
		"id": task_id,
		"project_id": project_id,
		"prompt": str(raw.get("prompt", "")),
		"status": state,
		"progress": clampi(int(raw.get("progress", 0)), 0, 100),
		"message": _redact(str(raw.get("message", ""))).substr(0, MAX_ERROR_CHARS),
		"output_name": str(raw.get("output_name", "")),
		"artifact_path": str(raw.get("artifact_path", "")),
		"result": str(raw.get("result", "")),
		"result_summary": _redact(str(raw.get("result_summary", ""))).substr(0, MAX_SUMMARY_CHARS),
		"error": last_error,
		"last_error": last_error,
		"last_action": _redact(str(raw.get("last_action", ""))).substr(0, MAX_SUMMARY_CHARS),
		"last_action_id": str(raw.get("last_action_id", "")),
		"last_action_retry_safety": retry_safety,
		"requires_user_action": requires_user_action,
		"cancel_requested": false,
		"retryable": bool(raw.get("retryable", true)),
		"attempts": maxi(0, int(raw.get("attempts", 0))),
		"execution_id": "" if state == STATE_INTERRUPTED else str(raw.get("execution_id", "")),
		"idempotency_key": str(raw.get("idempotency_key", "")),
		"created_at": created,
		"started_at": str(raw.get("started_at", "")),
		"finished_at": str(raw.get("finished_at", "")),
		"updated_at": str(raw.get("updated_at", created)),
		"_migrated": migrated,
	}

func _mark_dirty() -> void:
	_dirty = true
	if _batch_depth == 0:
		_save()

func _save() -> bool:
	_ensure_directories()
	var data := {
		"schema_version": SCHEMA_VERSION,
		"active_project_id": active_project_id,
		"projects": projects,
		"saved_at": _now(),
	}
	var tmp := _temp_path()
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.flush()
	file.close()
	var verified := _read_store(tmp)
	if verified.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	var primary_abs := ProjectSettings.globalize_path(store_path)
	var backup_abs := ProjectSettings.globalize_path(_backup_path())
	var tmp_abs := ProjectSettings.globalize_path(tmp)
	if FileAccess.file_exists(store_path):
		var primary_data := _read_store(store_path)
		if not primary_data.is_empty():
			if FileAccess.file_exists(_backup_path()):
				DirAccess.remove_absolute(backup_abs)
			if DirAccess.copy_absolute(primary_abs, backup_abs) != OK:
				DirAccess.remove_absolute(tmp_abs)
				return false
		if DirAccess.remove_absolute(primary_abs) != OK:
			DirAccess.remove_absolute(tmp_abs)
			return false
	var rename_error := DirAccess.rename_absolute(tmp_abs, primary_abs)
	if rename_error != OK:
		if not FileAccess.file_exists(store_path) and FileAccess.file_exists(_backup_path()):
			DirAccess.copy_absolute(backup_abs, primary_abs)
		return false
	_dirty = false
	return true

func _preserve_corrupt_primary() -> void:
	if not FileAccess.file_exists(store_path):
		return
	var source := ProjectSettings.globalize_path(store_path)
	var target := ProjectSettings.globalize_path(store_path + ".corrupt")
	if FileAccess.file_exists(store_path + ".corrupt"):
		DirAccess.remove_absolute(target)
	DirAccess.copy_absolute(source, target)

func _backup_path() -> String:
	return store_path + ".bak"

func _temp_path() -> String:
	return store_path + ".tmp"

func _new_id(prefix: String) -> String:
	var millis := int(Time.get_unix_time_from_system() * 1000.0)
	var ticks := Time.get_ticks_usec()
	var random_part := randi_range(0x100000, 0x7fffffff)
	return "%s_%d_%d_%x" % [prefix, millis, ticks, random_part]

func _now() -> String:
	return Time.get_datetime_string_from_system(true)

func _redact(text: String) -> String:
	if text.is_empty():
		return text
	var value := text
	var secret_regex := RegEx.new()
	if secret_regex.compile("(?i)(password|passwd|token|api[_-]?key|authorization|cookie|private[_-]?key)\\s*[:=]\\s*[^\\s,;]+") == OK:
		value = secret_regex.sub(value, "$1=[REDACTED]", true)
	var bearer_regex := RegEx.new()
	if bearer_regex.compile("(?i)bearer\\s+[A-Za-z0-9._~+/-]{8,}") == OK:
		value = bearer_regex.sub(value, "Bearer [REDACTED]", true)
	return value
