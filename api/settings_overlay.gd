class_name AuroraApiSettingsOverlay
extends Node

var manager: AuroraApiGatewayManager
var popup: PopupPanel
var status_label: Label
var url_label: Label
var enabled_toggle: CheckButton
var port_box: SpinBox
var key_name: LineEdit
var token_output: LineEdit
var keys_box: VBoxContainer

const BG := Color(0.025, 0.03, 0.05, 0.995)
const SURFACE := Color(0.055, 0.065, 0.10, 0.98)
const BORDER := Color(0.34, 0.39, 0.55, 0.55)
const ACCENT := Color("a98aff")
const GREEN := Color("64ff9d")
const WHITE := Color("f3f6ff")
const MUTED := Color("8d98ad")

func _ready() -> void:
	if OS.get_name() == "Android":
		return
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	await get_tree().process_frame
	manager = get_parent().get_node_or_null("ApiGatewayManager") as AuroraApiGatewayManager
	if manager == null:
		return
	_build_popup()
	_inject_settings_button()
	manager.status_changed.connect(_on_status_changed)
	manager.key_created.connect(_on_key_created)
	_refresh()

func _style(fill: Color, border: Color = BORDER, radius := 14) -> StyleBoxFlat:
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

func _button(text: String, accent := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	var border := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.82) if accent else BORDER
	button.add_theme_stylebox_override("normal", _style(SURFACE, border, 11))
	button.add_theme_stylebox_override("hover", _style(Color(0.10, 0.11, 0.17, 1.0), border, 11))
	button.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.10, 0.22, 1.0), border, 11))
	button.add_theme_color_override("font_color", WHITE)
	return button

func _build_popup() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 112
	add_child(layer)
	popup = PopupPanel.new()
	popup.size = Vector2i(720, 680)
	popup.add_theme_stylebox_override("panel", _style(BG, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.62), 18))
	layer.add_child(popup)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	popup.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "API и интеграции"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", WHITE)
	root.add_child(title)

	var description := Label.new()
	description.text = "Подключай Telegram/VK-ботов, сайты и приложения к тому же AgentCore, памяти и инструментам AuroraFox. API-диалоги и feedback участвуют в обучении."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("cbd4e8"))
	root.add_child(description)

	enabled_toggle = CheckButton.new()
	enabled_toggle.text = "Запускать локальный API вместе с AuroraFox"
	enabled_toggle.button_pressed = manager.enabled
	enabled_toggle.toggled.connect(_on_enabled_toggled)
	root.add_child(enabled_toggle)

	var endpoint_row := HBoxContainer.new()
	endpoint_row.add_theme_constant_override("separation", 8)
	root.add_child(endpoint_row)
	var endpoint_title := Label.new()
	endpoint_title.text = "Адрес"
	endpoint_title.custom_minimum_size.x = 80
	endpoint_row.add_child(endpoint_title)
	url_label = Label.new()
	url_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_label.add_theme_color_override("font_color", GREEN)
	endpoint_row.add_child(url_label)
	port_box = SpinBox.new()
	port_box.min_value = 1024
	port_box.max_value = 65535
	port_box.step = 1
	port_box.value = manager.port
	port_box.custom_minimum_size.x = 120
	port_box.value_changed.connect(_on_port_changed)
	endpoint_row.add_child(port_box)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	var note := Label.new()
	note.text = "По умолчанию API слушает только 127.0.0.1. Для сайта/бота на другом сервере позже можно включить защищённый relay, не открывая порт ПК напрямую."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", MUTED)
	root.add_child(note)
	root.add_child(HSeparator.new())

	var key_title := Label.new()
	key_title.text = "API-ключи"
	key_title.add_theme_font_size_override("font_size", 19)
	root.add_child(key_title)

	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 8)
	root.add_child(create_row)
	key_name = LineEdit.new()
	key_name.placeholder_text = "Например: Telegram VoxLyra"
	key_name.text = "Моя интеграция"
	key_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(key_name)
	var create := _button("Создать ключ", true)
	create.pressed.connect(_create_key)
	create_row.add_child(create)

	var token_row := HBoxContainer.new()
	token_row.add_theme_constant_override("separation", 8)
	root.add_child(token_row)
	token_output = LineEdit.new()
	token_output.placeholder_text = "Новый ключ появится здесь один раз"
	token_output.editable = false
	token_output.secret = true
	token_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	token_row.add_child(token_output)
	var copy := _button("Копировать")
	copy.pressed.connect(_copy_token)
	token_row.add_child(copy)

	var scope_hint := Label.new()
	scope_hint.text = "Новый ключ получает: chat, models.read, conversations.read, files, tools.read, feedback, memory.read, memory.write. Запуск системных tools через API по умолчанию не выдаётся."
	scope_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scope_hint.add_theme_font_size_override("font_size", 12)
	scope_hint.add_theme_color_override("font_color", MUTED)
	root.add_child(scope_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	keys_box = VBoxContainer.new()
	keys_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys_box.add_theme_constant_override("separation", 6)
	scroll.add_child(keys_box)

	var close := _button("Закрыть")
	close.pressed.connect(_close_popup)
	root.add_child(close)

func _inject_settings_button() -> void:
	var settings := get_parent().get_node_or_null("SettingsOverlay")
	if settings == null:
		return
	var settings_popup = settings.get("popup")
	if not settings_popup is PopupPanel:
		return
	var box := _find_main_vbox(settings_popup)
	if box == null:
		return
	var separator := HSeparator.new()
	var label := Label.new()
	label.text = "API и интеграции"
	label.add_theme_font_size_override("font_size", 20)
	var button := _button("Открыть API и интеграции", true)
	button.pressed.connect(show_api_settings)
	box.add_child(separator)
	box.add_child(label)
	box.add_child(button)
	var close_index := -1
	for i in range(box.get_child_count()):
		var child := box.get_child(i)
		if child is Button and str(child.text) == "Закрыть":
			close_index = i
			break
	if close_index >= 0:
		box.move_child(separator, close_index)
		box.move_child(label, close_index + 1)
		box.move_child(button, close_index + 2)

func _find_main_vbox(node: Node) -> VBoxContainer:
	for child in node.get_children():
		if child is VBoxContainer and child.get_child_count() >= 5:
			return child
		var found: VBoxContainer = _find_main_vbox(child)
		if found != null:
			return found
	return null

func show_api_settings() -> void:
	_refresh()
	popup.popup_centered()

func _refresh() -> void:
	if manager == null or popup == null:
		return
	enabled_toggle.button_pressed = manager.enabled
	port_box.value = manager.port
	url_label.text = manager.base_url()
	_on_status_changed(manager.online, manager.last_status)
	_refresh_keys()

func _on_status_changed(is_online: bool, details: Dictionary) -> void:
	if status_label == null:
		return
	if is_online:
		var core_state := "подключён" if bool(details.get("agent_online", false)) else "ожидает AuroraFox"
		status_label.text = "API: работает • AgentCore " + core_state
		status_label.add_theme_color_override("font_color", GREEN)
	else:
		status_label.text = "API: запускается / не отвечает"
		status_label.add_theme_color_override("font_color", Color("ffb36d"))

func _on_enabled_toggled(value: bool) -> void:
	manager.set_enabled(value)

func _on_port_changed(value: float) -> void:
	manager.set_port(int(value))
	url_label.text = manager.base_url()

func _copy_token() -> void:
	if not token_output.text.is_empty():
		DisplayServer.clipboard_set(token_output.text)

func _close_popup() -> void:
	popup.hide()

func _create_key() -> void:
	var name := key_name.text.strip_edges()
	if name.is_empty():
		name = "AuroraFox integration"
	var result := manager.create_key(name)
	if not result.get("ok", false):
		status_label.text = "Не удалось создать ключ: " + str(result.get("error", "unknown"))
	_refresh_keys()

func _on_key_created(api_key: String, _info: Dictionary) -> void:
	token_output.text = api_key
	token_output.secret = false
	DisplayServer.clipboard_set(api_key)
	status_label.text = "Ключ создан и скопирован. Сохрани его: повторно полный ключ не показывается."

func _revoke_key(key_id: String) -> void:
	manager.revoke_key(key_id)
	_refresh_keys()

func _refresh_keys() -> void:
	if keys_box == null or manager == null:
		return
	for child in keys_box.get_children():
		child.queue_free()
	var result := manager.list_keys()
	if not result.get("ok", false):
		var label := Label.new()
		label.text = "Ключи станут доступны после подготовки API runtime."
		label.add_theme_color_override("font_color", MUTED)
		keys_box.add_child(label)
		return
	var data: Dictionary = result.get("data", {})
	var rows: Array = data.get("keys", [])
	for item in rows:
		if not item is Dictionary:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		keys_box.add_child(row)
		var label := Label.new()
		label.text = "%s  •  %s" % [str(item.get("name", "Ключ")), ", ".join(PackedStringArray(item.get("scopes", [])))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		if not bool(item.get("revoked", false)):
			var revoke := _button("Отозвать")
			var key_id := str(item.get("id", ""))
			revoke.pressed.connect(_revoke_key.bind(key_id))
			row.add_child(revoke)
