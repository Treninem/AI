class_name AuroraModelSetupWizard
extends Node

const STATE_PATH := "user://aurora_model_setup_state.json"
const REQUIRED_MODEL := "qwen3:8b"
const OLLAMA_TAGS := "http://127.0.0.1:11434/api/tags"
const FOX_LOGO: Texture2D = preload("res://assets/ui/fox_logo.svg")
const PROFILE_INFO := {
	"core": {"label":"Базовый — чат", "models":"qwen3:8b", "bytes":5200000000, "note":"Основной локальный чат и инструменты."},
	"balanced": {"label":"Сбалансированный — чат + зрение", "models":"qwen3:8b + qwen3-vl:8b", "bytes":11300000000, "note":"Добавляет анализ изображений, сканов PDF и кадров видео."},
	"full": {"label":"Полный — чат + зрение + Code 30B", "models":"qwen3:8b + qwen3-vl:8b + qwen3-coder:30b", "bytes":30300000000, "note":"Добавляет отдельную Code-модель для сложных программных задач."}
}

var popup: PopupPanel
var progress: ProgressBar
var stage_label: Label
var detail_label: Label
var profile_select: OptionButton
var profile_detail: Label
var install_button: Button
var setup_pid := 0
var poll_timer := 0.0
var startup_wait := 2.0
var shown := false
var last_stage := ""

func _ready() -> void:
	if OS.get_name() != "Windows":
		return
	_build_ui()
	set_process(true)

func _process(delta: float) -> void:
	if OS.get_name() != "Windows":
		return
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
			poll_timer = 0.35
			_read_state()
			if setup_pid > 0 and not OS.is_process_running(setup_pid):
				_read_state()
				if setup_pid > 0:
					setup_pid = 0
					_unlock_controls()
					stage_label.text = "Подготовка завершилась с ошибкой"
					detail_label.text = "Процесс подготовки завершился без финального состояния. Повторите запуск; если ошибка сохранится, откройте журнал Windows/Ollama."

func _style(fill: Color, border: Color, radius := 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _apply_button(button: Button, accent := false) -> void:
	var border := Color(0.34, 0.39, 0.55, 0.55)
	if accent:
		border = Color(0.66, 0.54, 1.0, 0.85)
	button.add_theme_stylebox_override("normal", _style(Color(0.06, 0.07, 0.11, 0.98), border, 12))
	button.add_theme_stylebox_override("hover", _style(Color(0.11, 0.12, 0.18, 1.0), border, 12))
	button.add_theme_stylebox_override("pressed", _style(Color(0.15, 0.11, 0.23, 1.0), border, 12))
	button.add_theme_stylebox_override("focus", _style(Color(0.11, 0.12, 0.18, 1.0), Color(0.27, 0.84, 1.0, 0.85), 12))
	button.add_theme_color_override("font_color", Color("f3f6ff"))
	button.add_theme_font_size_override("font_size", 14)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 89
	add_child(layer)
	popup = PopupPanel.new()
	popup.size = Vector2i(720, 560)
	popup.add_theme_stylebox_override("panel", _style(Color(0.035, 0.042, 0.065, 0.995), Color(0.42, 0.34, 0.68, 0.72), 20))
	layer.add_child(popup)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	popup.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var logo := TextureRect.new()
	logo.texture = FOX_LOGO
	logo.custom_minimum_size = Vector2(58, 58)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(logo)
	var titles := VBoxContainer.new()
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(titles)
	var title := Label.new()
	title.text = "Подготовка локального AI"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f3f6ff"))
	titles.add_child(title)
	var sub := Label.new()
	sub.text = "AuroraFox • локальный режим"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color("a98aff"))
	titles.add_child(sub)

	var description := Label.new()
	description.text = "Если Ollama или выбранные модели отсутствуют, AuroraFox подготовит их автоматически. Уже установленные модели повторно не скачиваются."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("cbd4e8"))
	box.add_child(description)

	var profile_title := Label.new()
	profile_title.text = "Профиль моделей"
	profile_title.add_theme_color_override("font_color", Color("f3f6ff"))
	box.add_child(profile_title)
	profile_select = OptionButton.new()
	profile_select.custom_minimum_size.y = 42
	for id in ["core", "balanced", "full"]:
		var info: Dictionary = PROFILE_INFO[id]
		profile_select.add_item("%s • ≈ %.1f ГБ" % [info.get("label", id), float(info.get("bytes", 0)) / 1000000000.0])
		profile_select.set_item_metadata(profile_select.item_count - 1, id)
	profile_select.selected = 0
	profile_select.item_selected.connect(func(_index): _sync_profile_detail())
	box.add_child(profile_select)

	profile_detail = Label.new()
	profile_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profile_detail.add_theme_color_override("font_color", Color("8d98ad"))
	box.add_child(profile_detail)
	_sync_profile_detail()

	var hint := Label.new()
	hint.text = "Перед загрузкой проверяются версия Ollama и свободное место. Для первого запуска достаточно базового профиля; Vision и Code можно добавить позже."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("8d98ad"))
	box.add_child(hint)

	stage_label = Label.new()
	stage_label.text = "AI runtime ещё не подготовлен"
	stage_label.add_theme_font_size_override("font_size", 17)
	stage_label.add_theme_color_override("font_color", Color("f3f6ff"))
	box.add_child(stage_label)

	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = 100
	progress.value = 0
	progress.show_percentage = true
	progress.custom_minimum_size.y = 26
	progress.add_theme_stylebox_override("background", _style(Color(0.025, 0.03, 0.05, 1.0), Color(0.24, 0.28, 0.38, 0.55), 10))
	progress.add_theme_stylebox_override("fill", _style(Color(0.31, 0.18, 0.54, 1.0), Color(0.66, 0.54, 1.0, 0.85), 10))
	box.add_child(progress)

	detail_label = Label.new()
	detail_label.text = "Проверю Ollama и выбранные локальные модели."
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 13)
	detail_label.add_theme_color_override("font_color", Color("cbd4e8"))
	box.add_child(detail_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var later := Button.new()
	later.text = "Позже"
	later.custom_minimum_size = Vector2(90, 40)
	later.pressed.connect(func(): popup.hide())
	_apply_button(later, false)
	row.add_child(later)
	install_button = Button.new()
	install_button.text = "Подготовить AI"
	install_button.custom_minimum_size = Vector2(138, 40)
	install_button.pressed.connect(_start_install)
	_apply_button(install_button, true)
	row.add_child(install_button)

func _sync_profile_detail() -> void:
	if profile_select == null or profile_detail == null:
		return
	var id := str(profile_select.get_item_metadata(profile_select.selected))
	var info: Dictionary = PROFILE_INFO.get(id, {})
	profile_detail.text = "%s\nМодели: %s\nПолный объём профиля ≈ %.1f ГБ; скачивается только недостающее." % [
		str(info.get("note", "")), str(info.get("models", "")), float(info.get("bytes", 0)) / 1000000000.0
	]

func _start_install() -> void:
	if setup_pid > 0:
		return
	var installer := _installer_path()
	if installer.is_empty():
		stage_label.text = "Установщик моделей не найден"
		detail_label.text = "Windows-пакет неполный: models/install_models.ps1 должен лежать рядом с AuroraFox.exe."
		return
	var state_abs := ProjectSettings.globalize_path(STATE_PATH)
	if FileAccess.file_exists(STATE_PATH):
		DirAccess.remove_absolute(state_abs)
	var profile := str(profile_select.get_item_metadata(profile_select.selected))
	var args := PackedStringArray([
		"-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass",
		"-File", installer,
		"-Profile", profile,
		"-StateFile", state_abs
	])
	setup_pid = OS.create_process("powershell.exe", args, false)
	if setup_pid <= 0:
		stage_label.text = "Не удалось запустить подготовку AI"
		detail_label.text = "Windows не запустила powershell.exe для локальной установки."
		return
	install_button.disabled = true
	profile_select.disabled = true
	stage_label.text = "Запуск подготовки…"
	detail_label.text = "Ожидаю первый подтверждённый этап."
	progress.value = 0
	last_stage = ""

func _unlock_controls() -> void:
	if install_button != null:
		install_button.disabled = false
	if profile_select != null:
		profile_select.disabled = false

func _read_state() -> void:
	var file := FileAccess.open(STATE_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		return
	var stage := str(data.get("stage", ""))
	last_stage = stage
	progress.value = clampi(int(data.get("progress", 0)), 0, 100)
	stage_label.text = _stage_title(stage)
	detail_label.text = str(data.get("message", ""))
	if stage == "ready":
		setup_pid = 0
		_unlock_controls()
		stage_label.text = "Локальный AI готов"
		await get_tree().create_timer(0.7).timeout
		if await _required_model_ready():
			_update_main_status()
			popup.hide()
	elif stage == "error":
		setup_pid = 0
		_unlock_controls()
		stage_label.text = "Ошибка подготовки AI"

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
	if int(result[1]) != 200:
		return false
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary:
		return false
	for item in parsed.get("models", []):
		if item is Dictionary and str(item.get("name", item.get("model", ""))) == REQUIRED_MODEL:
			return true
	return false

func _installer_path() -> String:
	for root in _model_roots():
		var path := root.path_join("install_models.ps1")
		if FileAccess.file_exists(path):
			return path
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
		"runtime_install":"Установка / обновление Ollama",
		"runtime_start":"Запуск локального API",
		"storage":"Проверка свободного места",
		"model_pull":"Загрузка моделей",
		"verify":"Проверка моделей",
		"ready":"Готово",
		"error":"Ошибка подготовки"
	}.get(stage, "Подготовка локального AI")

func _update_main_status() -> void:
	var main := get_parent()
	if main == null:
		return
	if main.has_method("_set_status"):
		main.call("_set_status", "Модель подключена • qwen3:8b", true, false)
		return
	var label = main.get("status")
	if label is Label:
		label.text = "Модель подключена • qwen3:8b"
