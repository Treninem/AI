class_name AuroraSettingsOverlay
extends Node

var popup: PopupPanel
var update_status: Label
var file_status: Label
var voice_status: Label

func _ready() -> void:
	_build_ui()
	call_deferred("_connect_existing_settings_button")
	AuroraUpdate.update_available.connect(func(info): update_status.text = "Доступна версия %s" % str(info.get("version", "")))
	AuroraUpdate.no_update.connect(func(version): update_status.text = "Установлена актуальная версия %s" % version)
	AuroraUpdate.update_error.connect(func(message): update_status.text = "Обновление: %s" % message)
	AuroraVoice.backend_status.connect(func(ready, _info): voice_status.text = "Голосовой backend: %s" % ("готов" if ready else "не подключён"))

func show_settings() -> void:
	_sync_status()
	popup.popup_centered()

func _connect_existing_settings_button() -> void:
	var main := get_parent()
	if main == null: return
	var button := _find_button(main, "⚙  Инструменты и настройки")
	if button != null and not button.pressed.is_connected(show_settings):
		button.pressed.connect(show_settings)

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null: return found
	return null

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	popup = PopupPanel.new()
	popup.size = Vector2i(720, 690)
	layer.add_child(popup)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	popup.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "Настройки AuroraFox"
	title.add_theme_font_size_override("font_size", 27)
	box.add_child(title)

	var version := Label.new()
	version.text = "Версия %s • Godot %s" % [ProjectSettings.get_setting("application/config/version", "0.0.0"), Engine.get_version_info().get("string", "4.7.1")]
	box.add_child(version)
	_add_separator(box)

	_add_section(box, "Голос")
	var voice_enabled := CheckButton.new()
	voice_enabled.text = "Голос AuroraFox"
	voice_enabled.button_pressed = bool(AuroraVoice.settings.get("enabled", true))
	voice_enabled.toggled.connect(func(v): AuroraVoice.set_enabled(v))
	box.add_child(voice_enabled)

	var speak := CheckButton.new()
	speak.text = "Озвучивать ответы"
	speak.button_pressed = bool(AuroraVoice.settings.get("auto_speak", true))
	speak.toggled.connect(func(v): AuroraVoice.set_auto_speak(v))
	box.add_child(speak)

	box.add_child(_slider_row("Громкость", float(AuroraVoice.settings.get("volume", 0.86)), 0.0, 1.0, 0.01, func(v): AuroraVoice.set_volume(v)))
	box.add_child(_slider_row("Скорость речи", float(AuroraVoice.settings.get("speed", 1.04)), 0.82, 1.20, 0.01, func(v): AuroraVoice.update_setting("speed", v)))
	box.add_child(_slider_row("Механический оттенок", float(AuroraVoice.settings.get("mechanical_amount", 0.035)), 0.0, 0.10, 0.005, func(v): AuroraVoice.update_setting("mechanical_amount", v)))

	var mic_row := HBoxContainer.new()
	var mic_label := Label.new()
	mic_label.text = "Режим микрофона"
	mic_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mic_row.add_child(mic_label)
	var mic_mode := OptionButton.new()
	var modes := [
		["Выкл.", "off"],
		["Fox / Лиса", "wake_word"],
		["Постоянный диалог", "continuous"],
		["Push-to-talk", "push_to_talk"]
	]
	var current_mode := str(AuroraVoice.settings.get("mic_mode", "wake_word"))
	for i in range(modes.size()):
		mic_mode.add_item(str(modes[i][0]))
		mic_mode.set_item_metadata(i, modes[i][1])
		if str(modes[i][1]) == current_mode: mic_mode.selected = i
	mic_mode.item_selected.connect(func(index): AuroraVoice.set_mic_mode(str(mic_mode.get_item_metadata(index))))
	mic_row.add_child(mic_mode)
	box.add_child(mic_row)

	voice_status = Label.new()
	box.add_child(voice_status)
	var voice_prepare := Button.new()
	voice_prepare.text = "Подготовить / восстановить голосовой модуль"
	voice_prepare.pressed.connect(func(): _show_setup_node("VoiceSetup"))
	box.add_child(voice_prepare)
	_add_separator(box)

	_add_section(box, "Локальный AI")
	var ai_hint := Label.new()
	ai_hint.text = "Профили моделей: базовый чат, чат + зрение, полный с отдельной Code-моделью."
	ai_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ai_hint)
	var ai_prepare := Button.new()
	ai_prepare.text = "Установить / изменить локальные модели"
	ai_prepare.pressed.connect(func(): _show_setup_node("ModelSetup"))
	box.add_child(ai_prepare)
	_add_separator(box)

	_add_section(box, "Файлы")
	file_status = Label.new()
	file_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(file_status)
	var file_buttons := HBoxContainer.new()
	var prepare_files := Button.new()
	prepare_files.text = "Подготовить File Intelligence"
	prepare_files.pressed.connect(func(): _show_setup_node("FileSetup"))
	file_buttons.add_child(prepare_files)
	var clear_files := Button.new()
	clear_files.text = "Очистить кэш файлов"
	clear_files.pressed.connect(_clear_file_cache)
	file_buttons.add_child(clear_files)
	var refresh_files := Button.new()
	refresh_files.text = "Проверить"
	refresh_files.pressed.connect(_refresh_file_status)
	file_buttons.add_child(refresh_files)
	box.add_child(file_buttons)
	_add_separator(box)

	_add_section(box, "Обновления")
	var update_settings := AuroraUpdate.get_settings()
	var auto_check := CheckButton.new()
	auto_check.text = "Автоматически проверять обновления"
	auto_check.button_pressed = bool(update_settings.get("auto_check", true))
	auto_check.toggled.connect(func(v): AuroraUpdate.set_auto_check(v))
	box.add_child(auto_check)
	var auto_download := CheckButton.new()
	auto_download.text = "Автоматически скачивать проверенные обновления"
	auto_download.button_pressed = bool(update_settings.get("auto_download", true))
	auto_download.toggled.connect(func(v): AuroraUpdate.set_auto_download(v))
	box.add_child(auto_download)
	update_status = Label.new()
	update_status.text = "Канал: stable"
	update_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(update_status)
	var update_button := Button.new()
	update_button.text = "Проверить обновления сейчас"
	update_button.pressed.connect(_check_updates)
	box.add_child(update_button)
	_add_separator(box)

	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(func(): popup.hide())
	box.add_child(close)

func _slider_row(label_text: String, initial: float, minimum: float, maximum: float, step: float, changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 210
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(changed)
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = "%.2f" % initial
	value_label.custom_minimum_size.x = 55
	slider.value_changed.connect(func(v): value_label.text = "%.2f" % v)
	row.add_child(value_label)
	return row

func _add_section(box: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	box.add_child(label)

func _add_separator(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())

func _show_setup_node(name: String) -> void:
	var main := get_parent()
	if main == null: return
	var node := main.get_node_or_null(name)
	if node == null: return
	if node.has_method("show_setup"):
		node.call("show_setup")
		return
	var setup_popup = node.get("popup")
	if setup_popup is PopupPanel:
		setup_popup.popup_centered()

func _sync_status() -> void:
	voice_status.text = "Голосовой backend: %s" % ("готов" if AuroraVoice.backend_is_ready else "не подключён")	
	_refresh_file_status()

func _refresh_file_status() -> void:
	var main := get_parent()
	if main == null: return
	var manager = main.get("attachments")
	if not manager is AttachmentManager:
		file_status.text = "File Intelligence: менеджер не подключён"
		return
	var result := await manager.intelligence.health()
	if result.get("ok", false):
		file_status.text = "File Intelligence: готов • vision %s • voice/STT %s" % [
			"подключено" if result.get("vision_online", false) else "не подключено",
			"подключено" if result.get("voice_online", false) else "не подключено"
		]
	else:
		file_status.text = "File Intelligence: требуется подготовка"

func _clear_file_cache() -> void:
	var main := get_parent()
	if main == null: return
	var manager = main.get("attachments")
	if manager is AttachmentManager:
		var result := await manager.clear_file_cache()
		file_status.text = "Кэш очищен: %s" % str(result.get("removed", 0)) if result.get("ok", false) else "Не удалось очистить кэш"

func _check_updates() -> void:
	update_status.text = "Проверяю подписанный stable-релиз…"
	await AuroraUpdate.check_for_updates(true)
