extends SceneTree

func _init() -> void:
	var store := AuroraWorkStore.new()
	root.add_child(store)
	var project := store.create_project("Persistent Work", "Keep context")
	var project_id := str(project.get("id", ""))
	if project_id.is_empty():
		push_error("Work project id missing")
		quit(2)
		return
	if not store.add_file(project_id, "C:/AuroraFox/test.txt"):
		push_error("Work file linking failed")
		quit(3)
		return
	var task := store.create_task(project_id, "Long task", "result.md")
	if str(task.get("status", "")) != "queued":
		push_error("Work task creation failed")
		quit(4)
		return
	var task_id := str(task.get("id", ""))
	if not store.update_task(project_id, task_id, {"status":"completed", "progress":100, "result":"ok"}):
		push_error("Work task update failed")
		quit(5)
		return
	var reloaded := store.get_project(project_id)
	if reloaded.is_empty() or str((reloaded.get("tasks", []) as Array)[0].get("result", "")) != "ok":
		push_error("Work persisted project state invalid")
		quit(6)
		return
	store.queue_free()
	print("AURORA_WORK_STORE_SMOKE_OK")
	quit(0)
