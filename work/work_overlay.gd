class_name AuroraWorkOverlay
extends Node

var popup: PopupPanel
var manager: AuroraWorkManager
var project_select: OptionButton
var title_edit: LineEdit
var instructions_edit: TextEdit
var files_label: Label
var prompt_edit: TextEdit
var output_edit: LineEdit
var progress_bar: ProgressBar
var status_label: Label
var result_edit: TextEdit
var file_dialog: FileDialog
var run_button: Button

func _ready() -> void:
	if OS.get_name() == "Android":
		return
	await get_tree().process_frame
	manager = get_parent().get_node_or_null("WorkManager") as AuroraWorkManager
	if manager == null:
		return
	_build_ui()
	manager.task_progress.connect(_on_task_progress)
	manager.task_finished.connect(_on_task_finished)
	manager.task_failed.connect(_on_task_failed)

func show_work() -> void:
	if popup == null:
		return
	_refresh_projects()
	_fit_popup()
	popup.popup_centered()

func _fit_popup() -> void:
	var viewport := get_viewport().get_visible_rect().size
	popup.size = Vector2i(
		maxi(720, mini(1180, int(viewport.x - 48.0))),
		maxi(560, mini(780, int(viewport.y - 48.0)))
	)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 125
	add_child(layer)
	popup = PopupPanel.new()
	popup.name = "AuroraWorkPopup"
	popup.size = Vector2i(1180, 780)
	popup.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(popup)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	popup.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	var heading := Label.new()
	heading.text = "Работа AuroraFox"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color("f4f6ff"))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var new_project := Button.new()
	new_project.text = "Новый проект"
	new_project.pressed.connect(_create_project)
	header.add_child(new_project)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(func(): popup.hide())
	header.add_child(close)

	var body := HSplitContainer.new()
	body.name = "WorkSplit"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 300
	root.add_child(body)

	var left_scroll := ScrollContainer.new()
	left_scroll.name = "WorkProjectScroll"
	left_scroll.custom_minimum_size.x = 280
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 9)
	left_scroll.add_child(left)

	_add_label(left, "Рабочее пространство", 18)
	project_select = OptionButton.new()
	project_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	project_select.item_selected.connect(_on_project_selected)
	left.add_child(project_select)
	title_edit = LineEdit.new()
	title_edit.placeholder_text = "Название проекта"
	left.add_child(title_edit)
	instructions_edit = TextEdit.new()
	instructions_edit.placeholder_text = "Постоянные инструкции проекта"
	instructions_edit.custom_minimum_size.y = 120
	instructions_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	left.add_child(instructions_edit)
	var save_project := Button.new()
	save_project.text = "Сохранить инструкции"
	save_project.pressed.connect(_save_project)
	left.add_child(save_project)

	_add_label(left, "Источники", 18)
	files_label = Label.new()
	files_label.text = "Файлы не добавлены"
	files_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(files_label)
	var add_files := Button.new()
	add_files.text = "Добавить файлы"
	add_files.pressed.connect(func(): file_dialog.popup_centered_ratio(0.75))
	left.add_child(add_files)

	var right_scroll := ScrollContainer.new()
	right_scroll.name = "WorkTaskScroll"
	right_scroll.custom_minimum_size.x = 360
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 9)
	right_scroll.add_child(right)
	_add_label(right, "Длинная задача", 18)
	prompt_edit = TextEdit.new()
	prompt_edit.placeholder_text = "Опиши конечный результат. AuroraFox будет работать через AgentCore, память, инструменты и файлы проекта."
	prompt_edit.custom_minimum_size.y = 160
	prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	right.add_child(prompt_edit)
	output_edit = LineEdit.new()
	output_edit.placeholder_text = "Имя результата, например report.md (необязательно)"
	right.add_child(output_edit)

	var run_row := HBoxContainer.new()
	run_row.add_theme_constant_override("separation", 10)
	right.add_child(run_row)
	run_button = Button.new()
	run_button.text = "Запустить задачу"
	run_button.custom_minimum_size = Vector2(170, 44)
	run_button.pressed.connect(_run_work)
	run_row.add_child(run_button)
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.show_percentage = true
	run_row.add_child(progress_bar)

	status_label = Label.new()
	status_label.text = "Готово к работе"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("8ddfff"))
	right.add_child(status_label)
	_add_label(right, "Последний результат", 18)
	result_edit = TextEdit.new()
	result_edit.editable = false
	result_edit.custom_minimum_size.y = 170
	result_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	right.add_child(result_edit)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.files_selected.connect(_on_files_selected)
	add_child(file_dialog)

func _refresh_projects() -> void:
	project_select.clear()
	var projects := manager.store.all_projects()
	for project in projects:
		project_select.add_item(str(project.get("title", "Проект")))
		project_select.set_item_metadata(project_select.item_count - 1, str(project.get("id", "")))
	if projects.is_empty():
		_create_project()
		return
	var active := manager.store.active_project_id
	for i in range(project_select.item_count):
		if str(project_select.get_item_metadata(i)) == active:
			project_select.selected = i
			break
	_load_selected_project()

func _create_project() -> void:
	var project := manager.store.create_project("Новый проект", "")
	_refresh_projects()
	manager.store.set_active(str(project.get("id", "")))
	_load_selected_project()

func _on_project_selected(index: int) -> void:
	if index < 0:
		return
	manager.store.set_active(str(project_select.get_item_metadata(index)))
	_load_selected_project()

func _load_selected_project() -> void:
	var project := manager.store.get_active_project()
	if project.is_empty():
		return
	title_edit.text = str(project.get("title", ""))
	instructions_edit.text = str(project.get("instructions", ""))
	var files: Array = project.get("files", [])
	files_label.text = "Файлы не добавлены" if files.is_empty() else "• " + "\n• ".join(files)
	var tasks: Array = project.get("tasks", [])
	if not tasks.is_empty():
		var latest: Dictionary = tasks[0]
		progress_bar.value = float(latest.get("progress", 0))
		status_label.text = str(latest.get("message", latest.get("status", "")))
		result_edit.text = str(latest.get("result", ""))

func _save_project() -> void:
	var id := manager.store.active_project_id
	if id.is_empty():
		return
	manager.store.update_project(id, title_edit.text, instructions_edit.text)
	_refresh_projects()
	status_label.text = "Инструкции проекта сохранены"

func _on_files_selected(paths: PackedStringArray) -> void:
	var id := manager.store.active_project_id
	if id.is_empty():
		return
	for path in paths:
		manager.store.add_file(id, path)
	_load_selected_project()
	status_label.text = "Источники добавлены в проект"

func _run_work() -> void:
	var prompt := prompt_edit.text.strip_edges()
	if prompt.is_empty():
		status_label.text = "Сначала опиши задачу"
		return
	_save_project()
	run_button.disabled = true
	progress_bar.value = 2
	status_label.text = "Запускаю задачу AuroraFox…"
	var result: Dictionary = await manager.run_task(manager.store.active_project_id, prompt, output_edit.text)
	run_button.disabled = false
	if result.get("ok", false):
		result_edit.text = str(result.get("result", ""))
		status_label.text = "Готово • %s" % str(result.get("artifact_path", ""))
	else:
		status_label.text = str(result.get("error", "Ошибка выполнения задачи"))

func _on_task_progress(_project_id: String, _task_id: String, progress: int, message: String) -> void:
	progress_bar.value = progress
	status_label.text = message

func _on_task_finished(_project_id: String, _task_id: String, artifact_path: String) -> void:
	progress_bar.value = 100
	status_label.text = "Готово • %s" % artifact_path
	_load_selected_project()

func _on_task_failed(_project_id: String, _task_id: String, message: String) -> void:
	progress_bar.value = 100
	status_label.text = message

func _add_label(parent: Control, text: String, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("f4f6ff"))
	parent.add_child(label)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.03, 0.055, 1.0)
	style.border_color = Color(0.38, 0.65, 1.0, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.72)
	style.shadow_size = 18
	return style
