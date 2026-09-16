class_name AuroraSettingsOverlay
extends Node

const BG := Color(0.020, 0.024, 0.041, 0.995)
const SURFACE := Color(0.045, 0.052, 0.082, 0.98)
const SURFACE_HOVER := Color(0.075, 0.085, 0.13, 0.99)
const BORDER := Color(0.30, 0.36, 0.50, 0.52)
const ACCENT := Color("a98aff")
const CYAN := Color("45d8ff")
const GREEN := Color("64ff9d")
const MUTED := Color("8d98ad")
const WHITE := Color("f3f6ff")
const WARNING := Color("ffbd75")

var popup: PopupPanel
var page_stack: TabContainer
var nav_buttons: Array[Button] = []
var nav_keys: Array[String] = []
var nav_indices: Dictionary = {}
var mobile_nav: HFlowContainer

var core_status: Label
var update_status: Label
var file_status: Label
var voice_status: Label
var project_status: Label
var improvement_status: Label
var project_picker: FileDialog
var project_select: OptionButton

func _ready() -> void:
	_build_ui()
	AuroraUpdate.update_available.connect(func(info):
		if update_status != null:
			update_status.text = "Доступна версия %s" % str(info.get("version", ""))
	)
	AuroraUpdate.no_update.connect(func(version):
		if update_status != null:
			update_status.text = "Установлена актуальная версия %s" % version
	)
	AuroraUpdate.update_error.connect(func(message):
		if update_status != null and popup != null and popup.visible:
			update_status.text = "Обновление сейчас недоступно • %s" % message
	)
	AuroraVoice.backend_status.connect(func(ready, _info):
		if voice_status != null:
			voice_status.text = "Голосовой модуль: %s" % ("готов" if ready else "не подключён")
	)

func show_settings(initial_page := "general") -> void:
	await _sync_status()
	_refresh_project_list()
	_select_page(initial_page)
	_fit_popup()
	popup.popup_centered()

func _is_mobile_layout() -> bool:
	return OS.get_name() == "Android" or bool(ProjectSettings.get_setting("aurorafox/testing/mobile_preview", false))

func _fit_popup() -> void:
	if popup == null:
		return
	var viewport := get_viewport().get_visible_rect().size
	if _is_mobile_layout():
		popup.size = Vector2i(
			maxi(340, int(viewport.x - 20.0)),
			maxi(520, int(viewport.y - 28.0))
		)
	else:
		popup.size = Vector2i(
			maxi(720, mini(1040, int(viewport.x - 48.0))),
			maxi(560, mini(820, int(viewport.y - 48.0)))
		)

func _style(fill: Color, border := BORDER, radius := 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _panel_style() -> StyleBoxFlat:
	var style := _style(BG, Color(0.34, 0.50, 0.78, 0.72), 20)
	style.shadow_color = Color(0, 0, 0, 0.68)
	style.shadow_size = 18
	return style

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)

	popup = PopupPanel.new()
	popup.name = "SettingsPopup"
	popup.size = Vector2i(1000, 760)
	popup.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(popup)

	# Older integration overlays used to inject controls into the first large VBox
	# they could find. Keep a hidden compatibility sink so those legacy injections
	# never break the paged settings layout while their real entry points live on
	# the Tools page below.
	var legacy_sink := VBoxContainer.new()
	legacy_sink.name = "LegacySettingsInjectionSink"
	legacy_sink.visible = false
	for i in range(5):
		legacy_sink.add_child(Control.new())
	popup.add_child(legacy_sink)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var edge := 14 if _is_mobile_layout() else 20
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(side, edge)
	popup.add_child(outer)

	var root := VBoxContainer.new()
	root.name = "SettingsRoot"
	root.add_theme_constant_override("separation", 14)
	outer.add_child(root)

	var header := HBoxContainer.new()
	header.name = "SettingsHeader"
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	var heading_box := VBoxContainer.new()
	heading_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading_box)
	var title := Label.new()
	title.text = "Настройки"
	title.add_theme_font_size_override("font_size", 28 if not _is_mobile_layout() else 24)
	title.add_theme_color_override("font_color", WHITE)
	heading_box.add_child(title)
	var version := Label.new()
	version.text = "AuroraFox %s • Godot %s" % [ProjectSettings.get_setting("application/config/version", "0.0.0"), Engine.get_version_info().get("string", "4.7.1")]
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", MUTED)
	heading_box.add_child(version)

	var done := Button.new()
	done.name = "SettingsDoneButton"
	done.text = "Готово"
	done.custom_minimum_size = Vector2(96, 42)
	done.pressed.connect(func(): popup.hide())
	done.add_theme_stylebox_override("normal", _style(Color(0.11, 0.075, 0.18, 0.98), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.72), 12))
	done.add_theme_stylebox_override("hover", _style(Color(0.17, 0.10, 0.28, 1.0), Color(CYAN.r, CYAN.g, CYAN.b, 0.86), 12))
	header.add_child(done)

	if _is_mobile_layout():
		_build_mobile_navigation(root)
	else:
		_build_desktop_navigation(root)

	_build_pages()
	_select_page("general")

	project_picker = FileDialog.new()
	project_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	project_picker.access = FileDialog.ACCESS_FILESYSTEM
	project_picker.use_native_dialog = true
	project_picker.dir_selected.connect(_on_project_selected)
	add_child(project_picker)

func _build_desktop_navigation(root: VBoxContainer) -> void:
	var body := HBoxContainer.new()
	body.name = "SettingsBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	var nav_panel := PanelContainer.new()
	nav_panel.name = "SettingsNavigationPanel"
	nav_panel.custom_minimum_size.x = 212
	nav_panel.add_theme_stylebox_override("panel", _style(Color(0.028, 0.034, 0.057, 0.94), Color(0.22, 0.27, 0.39, 0.52), 16))
	body.add_child(nav_panel)
	var nav_margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		nav_margin.add_theme_constant_override(side, 10)
	nav_panel.add_child(nav_margin)
	var nav := VBoxContainer.new()
	nav.name = "SettingsNavigation"
	nav.add_theme_constant_override("separation", 6)
	nav_margin.add_child(nav)
	_build_nav_buttons(nav)

	page_stack = TabContainer.new()
	page_stack.name = "SettingsPages"
	page_stack.tabs_visible = false
	page_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(page_stack)

func _build_mobile_navigation(root: VBoxContainer) -> void:
	var nav_scroll := ScrollContainer.new()
	nav_scroll.name = "SettingsMobileNavigationScroll"
	nav_scroll.custom_minimum_size.y = 54
	nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	nav_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(nav_scroll)
	mobile_nav = HFlowContainer.new()
	mobile_nav.name = "SettingsMobileNavigation"
	mobile_nav.add_theme_constant_override("h_separation", 6)
	mobile_nav.add_theme_constant_override("v_separation", 6)
	nav_scroll.add_child(mobile_nav)
	_build_nav_buttons(mobile_nav)

	page_stack = TabContainer.new()
	page_stack.name = "SettingsPages"
	page_stack.tabs_visible = false
	page_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(page_stack)

func _build_nav_buttons(parent: Container) -> void:
	_add_nav_button(parent, "general", "Основное")
	_add_nav_button(parent, "voice", "Голос")
	_add_nav_button(parent, "files", "Файлы и проекты")
	_add_nav_button(parent, "autonomy", "Автономность")
	_add_nav_button(parent, "tools", "Инструменты")
	_add_nav_button(parent, "updates", "Обновления")

func _add_nav_button(parent: Container, key: String, text: String) -> void:
	var button := Button.new()
	button.name = "SettingsNav_" + key
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT if not _is_mobile_layout() else HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not _is_mobile_layout() else Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(func(): _select_page(key))
	parent.add_child(button)
	nav_buttons.append(button)
	nav_keys.append(key)
	_style_nav_button(button, false)

func _style_nav_button(button: Button, selected: bool) -> void:
	var fill := Color(0.10, 0.065, 0.17, 0.98) if selected else Color(0.025, 0.031, 0.052, 0.72)
	var border := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.72) if selected else Color(0.22, 0.27, 0.39, 0.45)
	button.add_theme_stylebox_override("normal", _style(fill, border, 11))
	button.add_theme_stylebox_override("hover", _style(SURFACE_HOVER, Color(CYAN.r, CYAN.g, CYAN.b, 0.58), 11))
	button.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.09, 0.23, 1.0), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.90), 11))
	button.add_theme_color_override("font_color", WHITE if selected else Color("c3ccdc"))
	button.add_theme_font_size_override("font_size", 14)

func _build_pages() -> void:
	if page_stack == null:
		return
	_build_general_page(_page("general", "Основное", "Состояние AuroraFox Core и локальных модулей."))
	_build_voice_page(_page("voice", "Голос", "Микрофон, озвучивание и параметры локального голоса."))
	_build_files_page(_page("files", "Файлы и проекты", "Локальный разбор файлов и доступ к выбранным рабочим папкам."))
	_build_autonomy_page(_page("autonomy", "Автономность", "Управление обучением, циклами анализа и проверенными улучшениями."))
	_build_tools_page(_page("tools", "Инструменты", "Отдельные рабочие поверхности AuroraFox без лишних кнопок в чате."))
	_build_updates_page(_page("updates", "Обновления", "Проверенные stable-обновления и безопасное применение пакетов."))

func _page(key: String, title_text: String, subtitle_text: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsPage_" + key
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_stack.add_child(scroll)
	var index := page_stack.get_child_count() - 1
	nav_indices[key] = index

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", WHITE)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = subtitle_text
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", MUTED)
	box.add_child(subtitle)
	return box

func _select_page(key: String) -> void:
	if page_stack == null or not nav_indices.has(key):
		return
	page_stack.current_tab = int(nav_indices[key])
	for i in range(nav_buttons.size()):
		_style_nav_button(nav_buttons[i], nav_keys[i] == key)

func _add_card(parent: VBoxContainer, title_text: String, subtitle_text := "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(SURFACE, Color(0.25, 0.30, 0.43, 0.54), 16))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", WHITE)
	box.add_child(title)
	if not subtitle_text.is_empty():
		var subtitle := Label.new()
		subtitle.text = subtitle_text
		subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		subtitle.add_theme_font_size_override("font_size", 12)
		subtitle.add_theme_color_override("font_color", MUTED)
		box.add_child(subtitle)
	return box

func _build_general_page(page: VBoxContainer) -> void:
	var core := _add_card(page, "AuroraFox Core", "Собственный локальный Core является основным интеллектом приложения. Отдельная внешняя модель для обычной работы не требуется.")
	core_status = Label.new()
	core_status.name = "SettingsCoreStatus"
	core_status.text = "Проверяю локальный Core…"
	core_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	core.add_child(core_status)

	var local := _add_card(page, "Локальные модули", "Если дополнительный модуль временно недоступен, основной чат продолжает работать через AuroraFox Core.")
	voice_status = Label.new()
	voice_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	local.add_child(voice_status)
	file_status = Label.new()
	file_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	local.add_child(file_status)
	var refresh := Button.new()
	refresh.text = "Обновить состояние"
	refresh.pressed.connect(func(): await _sync_status())
	local.add_child(refresh)

func _build_voice_page(page: VBoxContainer) -> void:
	var basic := _add_card(page, "Основные параметры")
	var voice_enabled := CheckButton.new()
	voice_enabled.text = "Включить голос AuroraFox"
	voice_enabled.button_pressed = bool(AuroraVoice.settings.get("enabled", true))
	voice_enabled.toggled.connect(func(v): AuroraVoice.set_enabled(v))
	basic.add_child(voice_enabled)

	var speak := CheckButton.new()
	speak.text = "Озвучивать ответы"
	speak.button_pressed = bool(AuroraVoice.settings.get("auto_speak", true))
	speak.toggled.connect(func(v): AuroraVoice.set_auto_speak(v))
	basic.add_child(speak)
	basic.add_child(_slider_row("Громкость", float(AuroraVoice.settings.get("volume", 0.86)), 0.0, 1.0, 0.01, func(v): AuroraVoice.set_volume(v)))
	basic.add_child(_slider_row("Скорость речи", float(AuroraVoice.settings.get("speed", 1.0)), 0.82, 1.20, 0.01, func(v): AuroraVoice.update_setting("speed", v)))
	basic.add_child(_slider_row("Механический оттенок", float(AuroraVoice.settings.get("mechanical_amount", 0.035)), 0.0, 0.10, 0.005, func(v): AuroraVoice.update_setting("mechanical_amount", v)))

	var mic := _add_card(page, "Микрофон")
	var mic_row := HBoxContainer.new()
	mic_row.add_theme_constant_override("separation", 10)
	mic.add_child(mic_row)
	var mic_label := Label.new()
	mic_label.text = "Режим"
	mic_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mic_row.add_child(mic_label)
	var mic_mode := OptionButton.new()
	var modes := [["Выкл.", "off"], ["Fox / Лиса", "wake_word"], ["Постоянный диалог", "continuous"], ["Push-to-talk", "push_to_talk"]]
	var current_mode := str(AuroraVoice.settings.get("mic_mode", "wake_word"))
	for i in range(modes.size()):
		mic_mode.add_item(str(modes[i][0]))
		mic_mode.set_item_metadata(i, modes[i][1])
		if str(modes[i][1]) == current_mode:
			mic_mode.selected = i
	mic_mode.item_selected.connect(func(index): AuroraVoice.set_mic_mode(str(mic_mode.get_item_metadata(index))))
	mic_row.add_child(mic_mode)

	var prepare := Button.new()
	prepare.text = "Подготовить или восстановить голосовой модуль"
	prepare.visible = OS.get_name() == "Windows"
	prepare.pressed.connect(func(): _show_setup_node("VoiceSetup"))
	mic.add_child(prepare)

func _build_files_page(page: VBoxContainer) -> void:
	var files := _add_card(page, "File Intelligence", "Локальный разбор документов, таблиц, презентаций и других поддерживаемых файлов.")
	var file_buttons := HFlowContainer.new()
	file_buttons.add_theme_constant_override("h_separation", 8)
	file_buttons.add_theme_constant_override("v_separation", 8)
	files.add_child(file_buttons)
	var prepare_files := Button.new()
	prepare_files.text = "Подготовить модуль"
	prepare_files.visible = OS.get_name() == "Windows"
	prepare_files.pressed.connect(func(): _show_setup_node("FileSetup"))
	file_buttons.add_child(prepare_files)
	var clear_files := Button.new()
	clear_files.text = "Очистить кэш"
	clear_files.pressed.connect(_clear_file_cache)
	file_buttons.add_child(clear_files)
	var refresh_files := Button.new()
	refresh_files.text = "Проверить состояние"
	refresh_files.pressed.connect(_refresh_file_status)
	file_buttons.add_child(refresh_files)

	var projects := _add_card(page, "Проекты и кодовая база", "AuroraFox получает доступ только к папкам, которые пользователь выбрал явно. Индекс хранится локально.")
	project_select = OptionButton.new()
	project_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	projects.add_child(project_select)
	project_status = Label.new()
	project_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	projects.add_child(project_status)
	var project_buttons := HFlowContainer.new()
	project_buttons.visible = OS.get_name() == "Windows"
	project_buttons.add_theme_constant_override("h_separation", 8)
	project_buttons.add_theme_constant_override("v_separation", 8)
	projects.add_child(project_buttons)
	var add_project := Button.new()
	add_project.text = "Добавить папку"
	add_project.pressed.connect(func(): project_picker.popup_centered_ratio(0.72))
	project_buttons.add_child(add_project)
	var reindex := Button.new()
	reindex.text = "Обновить индекс"
	reindex.pressed.connect(_index_selected_project)
	project_buttons.add_child(reindex)
	var remove_project := Button.new()
	remove_project.text = "Убрать доступ"
	remove_project.pressed.connect(_remove_selected_project)
	project_buttons.add_child(remove_project)
	if OS.get_name() != "Windows":
		var platform_hint := Label.new()
		platform_hint.text = "Управление доверенными папками проекта выполняется в Windows-клиенте."
		platform_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		platform_hint.add_theme_font_size_override("font_size", 12)
		platform_hint.add_theme_color_override("font_color", MUTED)
		projects.add_child(platform_hint)

func _build_autonomy_page(page: VBoxContainer) -> void:
	var autonomy_card := _add_card(page, "Автономное развитие", "Каждый кандидат проходит обязательные ограничения и проверки. Пользовательский master stop и откат сохраняются.")
	var autonomy := _autonomy_settings()
	var settings := autonomy.get_settings() if autonomy != null else {}
	var master := CheckButton.new()
	master.text = "Автономное обучение и развитие"
	master.button_pressed = bool(settings.get("master_enabled", true))
	master.disabled = autonomy == null
	master.toggled.connect(func(v): if autonomy != null: autonomy.set_master_enabled(v))
	autonomy_card.add_child(master)
	var learning := CheckButton.new()
	learning.text = "Пополнять Core Knowledge из проверенных исследований"
	learning.button_pressed = bool(settings.get("autonomous_learning", true))
	learning.disabled = autonomy == null
	learning.toggled.connect(func(v): if autonomy != null: autonomy.set_autonomous_learning(v))
	autonomy_card.add_child(learning)
	var cycles := CheckButton.new()
	cycles.text = "Запускать автономные циклы анализа"
	cycles.button_pressed = bool(settings.get("autonomous_cycles", true))
	cycles.disabled = autonomy == null
	cycles.toggled.connect(func(v): if autonomy != null: autonomy.set_autonomous_cycles(v))
	autonomy_card.add_child(cycles)
	var hot := CheckButton.new()
	hot.text = "Активировать только прошедшие проверки runtime-улучшения"
	hot.button_pressed = bool(settings.get("hot_improvements", true))
	hot.disabled = autonomy == null
	hot.toggled.connect(func(v): if autonomy != null: autonomy.set_hot_improvements(v))
	autonomy_card.add_child(hot)
	var core := CheckButton.new()
	core.text = "Создавать проверяемые кандидаты изменения ядра"
	core.button_pressed = bool(settings.get("core_candidates", true))
	core.disabled = autonomy == null
	core.toggled.connect(func(v): if autonomy != null: autonomy.set_core_candidates(v))
	autonomy_card.add_child(core)
	var dev_apply := CheckButton.new()
	dev_apply.text = "В dev/editor автоматически применять проверенного кандидата"
	dev_apply.button_pressed = bool(settings.get("auto_apply_dev_checkout", true))
	dev_apply.disabled = autonomy == null
	dev_apply.visible = OS.has_feature("editor")
	dev_apply.toggled.connect(func(v): if autonomy != null: autonomy.set_auto_apply_dev_checkout(v))
	autonomy_card.add_child(dev_apply)

	var status_card := _add_card(page, "Состояние")
	improvement_status = Label.new()
	improvement_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_card.add_child(improvement_status)
	var improvement_button := Button.new()
	improvement_button.text = "Открыть центр самоулучшения"
	improvement_button.pressed.connect(_open_self_improvement)
	status_card.add_child(improvement_button)

func _build_tools_page(page: VBoxContainer) -> void:
	var knowledge := _add_card(page, "База знаний", "Импорт документов, баз, шаблонов и алгоритмов в локальное Core Knowledge.")
	var knowledge_button := Button.new()
	knowledge_button.text = "Открыть базу знаний"
	knowledge_button.pressed.connect(func(): _open_surface("KnowledgeBase", "show_knowledge_base"))
	knowledge.add_child(knowledge_button)

	if OS.get_name() == "Windows":
		var computer := _add_card(page, "Компьютерный режим", "Отдельное явное разрешение на экран, мышь и клавиатуру. Без включения доступа действия запрещены.")
		var computer_button := Button.new()
		computer_button.text = "Настроить компьютерный режим"
		computer_button.pressed.connect(func(): _open_surface("ComputerOverlay", "show_computer_panel"))
		computer.add_child(computer_button)

		var work := _add_card(page, "Работа", "Длинные задачи, проекты и готовые результаты без перегрузки основного чата.")
		var work_button := Button.new()
		work_button.text = "Открыть Работу"
		work_button.pressed.connect(func(): _open_surface("WorkOverlay", "show_work"))
		work.add_child(work_button)

		var api := _add_card(page, "API и интеграции", "Локальные ключи и подключение приложений к тому же AgentCore и памяти AuroraFox.")
		var api_button := Button.new()
		api_button.text = "Открыть API и интеграции"
		api_button.pressed.connect(func(): _open_surface("ApiSettings", "show_api_settings"))
		api.add_child(api_button)
	else:
		var mobile_note := _add_card(page, "Мобильная версия", "На Android здесь показываются только реально поддерживаемые локальные инструменты. Desktop-only функции не рисуются пустыми кнопками.")
		var note := Label.new()
		note.text = "Компьютерный режим, Work и локальный API доступны в Windows-клиенте."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", MUTED)
		mobile_note.add_child(note)

func _build_updates_page(page: VBoxContainer) -> void:
	var update_settings := AuroraUpdate.get_settings()
	var card := _add_card(page, "Stable-канал", "Пакеты проходят проверку целостности и доверия. Ошибка сети не мешает работе текущей локальной версии.")
	var auto_check := CheckButton.new()
	auto_check.text = "Автоматически проверять обновления"
	auto_check.button_pressed = bool(update_settings.get("auto_check", true))
	auto_check.toggled.connect(func(v): AuroraUpdate.set_auto_check(v))
	card.add_child(auto_check)
	var auto_download := CheckButton.new()
	auto_download.text = "Автоматически скачивать проверенные обновления"
	auto_download.button_pressed = bool(update_settings.get("auto_download", true))
	auto_download.toggled.connect(func(v): AuroraUpdate.set_auto_download(v))
	card.add_child(auto_download)
	var auto_apply := CheckButton.new()
	auto_apply.text = "Автоматически применять проверенные обновления"
	auto_apply.button_pressed = bool(update_settings.get("auto_apply", true))
	auto_apply.toggled.connect(func(v): AuroraUpdate.set_auto_apply(v))
	card.add_child(auto_apply)
	update_status = Label.new()
	update_status.text = "Канал: stable"
	update_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_status.add_theme_color_override("font_color", MUTED)
	card.add_child(update_status)
	var update_button := Button.new()
	update_button.text = "Проверить обновления сейчас"
	update_button.pressed.connect(_check_updates)
	card.add_child(update_button)

func _slider_row(label_text: String, initial: float, minimum: float, maximum: float, step: float, changed: Callable) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	root.add_child(top)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(label)
	var value_label := Label.new()
	value_label.text = "%.2f" % initial
	value_label.custom_minimum_size.x = 52
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", MUTED)
	top.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(changed)
	slider.value_changed.connect(func(v): value_label.text = "%.2f" % v)
	root.add_child(slider)
	return root

func _show_setup_node(name: String) -> void:
	var main := get_parent()
	if main == null:
		return
	var node := main.get_node_or_null(name)
	if node == null:
		return
	if node.has_method("show_setup"):
		popup.hide()
		node.call("show_setup")
		return
	var setup_popup = node.get("popup")
	if setup_popup is PopupPanel:
		popup.hide()
		setup_popup.popup_centered()

func _open_surface(node_name: String, method_name: String) -> void:
	var main := get_parent()
	if main == null:
		return
	var node := main.get_node_or_null(node_name)
	if node == null or not node.has_method(method_name):
		return
	popup.hide()
	node.call(method_name)

func _sync_status() -> void:
	if voice_status != null:
		voice_status.text = "Голосовой модуль: %s" % ("готов" if AuroraVoice.backend_is_ready else "не подключён")
	await _sync_core_status()
	await _refresh_file_status()
	await _refresh_index_status()
	_sync_improvement_status()

func _sync_core_status() -> void:
	if core_status == null:
		return
	var main := get_parent()
	if main == null:
		core_status.text = "AuroraFox Core: интерфейс не подключён"
		return
	var ai = main.get("ai")
	if not ai is AIClient:
		core_status.text = "AuroraFox Core: клиент не подключён"
		return
	var available := await ai.is_available()
	core_status.text = "AuroraFox Core: готов и используется как основной локальный интеллект" if available else "AuroraFox Core: запускается; внешний AI не подменяет основной режим"
	core_status.add_theme_color_override("font_color", GREEN if available else WARNING)

func _refresh_file_status() -> void:
	if file_status == null:
		return
	var main := get_parent()
	if main == null:
		return
	var manager = main.get("attachments")
	if not manager is AttachmentManager:
		file_status.text = "File Intelligence: менеджер не подключён"
		return
	var result: Dictionary = await manager.intelligence.health()
	if not result.get("ok", false):
		file_status.text = "File Intelligence: требуется подготовка" if OS.get_name() == "Windows" else "File Intelligence: Android runtime недоступен"
		return
	if OS.get_name() == "Android":
		file_status.text = "File Intelligence: Android native • PDF/DOCX/XLSX/PPTX/ZIP • image-only OCR пока ограничен"
	else:
		file_status.text = "File Intelligence: готов • vision %s • voice/STT %s" % [
			"подключено" if result.get("vision_online", false) else "не подключено",
			"подключено" if result.get("voice_online", false) else "не подключено"
		]

func _clear_file_cache() -> void:
	var main := get_parent()
	if main == null:
		return
	var manager = main.get("attachments")
	if manager is AttachmentManager:
		var result: Dictionary = await manager.clear_file_cache()
		if file_status != null:
			file_status.text = ("Кэш файлов очищен" if OS.get_name() == "Android" else "Кэш очищен: %s" % str(result.get("removed", 0))) if result.get("ok", false) else "Не удалось очистить кэш"

func _project_bridge() -> ProjectIndexToolBridge:
	var main := get_parent()
	if main == null:
		return null
	return main.get_node_or_null("ProjectIndexTools") as ProjectIndexToolBridge

func _refresh_project_list() -> void:
	if project_select == null:
		return
	project_select.clear()
	var bridge := _project_bridge()
	if bridge == null:
		if project_status != null:
			project_status.text = "Индекс проектов: модуль не подключён"
		return
	var roots := bridge.access.all_roots()
	for root in roots:
		project_select.add_item(str(root).get_file() if not str(root).get_file().is_empty() else str(root))
		project_select.set_item_metadata(project_select.item_count - 1, root)
	if roots.is_empty():
		project_select.add_item("Нет доверенных папок")
		project_select.set_item_disabled(0, true)
		if project_status != null:
			project_status.text = "Выбери локальную папку проекта для индексирования." if OS.get_name() == "Windows" else "Доверенные папки проекта настраиваются в Windows-клиенте."
	else:
		_refresh_index_status()

func _selected_project() -> String:
	if project_select == null or project_select.item_count == 0:
		return ""
	var value = project_select.get_item_metadata(project_select.selected)
	return str(value) if value != null else ""

func _on_project_selected(path: String) -> void:
	var bridge := _project_bridge()
	if bridge == null:
		return
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
		if project_status != null:
			project_status.text = "Сначала выбери папку проекта."
		return
	project_status.text = "Индексирую изменившиеся файлы…"
	var result: Dictionary = await bridge.index.index_project(root, 30000, false)
	if result.get("ok", false):
		project_status.text = "Индекс готов: %d файлов • обновлено %d • %d мс" % [int(result.get("total_files", 0)), int(result.get("updated_files", 0)), int(result.get("elapsed_ms", 0))]
	else:
		project_status.text = "Ошибка индекса: %s" % str(result.get("error", "unknown"))

func _refresh_index_status() -> void:
	if project_status == null:
		return
	var root := _selected_project()
	var bridge := _project_bridge()
	if root.is_empty() or bridge == null:
		return
	var result: Dictionary = await bridge.index.status(root)
	if result.get("ok", false):
		project_status.text = "Индекс: %d файлов • %s" % [int(result.get("files", 0)), JSON.stringify(result.get("languages", {}))]

func _remove_selected_project() -> void:
	var root := _selected_project()
	var bridge := _project_bridge()
	if root.is_empty() or bridge == null:
		return
	await bridge.index.clear(root)
	bridge.access.remove_root(root)
	_refresh_project_list()

func _runtime_extensions() -> RuntimeExtensionManager:
	var main := get_parent()
	if main == null:
		return null
	return main.get_node_or_null("RuntimeExtensions") as RuntimeExtensionManager

func _autonomy_settings() -> AutonomySettingsManager:
	var main := get_parent()
	if main == null:
		return null
	return main.get_node_or_null("AutonomySettings") as AutonomySettingsManager

func _sync_improvement_status() -> void:
	if improvement_status == null:
		return
	var manager := _runtime_extensions()
	var autonomy := _autonomy_settings()
	if manager == null:
		improvement_status.text = "Runtime-расширения: менеджер не подключён"
		return
	var items := manager.list_extensions()
	var active := 0
	for item in items:
		if bool(item.get("active", false)):
			active += 1
	var mode := "управление автономностью ещё подключается"
	if autonomy != null:
		var state := autonomy.status()
		mode = "автономность включена" if bool(state.get("master_enabled", true)) else "автономность полностью остановлена пользователем"
	improvement_status.text = "%s • runtime-расширения %d/%d • sandbox-проверка: %s" % [mode, active, items.size(), "Godot 4.7.1 / Windows" if OS.get_name() == "Windows" else "кандидаты ядра не применяются на этой платформе"]

func _open_self_improvement() -> void:
	_open_surface("SelfImprovementCenter", "show_center")

func _check_updates() -> void:
	if update_status != null:
		update_status.text = "Проверяю подписанный stable-релиз…"
	await AuroraUpdate.check_for_updates(true)
