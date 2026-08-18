class_name AuroraVoiceSetupWizard
extends Node

const STATE_PATH := "user://aurora_voice_setup_state.json"

var popup: PopupPanel
var progress: ProgressBar
var stage_label: Label
var detail_label: Label
var install_button: Button
var setup_pid := 0
var poll_timer := 0.0
var startup_wait := 3.5
var shown := false

func _ready() -> void:
	if OS.get_name() != "Windows": return
	_build_ui()
	set_process(true)
	AuroraVoice.backend_status.connect(_on_backend_status)

func _process(delta: float) -> void:
	if OS.get_name() != "Windows": return
	if not shown and not AuroraVoice.backend_is_ready:
		startup_wait -= delta
		if startup_wait <= 0.0 and not _runtime_ready_on_disk():
			shown = true
			popup.popup_centered()
	if setup_pid > 0:
		poll_timer -= delta
		if poll_timer <= 0.0:
			poll_timer = 0.35
			_read_real_state()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	popup = PopupPanel.new()
	popup.size = Vector2i(610, 360)
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
	title.text = "Подготовка голосового модуля AuroraFox"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var description := Label.new()
	description.text = "Компоненты устанавливаются локально. Прогресс ниже отражает реальные этапы установки."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	stage_label = Label.new()
	stage_label.text = "Голосовой runtime ещё не подготовлен"
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
	detail_label.text = "Будут подготовлены VAD, Fox/Лиса wake word, Whisper STT и локальный TTS."
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
	install_button.text = "Подготовить голос"
	install_button.pressed.connect(_start_install)
	row.add_child(install_button)

func _start_install() -> void:
	var installer := _installer_path()
	if installer.is_empty():
		stage_label.text = "Установщик не найден"
		detail_label.text = "Запусти voice/install_voice.ps1 из исходного проекта или пересобери Windows-пакет."
		return
	var state_abs := ProjectSettings.globalize_path(STATE_PATH)
	if FileAccess.file_exists(STATE_PATH): DirAccess.remove_absolute(state_abs)
	var args := PackedStringArray([
		"-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass",
		"-File", installer, "-StateFile", state_abs
	])
	setup_pid = OS.create_process("powershell.exe", args, false)
	if setup_pid <= 0:
		stage_label.text = "Не удалось запустить установщик"
		return
	install_button.disabled = true
	stage_label.text = "Запуск установки…"
	detail_label.text = "Ожидаю первый реальный этап."

func _read_real_state() -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	if f == null: return
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary: return
	var stage := str(data.get("stage", ""))
	var percent := clampi(int(data.get("progress", 0)), 0, 100)
	var message := str(data.get("message", ""))
	progress.value = percent
	stage_label.text = _stage_title(stage)
	detail_label.text = message
	if stage == "ready":
		setup_pid = 0
		install_button.disabled = false
		AuroraVoice.bridge.call("_start_backend_if_installed")
		stage_label.text = "Готово. Запускаю голос AuroraFox…"
		await get_tree().create_timer(1.5).timeout
		popup.hide()
	elif stage == "error":
		setup_pid = 0
		install_button.disabled = false

func _stage_title(stage: String) -> String:
	return {
		"components":"Проверка компонентов",
		"dependencies":"Подготовка зависимостей",
		"wake_word":"Подготовка Fox / Лиса",
		"stt_model":"Подготовка распознавания речи",
		"tts_model":"Подготовка голоса",
		"microphone":"Проверка микрофона",
		"ready":"Готово",
		"error":"Ошибка подготовки"
	}.get(stage, "Подготовка голосового модуля")

func _runtime_ready_on_disk() -> bool:
	for root in _voice_roots():
		if FileAccess.file_exists(root.path_join(".venv/Scripts/pythonw.exe")) and FileAccess.file_exists(root.path_join("python/aurora_voice_server.py")) and DirAccess.dir_exists_absolute(root.path_join("models/vosk-model-small-ru-0.22")):
			return true
	return false

func _installer_path() -> String:
	for root in _voice_roots():
		var path := root.path_join("install_voice.ps1")
		if FileAccess.file_exists(path): return path
	return ""

func _voice_roots() -> Array[String]:
	return [
		OS.get_executable_path().get_base_dir().path_join("voice"),
		ProjectSettings.globalize_path("res://voice")
	]

func _on_backend_status(ready: bool, _info: Dictionary) -> void:
	if ready and popup != null and popup.visible:
		progress.value = 100
		stage_label.text = "Голос AuroraFox готов"
		detail_label.text = "Локальный backend подключён."
