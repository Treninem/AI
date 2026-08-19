class_name AuroraWorkStore
extends Node

const STORE_PATH := "user://work/workspaces.json"
const WORK_ROOT := "user://work/projects"

var projects: Array = []
var active_project_id := ""

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_ROOT))
	_load()

func create_project(title: String, instructions := "") -> Dictionary:
	var project_id := _new_id()
	var project := {
		"id": project_id,
		"title": title.strip_edges() if not title.strip_edges().is_empty() else "Новый проект",
		"instructions": instructions.strip_edges(),
		"files": [],
		"tasks": [],
		"created_at": Time.get_datetime_string_from_system(true),
		"updated_at": Time.get_datetime_string_from_system(true)
	}
	projects.push_front(project)
	active_project_id = project_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(project_dir(project_id)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(artifact_dir(project_id)))
	_save()
	return project.duplicate(true)

func all_projects() -> Array:
	return projects.duplicate(true)

func get_project(project_id: String) -> Dictionary:
	for project in projects:
		if str(project.get("id", "")) == project_id:
			return project.duplicate(true)
	return {}

func get_active_project() -> Dictionary:
	if active_project_id.is_empty() and not projects.is_empty():
		active_project_id = str(projects[0].get("id", ""))
	return get_project(active_project_id)

func set_active(project_id: String) -> bool:
	if get_project(project_id).is_empty():
		return false
	active_project_id = project_id
	_save()
	return true

func update_project(project_id: String, title: String, instructions: String) -> bool:
	for i in range(projects.size()):
		if str(projects[i].get("id", "")) != project_id:
			continue
		projects[i]["title"] = title.strip_edges() if not title.strip_edges().is_empty() else str(projects[i].get("title", "Проект"))
		projects[i]["instructions"] = instructions.strip_edges()
		projects[i]["updated_at"] = Time.get_datetime_string_from_system(true)
		_save()
		return true
	return false

func add_file(project_id: String, path: String) -> bool:
	var clean := path.strip_edges()
	if clean.is_empty():
		return false
	for i in range(projects.size()):
		if str(projects[i].get("id", "")) != project_id:
			continue
		var files: Array = projects[i].get("files", [])
		if clean not in files:
			files.append(clean)
		projects[i]["files"] = files
		projects[i]["updated_at"] = Time.get_datetime_string_from_system(true)
		_save()
		return true
	return false

func remove_file(project_id: String, path: String) -> bool:
	for i in range(projects.size()):
		if str(projects[i].get("id", "")) != project_id:
			continue
		var files: Array = projects[i].get("files", [])
		files.erase(path)
		projects[i]["files"] = files
		projects[i]["updated_at"] = Time.get_datetime_string_from_system(true)
		_save()
		return true
	return false

func create_task(project_id: String, prompt: String, output_name := "") -> Dictionary:
	var task := {
		"id": _new_id(),
		"prompt": prompt.strip_edges(),
		"status": "queued",
		"progress": 0,
		"message": "В очереди",
		"output_name": output_name.strip_edges(),
		"artifact_path": "",
		"result": "",
		"error": "",
		"created_at": Time.get_datetime_string_from_system(true),
		"updated_at": Time.get_datetime_string_from_system(true)
	}
	for i in range(projects.size()):
		if str(projects[i].get("id", "")) != project_id:
			continue
		var tasks: Array = projects[i].get("tasks", [])
		tasks.push_front(task)
		projects[i]["tasks"] = tasks
		projects[i]["updated_at"] = Time.get_datetime_string_from_system(true)
		_save()
		return task.duplicate(true)
	return {}

func update_task(project_id: String, task_id: String, patch: Dictionary) -> bool:
	for i in range(projects.size()):
		if str(projects[i].get("id", "")) != project_id:
			continue
		var tasks: Array = projects[i].get("tasks", [])
		for j in range(tasks.size()):
			if str(tasks[j].get("id", "")) != task_id:
				continue
			for key in patch.keys():
				tasks[j][key] = patch[key]
			tasks[j]["updated_at"] = Time.get_datetime_string_from_system(true)
			projects[i]["tasks"] = tasks
			projects[i]["updated_at"] = Time.get_datetime_string_from_system(true)
			_save()
			return true
	return false

func project_dir(project_id: String) -> String:
	return "%s/%s" % [WORK_ROOT, project_id]

func artifact_dir(project_id: String) -> String:
	return "%s/artifacts" % project_dir(project_id)

func _load() -> void:
	if not FileAccess.file_exists(STORE_PATH):
		return
	var file := FileAccess.open(STORE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	projects = parsed.get("projects", [])
	active_project_id = str(parsed.get("active_project_id", ""))

func _save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://work"))
	var file := FileAccess.open(STORE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"projects": projects, "active_project_id": active_project_id}, "  "))

func _new_id() -> String:
	return "%d_%d" % [Time.get_unix_time_from_system(), randi_range(100000, 999999)]
