class_name AuroraFileSetupWizard
extends Node

const STATE_PATH := "user://aurora_file_setup_state.json"

var popup: PopupPanel
var progress: ProgressBar
var stage_label: Label
var detail_label: Label
var install_button: Button
var setup_pid := 0
var poll_timer := 0.0

func _ready() -> void:
	if OS.get_name() != "Windows": return
	_build_ui()
	set_process(true)
	call_deferred("_connect_manager")

func _connect_manager() -> void:
	var main := get_parent()
	if main == null: return
	var manager = main.get("attachments")
	if manager is AttachmentManager and not manager.file_setup_required.is_connected(show_setup):
		manager.file_setup_required.connect(show_setup)

func _process(delta: float) -> void:
	if setup_pid <= 0: return
	poll_timer -= delta
	if poll_timer <= 0.0:
		poll_timer = 0.35
		_read_state()

func show_setup() -> void:
	if OS.get_name() != "Windows" or popup == null: return
	popup.popup_centered()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 92
	add_child(layer)
	popup = PopupPanel.new()
	popup.size = Vector2i(650, 360)
	layer.add_child(popup)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	popup.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Подготовка File Intelligence"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var description := Label.new()
	description.text = "Локальные парсеры нужны для реального чтения PDF, DOCX, XLSX, PPTX, изображений, аудио, видео и архивов. Системный Python не требуется."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)

	stage_label = Label.new()
	stage_label.text = "File Intelligence ещё не подготовлен"
	stage_label.add_theme_font_size_override("font_size", 18)
	box.add_child(stage_label)

	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = 100
	progress.value = 0
	progress.show_percentage = true
	progress.custom_minimum_size.y = 28
	box.add_child(progress)

	detail_label = Label.new()
	detail_label.text = "Установка выполняется в отдельное локальное окружение AuroraFox."
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	var later := Button.new()
	later.text = "Позже"
	later.pressed.connect(func(): popup.hide())
	row.add_child(later)
	install_button = Button.new()
	install_button.text = "Подготовить File Intelligence"
	install_button.pressed.connect(_start_install)
	row.add_child(install_button)

func _start_install() -> void:
	if setup_pid > 0: return
	var installer := _installer_path()
	if installer.is_empty():
		stage_label.text = "Установщик не найден"
		detail_label.text = "В Windows-пакете должен находиться file_intelligence/install_files.ps1."
		return
	var state_abs := ProjectSettings.globalize_path(STATE_PATH)
	if FileAccess.file_exists(STATE_PATH): DirAccess.remove_absolute(state_abs)
	var args := PackedStringArray([
		"-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass",
		"-File", installer, "-StateFile", state_abs
	])
	setup_pid = OS.create_process("powershell.exe", args, false)
	if setup_pid <= 0:
		stage_label.text = "Не удалось запустить установку"
		return
	install_button.disabled = true
	stage_label.text = "Запускаю подготовку…"
	detail_label.text = "Ожидаю первый реальный этап."

func _read_state() -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	if f == null: return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not data is Dictionary: return
	var stage := str(data.get("stage", ""))
	progress.value = clampi(int(data.get("progress", 0)), 0, 100)
	stage_label.text = _stage_title(stage)
	detail_label.text = str(data.get("message", ""))
	if stage == "ready":
		setup_pid = 0
		install_button.disabled = false
		_restart_backend()
		stage_label.text = "Запускаю File Intelligence…"
		await get_tree().create_timer(2.0).timeout
		await _reanalyze_pending_files()
		popup.hide()
	elif stage == "error":
		setup_pid = 0
		install_button.disabled = false

func _restart_backend() -> void:
	var main := get_parent()
	if main == null: return
	var manager = main.get("attachments")
	if manager is AttachmentManager:
		manager.restart_file_backend()

func _reanalyze_pending_files() -> void:
	var main := get_parent()
	if main == null: return
	var manager = main.get("attachments")
	var pending = main.get("pending_attachments")
	if not manager is AttachmentManager or not pending is Array: return
	for i in range(pending.size()):
		var item = pending[i]
		if item is Dictionary and bool(item.get("needs_setup", false)):
			var path := str(item.get("path", ""))
			if not path.is_empty():
				pending[i] = await manager.analyze(path)
	if main.has_method("_refresh_attachment_bar"):
		main.call("_refresh_attachment_bar")
	var status = main.get("status")
	if status is Label:
		status.text = "● File Intelligence готов"

func _installer_path() -> String:
	for root in _candidate_roots():
		var path := root.path_join("install_files.ps1")
		if FileAccess.file_exists(path): return path
	return ""

func _candidate_roots() -> Array[String]:
	return [
		OS.get_executable_path().get_base_dir().path_join("file_intelligence"),
		ProjectSettings.globalize_path("res://file_intelligence")
	]

func _stage_title(stage: String) -> String:
	return {
		"runtime":"Подготовка локального Python",
		"venv":"Создание изолированного окружения",
		"dependencies":"Установка парсеров",
		"verify":"Проверка File Intelligence",
		"ready":"Готово",
		"error":"Ошибка подготовки"
	}.get(stage, "Подготовка File Intelligence")
