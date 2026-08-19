extends Control

signal ai_working_started(state: String)
signal ai_working_finished
signal assistant_response_ready(text: String)
signal user_message_submitted(text: String)

var ai := AIClient.new()
var memory := MemoryStore.new()
var tools := ToolRegistry.new()
var agent := AgentCore.new()
var improver := SelfImprover.new()
var chats := ChatStore.new()
var attachments := AttachmentManager.new()

var chat_list: VBoxContainer
var message_scroll: ScrollContainer
var message_list: VBoxContainer
var input: TextEdit
var status: Label
var active_title: Label
var file_dialog: FileDialog
var pending_attachments: Array = []
var attachment_bar: HBoxContainer
var request_busy := false
var file_processing_busy := false
var queued_voice_text := ""
var rename_dialog: AcceptDialog
var rename_input: LineEdit
var rename_target_id := ""

const BACKGROUND: Texture2D = preload("res://assets/ui/aurora_background.svg")
const FOX_LOGO: Texture2D = preload("res://assets/ui/fox_logo.svg")
const ICON_NEW_CHAT: Texture2D = preload("res://assets/ui/icon_new_chat.svg")
const ICON_SEARCH: Texture2D = preload("res://assets/ui/icon_search.svg")
const ICON_SETTINGS: Texture2D = preload("res://assets/ui/icon_settings.svg")
const ICON_ATTACH: Texture2D = preload("res://assets/ui/icon_attach.svg")
const ICON_SEND: Texture2D = preload("res://assets/ui/icon_send.svg")
const ICON_RENAME: Texture2D = preload("res://assets/ui/icon_rename.svg")
const ICON_DELETE: Texture2D = preload("res://assets/ui/icon_delete.svg")

const BG := Color("080b12")
const SIDEBAR := Color(0.025, 0.032, 0.055, 0.97)
const SURFACE := Color(0.055, 0.066, 0.10, 0.94)
const SURFACE_2 := Color(0.075, 0.09, 0.135, 0.96)
const USER_BUBBLE := Color(0.08, 0.17, 0.25, 0.96)
const ASSISTANT_BUBBLE := Color(0.085, 0.07, 0.135, 0.96)
const ACCENT := Color("a98aff")
const CYAN := Color("45d8ff")
const GREEN := Color("64ff9d")
const DANGER := Color("ff6d82")
const MUTED := Color("8d98ad")
const WHITE := Color("f3f6ff")
const BORDER := Color(0.34, 0.39, 0.55, 0.45)

func _ready() -> void:
	add_child(ai)
	add_child(memory)
	add_child(tools)
	add_child(agent)
	add_child(improver)
	add_child(chats)
	add_child(attachments)
	agent.setup(ai, memory, tools)
	improver.setup(tools, ai)
	_build_ui()
	if not get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.connect(_on_files_dropped)
	if not get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.connect(_on_viewport_resized)
	_refresh_chat_list()
	_render_active_chat()
	await get_tree().process_frame
	var available := await ai.is_available()
	_set_status(
		"Модель подключена • %s • %d инструментов" % [ai.model, tools.tools.size()] if available
		else "Локальная модель не подключена — откройте подготовку AI",
		available
	)

func _style(fill: Color, border: Color = Color.TRANSPARENT, radius := 16, border_width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _apply_button(button: Button, accent := false, danger := false, compact := false) -> void:
	var normal := SURFACE_2 if not accent else Color(0.18, 0.11, 0.30, 0.98)
	var hover := Color(0.12, 0.14, 0.21, 0.99)
	var pressed := Color(0.15, 0.11, 0.23, 1.0)
	var border := BORDER
	if accent:
		border = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.8)
		hover = Color(0.23, 0.15, 0.36, 1.0)
	if danger:
		border = Color(DANGER.r, DANGER.g, DANGER.b, 0.55)
		hover = Color(0.27, 0.09, 0.13, 0.98)
	button.add_theme_stylebox_override("normal", _style(normal, border, 12, 1))
	button.add_theme_stylebox_override("hover", _style(hover, border, 12, 1))
	button.add_theme_stylebox_override("pressed", _style(pressed, border, 12, 1))
	button.add_theme_stylebox_override("focus", _style(hover, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.95), 12, 1))
	button.add_theme_stylebox_override("disabled", _style(Color(0.06, 0.07, 0.09, 0.72), Color(0.18, 0.20, 0.25, 0.55), 12, 1))
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_color_override("font_hover_color", WHITE)
	button.add_theme_color_override("font_pressed_color", WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.55, 0.75))
	button.add_theme_font_size_override("font_size", 14 if compact else 15)
	button.expand_icon = true
	button.icon_max_width = 19 if compact else 22

func _apply_input_style(control: Control) -> void:
	control.add_theme_stylebox_override("normal", _style(Color(0.035, 0.043, 0.068, 0.98), BORDER, 15, 1))
	control.add_theme_stylebox_override("focus", _style(Color(0.045, 0.052, 0.08, 1.0), Color(CYAN.r, CYAN.g, CYAN.b, 0.72), 15, 1))
	control.add_theme_color_override("font_color", WHITE)
	control.add_theme_color_override("font_placeholder_color", MUTED)

func _build_ui() -> void:
	var base := ColorRect.new()
	base.color = BG
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	var background := TextureRect.new()
	background.texture = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.modulate = Color(1, 1, 1, 0.82)
	add_child(background)

	var veil := ColorRect.new()
	veil.color = Color(0.01, 0.015, 0.028, 0.34)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var root := HBoxContainer.new()
	root.name = "RootLayout"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var sidebar_bg := ColorRect.new()
	sidebar_bg.name = "Sidebar"
	sidebar_bg.color = SIDEBAR
	sidebar_bg.custom_minimum_size.x = 286
	root.add_child(sidebar_bg)

	var sidebar_margin := MarginContainer.new()
	sidebar_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sidebar_margin.add_theme_constant_override("margin_left", 16)
	sidebar_margin.add_theme_constant_override("margin_right", 16)
	sidebar_margin.add_theme_constant_override("margin_top", 18)
	sidebar_margin.add_theme_constant_override("margin_bottom", 16)
	sidebar_bg.add_child(sidebar_margin)

	var sidebar := VBoxContainer.new()
	sidebar.add_theme_constant_override("separation", 10)
	sidebar_margin.add_child(sidebar)

	var brand_row := HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 10)
	sidebar.add_child(brand_row)
	var logo := TextureRect.new()
	logo.texture = FOX_LOGO
	logo.custom_minimum_size = Vector2(52, 52)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand_row.add_child(logo)
	var brand_text := VBoxContainer.new()
	brand_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand_row.add_child(brand_text)
	var brand := Label.new()
	brand.text = "AuroraFox"
	brand.add_theme_font_size_override("font_size", 23)
	brand.add_theme_color_override("font_color", WHITE)
	brand_text.add_child(brand)
	var version := Label.new()
	version.text = _current_version()
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", ACCENT)
	brand_text.add_child(version)

	var new_chat := Button.new()
	new_chat.name = "NewChatButton"
	new_chat.text = "Новый чат"
	new_chat.icon = ICON_NEW_CHAT
	new_chat.alignment = HORIZONTAL_ALIGNMENT_LEFT
	new_chat.custom_minimum_size.y = 48
	new_chat.pressed.connect(_new_chat)
	_apply_button(new_chat, true)
	sidebar.add_child(new_chat)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	sidebar.add_child(search_row)
	var search_icon := TextureRect.new()
	search_icon.texture = ICON_SEARCH
	search_icon.custom_minimum_size = Vector2(22, 22)
	search_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	search_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	search_icon.modulate = Color(1, 1, 1, 0.74)
	search_row.add_child(search_icon)
	var search := LineEdit.new()
	search.name = "ChatSearch"
	search.placeholder_text = "Поиск по чатам"
	search.custom_minimum_size.y = 42
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(q): _refresh_chat_list(q))
	_apply_input_style(search)
	search_row.add_child(search)

	var history_title := Label.new()
	history_title.text = "ИСТОРИЯ"
	history_title.add_theme_font_size_override("font_size", 11)
	history_title.add_theme_color_override("font_color", Color(0.58, 0.62, 0.72, 0.9))
	sidebar.add_child(history_title)

	var scroll := ScrollContainer.new()
	scroll.name = "ChatHistoryScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	chat_list = VBoxContainer.new()
	chat_list.name = "ChatList"
	chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_list.add_theme_constant_override("separation", 6)
	scroll.add_child(chat_list)

	var settings_button := Button.new()
	settings_button.name = "SettingsButton"
	settings_button.text = "Настройки"
	settings_button.icon = ICON_SETTINGS
	settings_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	settings_button.custom_minimum_size.y = 44
	settings_button.pressed.connect(_show_tools_info)
	_apply_button(settings_button)
	sidebar.add_child(settings_button)

	var main_panel := VBoxContainer.new()
	main_panel.name = "MainPanel"
	main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_panel.add_theme_constant_override("separation", 0)
	root.add_child(main_panel)

	var header_panel := PanelContainer.new()
	header_panel.custom_minimum_size.y = 70
	header_panel.add_theme_stylebox_override("panel", _style(Color(0.025, 0.03, 0.05, 0.88), Color(0.24, 0.27, 0.38, 0.35), 0, 0))
	main_panel.add_child(header_panel)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 24)
	header_margin.add_theme_constant_override("margin_right", 20)
	header_margin.add_theme_constant_override("margin_top", 11)
	header_margin.add_theme_constant_override("margin_bottom", 10)
	header_panel.add_child(header_margin)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header_margin.add_child(header)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	active_title = Label.new()
	active_title.text = "Новый чат"
	active_title.add_theme_font_size_override("font_size", 20)
	active_title.add_theme_color_override("font_color", WHITE)
	title_box.add_child(active_title)
	status = Label.new()
	status.text = "Инициализация…"
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", MUTED)
	title_box.add_child(status)
	var header_actions := HBoxContainer.new()
	header_actions.name = "MainHeaderActions"
	header_actions.alignment = BoxContainer.ALIGNMENT_END
	header_actions.add_theme_constant_override("separation", 8)
	header.add_child(header_actions)
	var avatar_slot := Control.new()
	avatar_slot.name = "AvatarSlot"
	avatar_slot.custom_minimum_size = Vector2(58, 48)
	header_actions.add_child(avatar_slot)

	var messages_margin := MarginContainer.new()
	messages_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	messages_margin.add_theme_constant_override("margin_left", 26)
	messages_margin.add_theme_constant_override("margin_right", 26)
	messages_margin.add_theme_constant_override("margin_top", 18)
	messages_margin.add_theme_constant_override("margin_bottom", 8)
	main_panel.add_child(messages_margin)
	message_scroll = ScrollContainer.new()
	message_scroll.name = "MessageScroll"
	message_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	messages_margin.add_child(message_scroll)
	message_list = VBoxContainer.new()
	message_list.name = "MessageList"
	message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_list.add_theme_constant_override("separation", 14)
	message_scroll.add_child(message_list)

	var composer_margin := MarginContainer.new()
	composer_margin.name = "ComposerMargin"
	composer_margin.add_theme_constant_override("margin_left", 24)
	composer_margin.add_theme_constant_override("margin_right", 24)
	composer_margin.add_theme_constant_override("margin_top", 8)
	composer_margin.add_theme_constant_override("margin_bottom", 20)
	main_panel.add_child(composer_margin)
	var composer_panel := PanelContainer.new()
	composer_panel.add_theme_stylebox_override("panel", _style(Color(0.025, 0.032, 0.052, 0.96), Color(0.28, 0.32, 0.46, 0.6), 20, 1))
	composer_margin.add_child(composer_panel)
	var composer_inner := MarginContainer.new()
	composer_inner.add_theme_constant_override("margin_left", 10)
	composer_inner.add_theme_constant_override("margin_right", 10)
	composer_inner.add_theme_constant_override("margin_top", 8)
	composer_inner.add_theme_constant_override("margin_bottom", 8)
	composer_panel.add_child(composer_inner)
	var composer := VBoxContainer.new()
	composer.add_theme_constant_override("separation", 7)
	composer_inner.add_child(composer)

	attachment_bar = HBoxContainer.new()
	attachment_bar.name = "AttachmentBar"
	attachment_bar.add_theme_constant_override("separation", 6)
	composer.add_child(attachment_bar)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	composer.add_child(input_row)
	var attach := Button.new()
	attach.name = "AttachButton"
	attach.icon = ICON_ATTACH
	attach.tooltip_text = "Прикрепить файлы"
	attach.custom_minimum_size = Vector2(46, 46)
	attach.pressed.connect(_open_file_dialog)
	_apply_button(attach, false, false, true)
	input_row.add_child(attach)

	input = TextEdit.new()
	input.name = "MessageInput"
	input.placeholder_text = "Сообщение AuroraFox…"
	input.custom_minimum_size.y = 72
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.gui_input.connect(_on_input_gui)
	input.add_theme_font_size_override("font_size", 16)
	_apply_input_style(input)
	input_row.add_child(input)

	var voice_dock := HBoxContainer.new()
	voice_dock.name = "VoiceDock"
	voice_dock.add_theme_constant_override("separation", 6)
	input_row.add_child(voice_dock)

	var send := Button.new()
	send.name = "SendButton"
	send.icon = ICON_SEND
	send.tooltip_text = "Отправить"
	send.custom_minimum_size = Vector2(52, 46)
	send.pressed.connect(_submit_current)
	_apply_button(send, true, false, true)
	input_row.add_child(send)

	var hint := Label.new()
	hint.text = "Enter — отправить   •   Shift+Enter — новая строка   •   файлы можно перетащить в окно"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.52, 0.56, 0.66, 0.9))
	composer.add_child(hint)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.files_selected.connect(_on_files_selected)
	add_child(file_dialog)

	rename_dialog = AcceptDialog.new()
	rename_dialog.title = "Переименовать чат"
	rename_dialog.dialog_text = "Введите новое название чата:"
	rename_dialog.min_size = Vector2i(460, 190)
	rename_dialog.confirmed.connect(_confirm_rename_chat)
	add_child(rename_dialog)
	rename_input = LineEdit.new()
	rename_input.position = Vector2(24, 72)
	rename_input.size = Vector2(410, 42)
	rename_input.custom_minimum_size = Vector2(410, 42)
	rename_input.max_length = 60
	rename_input.placeholder_text = "Название чата"
	_apply_input_style(rename_input)
	rename_input.text_submitted.connect(func(_text): rename_dialog.get_ok_button().emit_signal("pressed"))
	rename_dialog.add_child(rename_input)

func _current_version() -> String:
	var value := str(ProjectSettings.get_setting("application/config/version", "1.0.0.0"))
	if not value.to_upper().begins_with("V"):
		value = "V" + value
	return value.to_upper()

func _set_status(text: String, good := false, error := false) -> void:
	if status == null:
		return
	status.text = text
	status.add_theme_color_override("font_color", DANGER if error else (GREEN if good else MUTED))

func _on_viewport_resized() -> void:
	call_deferred("_render_active_chat")

func _new_chat() -> void:
	if request_busy or file_processing_busy:
		return
	AuroraVoice.stop()
	chats.create_chat()
	pending_attachments.clear()
	_refresh_attachment_bar()
	_refresh_chat_list()
	_render_active_chat()
	input.grab_focus()

func _refresh_chat_list(query: String = "") -> void:
	if chat_list == null:
		return
	for child in chat_list.get_children():
		child.queue_free()
	var source: Array = chats.search(query)
	for chat in source:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 4)
		var id := str(chat.get("id", ""))
		var title_text := str(chat.get("title", "Новый чат"))
		var active := id == chats.active_chat_id

		var select := Button.new()
		select.text = title_text
		select.tooltip_text = title_text
		select.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select.custom_minimum_size.y = 40
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_button(select, active, false, true)
		select.pressed.connect(func():
			if request_busy or file_processing_busy:
				return
			chats.active_chat_id = id
			chats.save_all()
			_refresh_chat_list(query)
			_render_active_chat()
		)
		row.add_child(select)

		var rename := Button.new()
		rename.icon = ICON_RENAME
		rename.tooltip_text = "Переименовать чат"
		rename.custom_minimum_size = Vector2(36, 40)
		_apply_button(rename, false, false, true)
		rename.pressed.connect(func(): _open_rename_chat(id, title_text))
		row.add_child(rename)

		var del := Button.new()
		del.icon = ICON_DELETE
		del.tooltip_text = "Удалить чат"
		del.custom_minimum_size = Vector2(36, 40)
		_apply_button(del, false, true, true)
		del.pressed.connect(func():
			if request_busy or file_processing_busy:
				return
			chats.delete_chat(id)
			_refresh_chat_list(query)
			_render_active_chat()
		)
		row.add_child(del)
		chat_list.add_child(row)

func _open_rename_chat(id: String, current_title: String) -> void:
	if request_busy:
		return
	rename_target_id = id
	rename_input.text = current_title
	rename_dialog.popup_centered()
	await get_tree().process_frame
	rename_input.grab_focus()
	rename_input.select_all()

func _confirm_rename_chat() -> void:
	if rename_target_id.is_empty():
		return
	var title_text := rename_input.text.strip_edges()
	if title_text.is_empty():
		return
	chats.rename_chat(rename_target_id, title_text)
	rename_target_id = ""
	_refresh_chat_list()
	_render_active_chat()

func _render_active_chat() -> void:
	if message_list == null:
		return
	for child in message_list.get_children():
		child.queue_free()
	var chat := chats.get_active_chat()
	active_title.text = str(chat.get("title", "Новый чат")) if active_title != null else "Новый чат"
	var messages: Array = chat.get("messages", [])
	if messages.is_empty():
		_add_welcome_state()
	else:
		for message in messages:
			if message is Dictionary:
				_add_message_card(message)
	call_deferred("_scroll_messages_to_bottom")

func _add_welcome_state() -> void:
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size.y = maxf(360.0, get_viewport_rect().size.y * 0.52)
	message_list.add_child(center)
	var logo := TextureRect.new()
	logo.texture = FOX_LOGO
	logo.custom_minimum_size = Vector2(116, 116)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	center.add_child(logo)
	var title := Label.new()
	title.text = "Чем займёмся?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", WHITE)
	center.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Чат, код, файлы, проекты и локальные инструменты — в одном диалоге."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", MUTED)
	center.add_child(subtitle)

func _bubble_width() -> float:
	var width := get_viewport_rect().size.x
	return clampf(width * 0.48, 360.0, 760.0)

func _add_message_card(message: Dictionary) -> void:
	var role := str(message.get("role", "assistant"))
	var is_user := role == "user"
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_END if is_user else BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 9)
	message_list.add_child(row)

	if not is_user:
		var avatar := TextureRect.new()
		avatar.texture = FOX_LOGO
		avatar.custom_minimum_size = Vector2(34, 34)
		avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(avatar)

	var card := PanelContainer.new()
	card.custom_minimum_size.x = _bubble_width()
	card.size_flags_horizontal = Control.SIZE_SHRINK_END if is_user else Control.SIZE_SHRINK_BEGIN
	card.add_theme_stylebox_override("panel", _style(USER_BUBBLE if is_user else ASSISTANT_BUBBLE, Color(CYAN.r, CYAN.g, CYAN.b, 0.34) if is_user else Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.38), 18, 1))
	row.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	margin.add_child(body)
	var meta := Label.new()
	meta.text = ("Вы" if is_user else "AuroraFox") + ("  •  " + str(message.get("time", "")) if not str(message.get("time", "")).is_empty() else "")
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", CYAN if is_user else ACCENT)
	body.add_child(meta)
	var content := RichTextLabel.new()
	content.bbcode_enabled = false
	content.fit_content = true
	content.scroll_active = false
	content.custom_minimum_size.x = _bubble_width() - 44.0
	content.text = str(message.get("content", ""))
	content.add_theme_font_size_override("normal_font_size", 16)
	content.add_theme_color_override("default_color", WHITE)
	body.add_child(content)
	var message_attachments: Array = message.get("attachments", [])
	if not message_attachments.is_empty():
		var files := HFlowContainer.new()
		files.add_theme_constant_override("h_separation", 6)
		files.add_theme_constant_override("v_separation", 6)
		body.add_child(files)
		for item in message_attachments:
			if not item is Dictionary:
				continue
			var chip := Label.new()
			chip.text = str(item.get("name", "file"))
			chip.add_theme_font_size_override("font_size", 11)
			chip.add_theme_color_override("font_color", Color(0.78, 0.84, 0.94, 0.94))
			chip.add_theme_stylebox_override("normal", _style(Color(0.03, 0.04, 0.065, 0.72), Color(0.3, 0.35, 0.48, 0.55), 9, 1))
			files.add_child(chip)

func _scroll_messages_to_bottom() -> void:
	if message_scroll == null:
		return
	await get_tree().process_frame
	var bar := message_scroll.get_v_scroll_bar()
	message_scroll.scroll_vertical = int(bar.max_value)

func _open_file_dialog() -> void:
	if not request_busy and not file_processing_busy:
		file_dialog.popup_centered_ratio(0.72)

func _on_files_selected(paths: PackedStringArray) -> void:
	await _ingest_files(paths)

func _on_files_dropped(paths: PackedStringArray) -> void:
	await _ingest_files(paths)

func _ingest_files(paths: PackedStringArray) -> void:
	if request_busy or file_processing_busy or paths.is_empty():
		return
	file_processing_busy = true
	var failures: Array[String] = []
	for path in paths:
		var duplicate := false
		for existing in pending_attachments:
			if str(existing.get("path", "")) == path:
				duplicate = true
				break
		if duplicate:
			continue
		_set_status("Разбираю файл: %s…" % path.get_file())
		var item := await attachments.analyze(path)
		if item.get("ok", false):
			pending_attachments.append(item)
		else:
			failures.append("%s: %s" % [path.get_file(), str(item.get("error", "анализ не выполнен"))])
	_refresh_attachment_bar()
	file_processing_busy = false
	if failures.is_empty():
		_set_status("Файлы готовы • %d вложений" % pending_attachments.size(), true)
	else:
		_set_status("Не удалось разобрать %d файл(а/ов): %s" % [failures.size(), failures[0]], false, true)

func _refresh_attachment_bar() -> void:
	if attachment_bar == null:
		return
	for child in attachment_bar.get_children():
		child.queue_free()
	for item in pending_attachments:
		var chip := Button.new()
		chip.text = str(item.get("name", "file"))
		chip.tooltip_text = "%s • %s B%s" % [
			item.get("kind", ""), item.get("size", 0),
			" • анализ готов" if bool(item.get("analyzed", false)) else " • анализ ограничен"
		]
		chip.icon = ICON_ATTACH
		_apply_button(chip, false, false, true)
		var target = item
		chip.pressed.connect(func(): pending_attachments.erase(target); _refresh_attachment_bar())
		attachment_bar.add_child(chip)

func _on_input_gui(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER and not event.shift_pressed:
		get_viewport().set_input_as_handled()
		_submit_current()

func submit_voice_text(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	if request_busy or file_processing_busy:
		queued_voice_text = clean
		return
	if input == null:
		return
	input.text = clean
	_submit_current()

func _submit_queued_voice() -> void:
	if request_busy or file_processing_busy or queued_voice_text.is_empty():
		return
	var next := queued_voice_text
	queued_voice_text = ""
	submit_voice_text(next)

func _submit_current() -> void:
	if request_busy:
		return
	if file_processing_busy:
		_set_status("Сначала заканчиваю локальный анализ вложений…")
		return
	var text := input.text.strip_edges()
	if text.is_empty() and pending_attachments.is_empty():
		return
	request_busy = true
	AuroraVoice.stop()
	input.clear()
	var shown := text
	if shown.is_empty():
		shown = "Проанализируй прикреплённые файлы."
	var attachment_copy := pending_attachments.duplicate(true)
	chats.add_message("user", shown, attachment_copy)
	user_message_submitted.emit(shown)
	pending_attachments.clear()
	_refresh_attachment_bar()
	_refresh_chat_list()
	_render_active_chat()
	var work_state := "AI_READING" if not attachment_copy.is_empty() else "AI_WORKING"
	_set_status("AuroraFox думает…")
	ai_working_started.emit(work_state)
	AuroraVoice.set_ai_working(true, work_state)
	var task := shown + attachments.build_context(attachment_copy)
	var answer := await agent.run_task(task)
	AuroraVoice.set_ai_working(false)
	ai_working_finished.emit()
	chats.add_message("assistant", answer)
	_render_active_chat()
	_refresh_chat_list()
	_set_status("Готово • %d инструментов • память %d" % [tools.tools.size(), memory.memory.size()], true)
	assistant_response_ready.emit(answer)
	AuroraVoice.say(answer)
	request_busy = false
	if not queued_voice_text.is_empty():
		call_deferred("_submit_queued_voice")

func _show_tools_info() -> void:
	var settings_panel := get_node_or_null("SettingsOverlay")
	if settings_panel != null and settings_panel.has_method("show_settings"):
		settings_panel.call("show_settings")
