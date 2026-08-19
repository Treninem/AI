class_name AuroraWorkManager
extends Node

signal task_progress(project_id: String, task_id: String, progress: int, message: String)
signal task_finished(project_id: String, task_id: String, artifact_path: String)
signal task_failed(project_id: String, task_id: String, message: String)

var store := AuroraWorkStore.new()
var running := false

func _ready() -> void:
	if store.get_parent() == null:
		add_child(store)

func run_task(project_id: String, prompt: String, output_name := "") -> Dictionary:
	if running:
		return {"ok": false, "error": "AuroraFox Work уже выполняет задачу"}
	var main := get_parent()
	if main == null:
		return {"ok": false, "error": "Главное окно AuroraFox недоступно"}
	var agent = main.get("agent")
	if not agent is AgentCore:
		return {"ok": false, "error": "AgentCore не подключён"}
	var project := store.get_project(project_id)
	if project.is_empty():
		return {"ok": false, "error": "Work-проект не найден"}
	var task := store.create_task(project_id, prompt, output_name)
	if task.is_empty():
		return {"ok": false, "error": "Не удалось создать Work-задачу"}
	var task_id := str(task.get("id", ""))
	running = true
	_update(project_id, task_id, 8, "Подготавливаю контекст проекта")
	var context := _build_context(project)
	_update(project_id, task_id, 22, "Проверяю инструкции и источники")
	var full_prompt := _compose_prompt(project, prompt, context, output_name)
	_update(project_id, task_id, 35, "AuroraFox выполняет многошаговую задачу")
	var result: String = await agent.run_task(full_prompt, [])
	if result.begins_with("Ошибка модели:"):
		store.update_task(project_id, task_id, {"status":"failed", "progress":100, "message":"Ошибка модели", "error":result})
		running = false
		task_failed.emit(project_id, task_id, result)
		return {"ok": false, "error": result, "task_id": task_id}
	_update(project_id, task_id, 82, "Сохраняю результат")
	var artifact_path := _write_artifact(project_id, task_id, output_name, prompt, result)
	if artifact_path.is_empty():
		store.update_task(project_id, task_id, {"status":"failed", "progress":100, "message":"Не удалось сохранить результат", "error":"artifact write failed"})
		running = false
		task_failed.emit(project_id, task_id, "Не удалось сохранить Work-результат")
		return {"ok": false, "error": "Не удалось сохранить Work-результат", "task_id": task_id}
	store.update_task(project_id, task_id, {
		"status":"completed",
		"progress":100,
		"message":"Готово",
		"result":result,
		"artifact_path":artifact_path
	})
	running = false
	task_progress.emit(project_id, task_id, 100, "Готово")
	task_finished.emit(project_id, task_id, artifact_path)
	return {"ok": true, "task_id": task_id, "result": result, "artifact_path": artifact_path}

func _update(project_id: String, task_id: String, progress: int, message: String) -> void:
	store.update_task(project_id, task_id, {"status":"running", "progress":progress, "message":message})
	task_progress.emit(project_id, task_id, progress, message)

func _build_context(project: Dictionary) -> String:
	var parts: Array[String] = []
	var instructions := str(project.get("instructions", "")).strip_edges()
	if not instructions.is_empty():
		parts.append("ИНСТРУКЦИИ ПРОЕКТА:\n" + instructions)
	var files: Array = project.get("files", [])
	if not files.is_empty():
		parts.append("СВЯЗАННЫЕ ФАЙЛЫ:\n- " + "\n- ".join(files))
	return "\n\n".join(parts)

func _compose_prompt(project: Dictionary, prompt: String, context: String, output_name: String) -> String:
	var artifact_hint := ""
	if not output_name.strip_edges().is_empty():
		artifact_hint = "\nЖелаемое имя результата: %s" % output_name.strip_edges()
	return """
РЕЖИМ AURORAFOX WORK.
Это долгосрочная многошаговая задача внутри постоянного рабочего пространства.
Работай до законченного результата, используй существующие инструменты AuroraFox, File Intelligence, память, индекс проекта и песочницу там, где это уместно.
Не теряй контекст проекта. Если задача требует файла, подготовь содержимое результата так, чтобы оно могло быть сохранено как законченный артефакт.

ПРОЕКТ: %s
%s

ЗАДАЧА:
%s
%s
""" % [str(project.get("title", "Work")), context, prompt.strip_edges(), artifact_hint]

func _write_artifact(project_id: String, task_id: String, output_name: String, prompt: String, result: String) -> String:
	var dir := store.artifact_dir(project_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var safe_name := output_name.strip_edges()
	if safe_name.is_empty():
		safe_name = "work_%s.md" % task_id
	elif safe_name.get_extension().is_empty():
		safe_name += ".md"
	safe_name = safe_name.replace("/", "_").replace("\\", "_").replace(":", "_")
	var path := "%s/%s" % [dir, safe_name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string("# AuroraFox Work\n\n## Задача\n\n%s\n\n## Результат\n\n%s\n" % [prompt.strip_edges(), result])
	return path
