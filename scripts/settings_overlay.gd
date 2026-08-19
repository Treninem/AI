class_name AuroraSettingsOverlay
extends Node

var popup: PopupPanel
var update_status: Label
var file_status: Label
var voice_status: Label
var project_status: Label
var improvement_status: Label
var project_picker: FileDialog
var project_select: OptionButton

func _ready() -> void:
	_build_ui()
	AuroraUpdate.update_available.connect(func(info): update_status.text = "Доступна версия %s" % str(info.get("version", "")))
	AuroraUpdate.no_update.connect(func(version): update_status.text = "Установлена актуальная версия %s" % version)
	AuroraUpdate.update_error.connect(func(message): update_status.text = "Обновление: %s" % message)
	AuroraVoice.backend_status.connect(func(ready, _info): voice_status.text = "Голосовой backend: %s" % ("готов" if ready else "не подключён"))

func show_settings() -> void:
	_sync_status()
	_refresh_project_list()
	popup.popup_centered()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	popup = PopupPanel.new()
	popup.size = Vector2i(760, 760)
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
	var modes := [["Выкл.", "off"], ["Fox / Лиса", "wake_word"], ["Постоянный диалог", "continuous"], ["Push-to-talk", "push_to_talk"]]
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
	prepare_files.visible = OS.get_name() == "Windows"
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

	_add_section(box, "Проекты и кодовая база")
	var project_hint := Label.new()
	project_hint.text = "Папка становится доступной агенту только после явного выбора здесь. Индекс хранится локально и позволяет быстро находить классы, функции и связанные участки кода."
	project_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(project_hint)
	project_select = OptionButton.new()
	project_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(project_select)
	project_status = Label.new()
	project_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(project_status)
	var project_buttons := HBoxContainer.new()
	var add_project := Button.new()
	add_project.text = "Добавить папку проекта"
	add_project.disabled = OS.get_name() != "Windows"
	add_project.pressed.connect(func(): project_picker.popup_centered_ratio(0.72))
	project_buttons.add_child(add_project)
	var reindex := Button.new()
	reindex.text = "Обновить индекс"
	reindex.disabled = OS.get_name() != "Windows"
	reindex.pressed.connect(_index_selected_project)
	project_buttons.add_child(reindex)
	var remove_project := Button.new()
	remove_project.text = "Убрать доступ"
	remove_project.disabled = OS.get_name() != "Windows"
	remove_project.pressed.connect(_remove_selected_project)
	project_buttons.add_child(remove_project)
	box.add_child(project_buttons)
	_add_separator(box)

	_add_section(box, "Самоулучшение")
	var improvement_hint := Label.new()
	improvement_hint.text = "AuroraFox может предложить новое ограниченное расширение, проверить полную копию проекта в песочнице через Godot 4.7.1 и подготовить его. Активация выполняется только после отдельного подтверждения и не заменяет ядро."
	improvement_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(improvement_hint)
	improvement_status = Label.new()
	improvement_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(improvement_status)
	var improvement_button := Button.new()
	improvement_button.text = "Открыть центр самоулучшения"
	improvement_button.pressed.connect(_open_self_improvement)
	box.add_child(improvement_button)
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

	project_picker = FileDialog.new()
	project_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	project_picker.access = FileDialog.ACCESS_FILESYSTEM
	project_picker.use_native_dialog = true
	project_picker.dir_selected.connect(_on_project_selected)
	add_child(project_picker)

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
	if setup_popup is PopupPanel: setup_popup.popup_centered()

func _sync_status() -> void:
	voice_status.text = "Голосовой backend: %s" % ("готов" if AuroraVoice.backend_is_ready else "не подключён")
	_refresh_file_status()
	_refresh_index_status()
	_sync_improvement_status()

func _refresh_file_status() -> void:
	var main := get_parent()
	if main == null: return
	var manager = main.get("attachments")
	if not manager is AttachmentManager:
		file_status.text = "File Intelligence: менеджер не подключён"
		return
	var result := await manager.intelligence.health()
	if not result.get("ok", false):
		file_status.text = "File Intelligence: требуется подготовка" if OS.get_name() == "Windows" else "File Intelligence: Android runtime недоступен"
		return
	if OS.get_name() == "Android":
		file_status.text = "File Intelligence: Android native • STT %s • PDF/DOCX/XLSX/PPTX/ZIP • глубокое vision/OCR пока не подключено" % ("готов" if result.get("voice_online", false) else "ограничен")
	else:
		file_status.text = "File Intelligence: готов • vision %s • voice/STT %s" % [
			"подключено" if result.get("vision_online", false) else "не подключено",
			"подключено" if result.get("voice_online", false) else "не подключено"
		]

func _clear_file_cache() -> void:
	var main := get_parent()
	if main == null: return
	var manager = main.get("attachments")
	if manager is AttachmentManager:
		var result := await manager.clear_file_cache()
		file_status.text = ("Кэш файлов очищен" if OS.get_name() == "Android" else "Кэш очищен: %s" % str(result.get("removed", 0))) if result.get("ok", false) else "Не удалось очистить кэш"

func _project_bridge() -> ProjectIndexToolBridge:
	var main := get_parent()
	if main == null: return null
	return main.get_node_or_null("ProjectIndexTools") as ProjectIndexToolBridge

func _refresh_project_list() -> void:
	if project_select == null: return
	project_select.clear()
	var bridge := _project_bridge()
	if bridge == null:
		project_status.text = "Индекс проектов: модуль не подключён"
		return
	var roots := bridge.access.all_roots()
	for root in roots:
		project_select.add_item(str(root).get_file() if not str(root).get_file().is_empty() else str(root))
		project_select.set_item_metadata(project_select.item_count - 1, root)
	if roots.is_empty():
		project_select.add_item("Нет доверенных папок")
		project_select.set_item_disabled(0, true)
		project_status.text = "Выбери локальную папку проекта, чтобы AuroraFox могла её индексировать."
	else:
		_refresh_index_status()

func _selected_project() -> String:
	if project_select == null or project_select.item_count == 0: return ""
	var value = project_select.get_item_metadata(project_select.selected)
	return str(value) if value != null else ""

func _on_project_selected(path: String) -> void:
	var bridge := _project_bridge()
	if bridge == null: return
	if not bridge.access.add_root(path):
		project_status.text = "Не удалось добавить папку проекта."
		return
	_refresh_project_list()
	for i in range(project_select.item_count):
		if str(project_select.get_item_metadata(i)) == bridge.access.normalize(path):
			project_select.selected = i
			break
	await _index_selected_project()

func _index_selected_project() -> void:
	var root := _selected_project()
	var bridge := _project_bridge()
	if root.is_empty() or bridge == null:
		project_status.text = "Сначала выбери папку проекта."
		return
	project_status.text = "Индексирую изменившиеся файлы…"
	var result := await bridge.index.index_project(root, 30000, false)
	if result.get("ok", false):
		project_status.text = "Индекс готов: %d файлов • обновлено %d • %d мс" % [int(result.get("total_files", 0)), int(result.get("updated_files", 0)), int(result.get("elapsed_ms", 0))]
	else:
		project_status.text = "Ошибка индекса: %s" % str(result.get("error", "unknown"))

func _refresh_index_status() -> void:
	var root := _selected_project()
	var bridge := _project_bridge()
	if root.is_empty() or bridge == null: return
	var result := await bridge.index.status(root)
	if result.get("ok", false):
		project_status.text = "Индекс: %d файлов • %s" % [int(result.get("files", 0)), JSON.stringify(result.get("languages", {}))]

func _remove_selected_project() -> void:
	var root := _selected_project()
	var bridge := _project_bridge()
	if root.is_empty() or bridge == null: return
	await bridge.index.clear(root)
	bridge.access.remove_root(root)
	_refresh_project_list()

func _runtime_extensions() -> RuntimeExtensionManager:
	var main := get_parent()
	if main == null: return null
	return main.get_node_or_null("RuntimeExtensions") as RuntimeExtensionManager

func _sync_improvement_status() -> void:
	if improvement_status == null: return
	var manager := _runtime_extensions()
	if manager == null:
		improvement_status.text = "Runtime-расширения: менеджер не подключён"
		return
	var items := manager.list_extensions()
	var active := 0
	for item in items:
		if bool(item.get("active", false)): active += 1
	improvement_status.text = "Runtime-расширения: %d активных / %d сохранённых • автоматическая Godot-проверка: %s" % [active, items.size(), "Windows" if OS.get_name() == "Windows" else "недоступна на этой платформе"]

func _open_self_improvement() -> void:
	var main := get_parent()
	if main == null: return
	var center := main.get_node_or_null("SelfImprovementCenter")
	if center == null or not center.has_method("show_center"):
		improvement_status.text = "Центр самоулучшения не подключён"
		return
	popup.hide()
	center.call("show_center")

func _check_updates() -> void:
	update_status.text = "Проверяю подписанный stable-релиз…"
	await AuroraUpdate.check_for_updates(true)
