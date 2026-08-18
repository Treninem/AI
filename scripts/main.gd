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

const BG := Color("0b1014")
const SIDEBAR := Color("101820")
const PANEL := Color("121d25")
const ACCENT := Color("36e68a")
const CYAN := Color("39d7ff")
const MUTED := Color("91a2ad")

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

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var sidebar_bg := ColorRect.new()
	sidebar_bg.color = SIDEBAR
	sidebar_bg.custom_minimum_size.x = 286
	root.add_child(sidebar_bg)

	var sidebar := VBoxContainer.new()
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sidebar.offset_left = 16
	sidebar.offset_right = -16
	sidebar.offset_top = 18
	sidebar.offset_bottom = -18
	sidebar.add_theme_constant_override("separation", 10)
	sidebar_bg.add_child(sidebar)

	var brand := Label.new()
	brand.text = "◈  AuroraFox"
	brand.add_theme_font_size_override("font_size", 25)
	brand.add_theme_color_override("font_color", ACCENT)
	sidebar.add_child(brand)

	var subtitle := Label.new()
	subtitle.text = "Локальный автономный AI"
	subtitle.add_theme_color_override("font_color", MUTED)
	sidebar.add_child(subtitle)

	var new_chat := Button.new()
	new_chat.text = "+  Новый чат"
	new_chat.custom_minimum_size.y = 42
	new_chat.pressed.connect(_new_chat)
	sidebar.add_child(new_chat)

	var search := LineEdit.new()
	search.placeholder_text = "Поиск по чатам"
	search.text_changed.connect(func(q): _refresh_chat_list(q))
	sidebar.add_child(search)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(scroll)
	chat_list = VBoxContainer.new()
	chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_list.add_theme_constant_override("separation", 5)
	scroll.add_child(chat_list)

	var tools_button := Button.new()
	tools_button.text = "⚙  Инструменты и настройки"
	tools_button.pressed.connect(_show_tools_info)
	sidebar.add_child(tools_button)

	var main_panel := VBoxContainer.new()
	main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_panel.add_theme_constant_override("separation", 0)
	root.add_child(main_panel)

	var top := HBoxContainer.new()
	top.custom_minimum_size.y = 62
	top.add_theme_constant_override("separation", 12)
	main_panel.add_child(top)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 22
	top.add_child(spacer)
	var title := Label.new()
	title.text = "AuroraFox"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	status = Label.new()
	status.text = "Инициализация..."
	status.add_theme_color_override("font_color", MUTED)
	top.add_child(status)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.x = 20
	top.add_child(spacer2)

	var chat_margin := MarginContainer.new()
	chat_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_margin.add_theme_constant_override("margin_left", 48)
	chat_margin.add_theme_constant_override("margin_right", 48)
	chat_margin.add_theme_constant_override("margin_top", 18)
	chat_margin.add_theme_constant_override("margin_bottom", 8)
	main_panel.add_child(chat_margin)
	output = RichTextLabel.new()
	output.bbcode_enabled = true
	output.scroll_following = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.add_theme_font_size_override("normal_font_size", 17)
	chat_margin.add_child(output)

	var composer_margin := MarginContainer.new()
	composer_margin.add_theme_constant_override("margin_left", 46)
	composer_margin.add_theme_constant_override("margin_right", 46)
	composer_margin.add_theme_constant_override("margin_top", 4)
	composer_margin.add_theme_constant_override("margin_bottom", 28)
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
	attach.custom_minimum_size = Vector2(48, 48)
	attach.pressed.connect(_open_file_dialog)
	row.add_child(attach)

	input = TextEdit.new()
	input.placeholder_text = "Сообщение для AuroraFox…"
	input.custom_minimum_size.y = 74
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.gui_input.connect(_on_input_gui)
	row.add_child(input)

	var send := Button.new()
	send.text = "➤"
	send.tooltip_text = "Отправить"
	send.custom_minimum_size = Vector2(58, 48)
	send.pressed.connect(_submit_current)
	row.add_child(send)

	var hint := Label.new()
	hint.text = "Enter — отправить • Shift+Enter — новая строка • файлы можно прикреплять"
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
	if chat_list == null: return
	for child in chat_list.get_children(): child.queue_free()
	var source: Array = chats.search(query)
	for chat in source:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := Button.new()
		b.text = str(chat.get("title", "Новый чат"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		del.pressed.connect(func():
			chats.delete_chat(id)
			_refresh_chat_list(query)
			_render_active_chat()
		)
		row.add_child(del)
		chat_list.add_child(row)

func _render_active_chat() -> void:
	if output == null: return
	output.clear()
	var chat := chats.get_active_chat()
	var messages: Array = chat.get("messages", [])
	if messages.is_empty():
		output.append_text("[center][font_size=28][color=#36e68a]AuroraFox[/color][/font_size]\n")
		output.append_text("[color=#91a2ad]Чем я могу помочь? Можно задать вопрос, дать задачу, прикрепить файл или попросить найти информацию.[/color][/center]\n")
		return
	for message in messages:
		var role := str(message.get("role", "assistant"))
		var content := str(message.get("content", ""))
		if role == "user":
			output.append_text("\n[color=#39d7ff][b]Вы[/b][/color]\n%s\n" % content)
		else:
			output.append_text("\n[color=#36e68a][b]AuroraFox[/b][/color]\n%s\n" % content)

func _open_file_dialog() -> void:
	file_dialog.popup_centered_ratio(0.72)

func _on_files_selected(paths: PackedStringArray) -> void:
	for path in paths:
		var item := attachments.describe(path)
		if item.get("ok", false): pending_attachments.append(item)
	_refresh_attachment_bar()

func _refresh_attachment_bar() -> void:
	for child in attachment_bar.get_children(): child.queue_free()
	for item in pending_attachments:
		var chip := Button.new()
		chip.text = "📎 %s" % item.get("name", "file")
		chip.tooltip_text = "%s • %s" % [item.get("kind", ""), item.get("size", 0)]
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
	if text.is_empty() and pending_attachments.is_empty(): return
	input.clear()
	var shown := text
	if shown.is_empty(): shown = "Проанализируй прикреплённые файлы."
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
	output.append_text("\n[color=#36e68a][b]Инструменты AuroraFox[/b][/color]\nИнтернет, HTTP, файлы, Git, системная информация, память, база знаний и безопасное создание модулей улучшения.\n")
