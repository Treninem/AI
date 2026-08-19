class_name AuroraModelSetupWizard
extends Node

const STATE_PATH := "user://aurora_model_setup_state.json"
const REQUIRED_MODEL := "qwen3:8b"
const OLLAMA_TAGS := "http://127.0.0.1:11434/api/tags"

var popup: PopupPanel
var progress: ProgressBar
var stage_label: Label
var detail_label: Label
var profile_select: OptionButton
var install_button: Button
var setup_pid := 0
var poll_timer := 0.0
var startup_wait := 4.0
var shown := false

func _ready() -> void:
	if OS.get_name() != "Windows": return
	_build_ui()
	set_process(true)

func _process(delta: float) -> void:
	if OS.get_name() != "Windows": return
	if not shown and setup_pid <= 0:
		startup_wait -= delta
		if startup_wait <= 0.0:
			shown = true
			var ready := await _required_model_ready()
			if not ready:
				popup.popup_centered()
	if setup_pid > 0:
		poll_timer -= delta
		if poll_timer <= 0.0:
			poll_timer = 0.4
			_read_state()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 89
	add_child(layer)
	popup = PopupPanel.new()
	popup.size = Vector2i(650, 430)
	layer.add_child(popup)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	popup.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 13)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Подготовка локального AI AuroraFox"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var description := Label.new()
	description.text = "AuroraFox работает локально. Если Ollama или модель отсутствуют, приложение может подготовить их автоматически."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)

	var profile_title := Label.new()
	profile_title.text = "Профиль моделей"
	box.add_child(profile_title)
	profile_select = OptionButton.new()
	profile_select.add_item("Базовый — чат (qwen3:8b)")
	profile_select.set_item_metadata(0, "core")
	profile_select.add_item("Сбалансированный — чат + зрение")
	profile_select.set_item_metadata(1, "balanced")
	profile_select.add_item("Полный — чат + зрение + Code 30B")
	profile_select.set_item_metadata(2, "full")
	profile_select.selected = 1
	box.add_child(profile_select)

	var hint := Label.new()
	hint.text = "Полный профиль занимает значительно больше места. Его можно установить позже; базовый ИИ работает без Code 30B."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	stage_label = Label.new()
	stage_label.text = "AI runtime ещё не подготовлен"
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
	detail_label.text = "Проверю Ollama и выбранные локальные модели."
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
	install_button.text = "Подготовить AI"
	install_button.pressed.connect(_start_install)
	row.add_child(install_button)

func _start_install() -> void:
	if setup_pid > 0: return
	var installer := _installer_path()
	if installer.is_empty():
		stage_label.text = "Установщик моделей не найден"
		detail_label.text = "Пересобери Windows-пакет: models/install_models.ps1 должен лежать рядом с AuroraFox.exe."
		return
	var state_abs := ProjectSettings.globalize_path(STATE_PATH)
	if FileAccess.file_exists(STATE_PATH): DirAccess.remove_absolute(state_abs)
	var profile := str(profile_select.get_item_metadata(profile_select.selected))
	var args := PackedStringArray([
		"-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass",
		"-File", installer,
		"-Profile", profile,
		"-StateFile", state_abs
	])
	setup_pid = OS.create_process("powershell.exe", args, false)
	if setup_pid <= 0:
		stage_label.text = "Не удалось запустить установщик"
		return
	install_button.disabled = true
	profile_select.disabled = true
	stage_label.text = "Запуск подготовки…"
	detail_label.text = "Ожидаю первый реальный этап."

func _read_state() -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	if f == null: return
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary: return
	var stage := str(data.get("stage", ""))
	progress.value = clampi(int(data.get("progress", 0)), 0, 100)
	stage_label.text = _stage_title(stage)
	detail_label.text = str(data.get("message", ""))
	if stage == "ready":
		setup_pid = 0
		install_button.disabled = false
		profile_select.disabled = false
		stage_label.text = "Локальный AI готов"
		await get_tree().create_timer(1.0).timeout
		if await _required_model_ready():
			_update_main_status()
			popup.hide()
	elif stage == "error":
		setup_pid = 0
		install_button.disabled = false
		profile_select.disabled = false

func _required_model_ready() -> bool:
	var req := HTTPRequest.new()
	req.timeout = 4.0
	add_child(req)
	var err := req.request(OLLAMA_TAGS)
	if err != OK:
		req.queue_free()
		return false
	var result: Array = await req.request_completed
	req.queue_free()
	if int(result[1]) != 200: return false
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary: return false
	for item in parsed.get("models", []):
		if item is Dictionary and str(item.get("name", item.get("model", ""))) == REQUIRED_MODEL:
			return true
	return false

func _installer_path() -> String:
	for root in _model_roots():
		var path := root.path_join("install_models.ps1")
		if FileAccess.file_exists(path): return path
	return ""

func _model_roots() -> Array[String]:
	return [
		OS.get_executable_path().get_base_dir().path_join("models"),
		ProjectSettings.globalize_path("res://models")
	]

func _stage_title(stage: String) -> String:
	return {
		"runtime":"Проверка AI runtime",
		"runtime_download":"Загрузка Ollama",
		"runtime_install":"Установка Ollama",
		"runtime_start":"Запуск локального API",
		"model_pull":"Загрузка модели",
		"verify":"Проверка моделей",
		"ready":"Готово",
		"error":"Ошибка подготовки"
	}.get(stage, "Подготовка локального AI")

func _update_main_status() -> void:
	var main := get_parent()
	if main == null: return
	var label = main.get("status")
	if label is Label:
		label.text = "● модель подключена   qwen3:8b"
