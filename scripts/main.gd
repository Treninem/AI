extends Control

var ai := AIClient.new()
var memory := MemoryStore.new()
var tools := ToolRegistry.new()
var agent := AgentCore.new()
var improver := SelfImprover.new()
var chats := ChatStore.new()
var attachments := AttachmentManager.new()

var chat_list: VBoxContainer
var output: RichTextLabel
var input: TextEdit
var status: Label
var file_dialog: FileDialog
var pending_attachments: Array = []
var attachment_bar: HBoxContainer

const CHAT_BACKGROUND: Texture2D = preload("res://assets/chat_background.webp")
const UI_ATLAS: Texture2D = preload("res://assets/ui_atlas.webp")

const BG := Color("070b14")
const SIDEBAR := Color(0.025, 0.03, 0.075, 0.93)
const ACCENT := Color("a66cff")
const CYAN := Color("32c9ff")
const MUTED := Color("8993aa")
const WHITE := Color("eef5ff")

# Координаты относятся к уменьшенному атласу 768x512.
const REGION_PANEL_PURPLE := Rect2(16, 20, 358, 95)
const REGION_PANEL_CYAN := Rect2(395, 20, 357, 95)
const REGION_BUTTON_PURPLE := Rect2(17, 456, 135, 38)
const REGION_BUTTON_PURPLE_ALT := Rect2(167, 456, 135, 38)
const REGION_BUTTON_CYAN := Rect2(326, 456, 142, 38)
const REGION_BUTTON_CYAN_ALT := Rect2(482, 456, 131, 38)
const REGION_BUTTON_CYAN_NEXT := Rect2(626, 456, 124, 38)

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
	_refresh_chat_list()
	_render_active_chat()
	await get_tree().process_frame
	var available := await ai.is_available()
	status.text = "● %s   %s   •   %d инструментов" % ["модель подключена" if available else "модель не подключена", ai.model, tools.tools.size()]

func _atlas_texture(region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = UI_ATLAS
	texture.region = region
	return texture

func _atlas_style(region: Rect2, texture_margin := 14.0, content_margin := 10.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _atlas_texture(region)
	style.texture_margin_left = texture_margin
	style.texture_margin_right = texture_margin
	style.texture_margin_top = texture_margin
	style.texture_margin_bottom = texture_margin
	style.content_margin_left = content_margin
	style.content_margin_right = content_margin
	style.content_margin_top = content_margin * 0.55
	style.content_margin_bottom = content_margin * 0.55
	return style

func _apply_neon_button(button: Button, cyan := false) -> void:
	var normal_region := REGION_BUTTON_CYAN if cyan else REGION_BUTTON_PURPLE
	var hover_region := REGION_BUTTON_CYAN_ALT if cyan else REGION_BUTTON_PURPLE_ALT
	button.add_theme_stylebox_override("normal", _atlas_style(normal_region, 11.0, 9.0))
	button.add_theme_stylebox_override("hover", _atlas_style(hover_region, 11.0, 9.0))
	button.add_theme_stylebox_override("pressed", _atlas_style(hover_region, 11.0, 9.0))
	button.add_theme_stylebox_override("focus", _atlas_style(hover_region, 11.0, 9.0))
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_color_override("font_hover_color", WHITE)
	button.add_theme_color_override("font_pressed_color", WHITE)

func _build_ui() -> void:
	var bg_color := ColorRect.new()
	bg_color.color = BG
	bg_color.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_color)

	var bg := TextureRect.new()
	bg.texture = CHAT_BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.modulate = Color(1, 1, 1, 0.82)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var sidebar_bg := ColorRect.new()
	sidebar_bg.color = SIDEBAR
	sidebar_bg.custom_minimum_size.x = 306
	root.add_child(sidebar_bg)

	var sidebar := VBoxContainer.new()
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sidebar.offset_left = 18
	sidebar.offset_right = -18
	sidebar.offset_top = 18
	sidebar.offset_bottom = -18
	sidebar.add_theme_constant_override("separation", 10)
	sidebar_bg.add_child(sidebar)

	var brand := Label.new()
	brand.text = "◈  AuroraFox"
	brand.add_theme_font_size_override("font_size", 27)
	brand.add_theme_color_override("font_color", ACCENT)
	sidebar.add_child(brand)

	var subtitle := Label.new()
	subtitle.text = "Ваш AI-ассистент"
	subtitle.add_theme_color_override("font_color", MUTED)
	sidebar.add_child(subtitle)

	var new_chat := Button.new()
	new_chat.text = "+  Новый чат"
	new_chat.custom_minimum_size.y = 48
	new_chat.pressed.connect(_new_chat)
	_apply_neon_button(new_chat, false)
	sidebar.add_child(new_chat)

	var search := LineEdit.new()
	search.placeholder_text = "Поиск по чатам"
	search.custom_minimum_size.y = 42
	search.text_changed.connect(func(q): _refresh_chat_list(q))
	search.add_theme_stylebox_override("normal", _atlas_style(REGION_PANEL_PURPLE, 18.0, 12.0))
	search.add_theme_stylebox_override("focus", _atlas_style(REGION_PANEL_CYAN, 18.0, 12.0))
	search.add_theme_color_override("font_color", WHITE)
	search.add_theme_color_override("font_placeholder_color", MUTED)
	sidebar.add_child(search)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(scroll)
	chat_list = VBoxContainer.new()
	chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_list.add_theme_constant_override("separation", 6)
	scroll.add_child(chat_list)

	var tools_button := Button.new()
	tools_button.text = "⚙  Инструменты и настройки"
	tools_button.custom_minimum_size.y = 44
	tools_button.pressed.connect(_show_tools_info)
	_apply_neon_button(tools_button, true)
	sidebar.add_child(tools_button)

	var main_panel := VBoxContainer.new()
	main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_panel.add_theme_constant_override("separation", 0)
	root.add_child(main_panel)

	var top := HBoxContainer.new()
	top.custom_minimum_size.y = 66
	top.add_theme_constant_override("separation", 12)
	main_panel.add_child(top)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 28
	top.add_child(spacer)
	var title := Label.new()
	title.text = "AuroraFox"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	status = Label.new()
	status.text = "Инициализация..."
	status.add_theme_color_override("font_color", MUTED)
	top.add_child(status)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.x = 24
	top.add_child(spacer2)

	var chat_margin := MarginContainer.new()
	chat_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_margin.add_theme_constant_override("margin_left", 54)
	chat_margin.add_theme_constant_override("margin_right", 54)
	chat_margin.add_theme_constant_override("margin_top", 20)
	chat_margin.add_theme_constant_override("margin_bottom", 8)
	main_panel.add_child(chat_margin)
	output = RichTextLabel.new()
	output.bbcode_enabled = true
	output.scroll_following = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.add_theme_font_size_override("normal_font_size", 17)
	output.add_theme_color_override("default_color", WHITE)
	output.add_theme_stylebox_override("normal", _atlas_style(REGION_PANEL_CYAN, 20.0, 16.0))
	chat_margin.add_child(output)

	var composer_margin := MarginContainer.new()
	composer_margin.add_theme_constant_override("margin_left", 52)
	composer_margin.add_theme_constant_override("margin_right", 52)
	composer_margin.add_theme_constant_override("margin_top", 6)
	composer_margin.add_theme_constant_override("margin_bottom", 24)
	main_panel.add_child(composer_margin)
	var composer := VBoxContainer.new()
	composer.add_theme_constant_override("separation", 7)
	composer_margin.add_child(composer)

	attachment_bar = HBoxContainer.new()
	attachment_bar.add_theme_constant_override("separation", 6)
	composer.add_child(attachment_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	composer.add_child(row)
	var attach := Button.new()
	attach.text = "＋"
	attach.tooltip_text = "Прикрепить файлы"
	attach.custom_minimum_size = Vector2(54, 54)
	attach.pressed.connect(_open_file_dialog)
	_apply_neon_button(attach, false)
	row.add_child(attach)

	input = TextEdit.new()
	input.placeholder_text = "Напишите сообщение AuroraFox…"
	input.custom_minimum_size.y = 84
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.gui_input.connect(_on_input_gui)
	input.add_theme_stylebox_override("normal", _atlas_style(REGION_PANEL_PURPLE, 22.0, 16.0))
	input.add_theme_stylebox_override("focus", _atlas_style(REGION_PANEL_CYAN, 22.0, 16.0))
	input.add_theme_color_override("font_color", WHITE)
	input.add_theme_color_override("font_placeholder_color", MUTED)
	row.add_child(input)

	var send := Button.new()
	send.text = "➤"
	send.tooltip_text = "Отправить"
	send.custom_minimum_size = Vector2(64, 54)
	send.pressed.connect(_submit_current)
	_apply_neon_button(send, true)
	row.add_child(send)

	var hint := Label.new()
	hint.text = "Enter — отправить  •  Shift+Enter — новая строка  •  прикрепляйте файлы кнопкой +"
	hint.add_theme_color_override("font_color", MUTED)
	composer.add_child(hint)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.files_selected.connect(_on_files_selected)
	add_child(file_dialog)

func _new_chat() -> void:
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
		var b := Button.new()
		b.text = str(chat.get("title", "Новый чат"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 40
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_neon_button(b, false)
		var id := str(chat.get("id", ""))
		b.pressed.connect(func():
			chats.active_chat_id = id
			chats.save_all()
			_render_active_chat()
		)
		row.add_child(b)
		var del := Button.new()
		del.text = "×"
		del.tooltip_text = "Удалить чат"
		del.custom_minimum_size = Vector2(42, 40)
		_apply_neon_button(del, true)
		del.pressed.connect(func():
			chats.delete_chat(id)
			_refresh_chat_list(query)
			_render_active_chat()
		)
		row.add_child(del)
		chat_list.add_child(row)

func _render_active_chat() -> void:
	if output == null:
		return
	output.clear()
	var chat := chats.get_active_chat()
	var messages: Array = chat.get("messages", [])
	if messages.is_empty():
		output.append_text("[center][font_size=30][color=#a66cff]Привет! Я AuroraFox[/color][/font_size]\n")
		output.append_text("[color=#8993aa]Ваш AI-ассистент. Готов помочь с файлами, кодом, поиском информации и задачами.[/color][/center]\n")
		return
	for message in messages:
		var role := str(message.get("role", "assistant"))
		var content := str(message.get("content", ""))
		if role == "user":
			output.append_text("\n[color=#32c9ff][b]Вы[/b][/color]\n%s\n" % content)
		else:
			output.append_text("\n[color=#a66cff][b]AuroraFox[/b][/color]\n%s\n" % content)

func _open_file_dialog() -> void:
	file_dialog.popup_centered_ratio(0.72)

func _on_files_selected(paths: PackedStringArray) -> void:
	for path in paths:
		var item := attachments.describe(path)
		if item.get("ok", false):
			pending_attachments.append(item)
	_refresh_attachment_bar()

func _refresh_attachment_bar() -> void:
	for child in attachment_bar.get_children():
		child.queue_free()
	for item in pending_attachments:
		var chip := Button.new()
		chip.text = "📎 %s" % item.get("name", "file")
		chip.tooltip_text = "%s • %s" % [item.get("kind", ""), item.get("size", 0)]
		_apply_neon_button(chip, false)
		var target = item
		chip.pressed.connect(func():
			pending_attachments.erase(target)
			_refresh_attachment_bar()
		)
		attachment_bar.add_child(chip)

func _on_input_gui(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER and not event.shift_pressed:
		get_viewport().set_input_as_handled()
		_submit_current()

func _submit_current() -> void:
	var text := input.text.strip_edges()
	if text.is_empty() and pending_attachments.is_empty():
		return
	input.clear()
	var shown := text
	if shown.is_empty():
		shown = "Проанализируй прикреплённые файлы."
	var attachment_copy := pending_attachments.duplicate(true)
	chats.add_message("user", shown, attachment_copy)
	pending_attachments.clear()
	_refresh_attachment_bar()
	_refresh_chat_list()
	_render_active_chat()
	status.text = "AuroraFox думает…"
	var task := shown + attachments.build_context(attachment_copy)
	var answer := await agent.run_task(task)
	chats.add_message("assistant", answer)
	_render_active_chat()
	_refresh_chat_list()
	status.text = "● готово   •   %d инструментов   •   память %d" % [tools.tools.size(), memory.memory.size()]

func _show_tools_info() -> void:
	output.append_text("\n[color=#a66cff][b]Инструменты AuroraFox[/b][/color]\nИнтернет, HTTP, файлы, Git, системная информация, память, база знаний и безопасное создание модулей улучшения.\n")
