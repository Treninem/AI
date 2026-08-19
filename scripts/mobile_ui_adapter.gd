class_name MobileUIAdapter
extends Node

const PORTRAIT_BASE := Vector2i(720, 1280)
const LANDSCAPE_BASE := Vector2i(1280, 720)
const KEYBOARD_POLL_SECONDS := 0.12

var sidebar: Control
var main_panel: Control
var root_row: HBoxContainer
var menu_button: Button
var composer_margin: MarginContainer
var sidebar_open := false
var _base_composer_bottom := 24
var _poll_left := 0.0
var _last_keyboard_height := -1
var _last_safe_area := Rect2i()
var _last_screen_size := Vector2i()
var _last_chat_id := ""

func _ready() -> void:
	if OS.get_name() != "Android": return
	_configure_mobile_scale()
	await get_tree().process_frame
	_find_layout()
	_apply_mobile_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	set_process(true)

func _process(delta: float) -> void:
	if OS.get_name() != "Android": return
	_poll_left -= delta
	if _poll_left > 0.0: return
	_poll_left = KEYBOARD_POLL_SECONDS
	var keyboard_height := DisplayServer.virtual_keyboard_get_height()
	var safe_area := DisplayServer.get_display_safe_area()
	var screen_size := DisplayServer.screen_get_size()
	if keyboard_height != _last_keyboard_height or safe_area != _last_safe_area or screen_size != _last_screen_size:
		_apply_mobile_layout()
	_close_sidebar_after_chat_change()

func _configure_mobile_scale() -> void:
	var screen := DisplayServer.screen_get_size()
	var base := PORTRAIT_BASE if screen.y >= screen.x else LANDSCAPE_BASE
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = base

func _find_layout() -> void:
	var parent := get_parent()
	if parent == null: return
	for child in parent.get_children():
		if child is HBoxContainer and child.get_child_count() >= 2:
			root_row = child
			break
	if root_row == null: return
	for child in root_row.get_children():
		if sidebar == null and child is ColorRect:
			sidebar = child
		elif main_panel == null and child is Control:
			main_panel = child
	composer_margin = _find_composer_margin(parent)
	if composer_margin != null:
		_base_composer_bottom = maxi(12, composer_margin.get_theme_constant("margin_bottom"))
	var main = get_parent()
	if main != null:
		var store = main.get("chats")
		if store is ChatStore: _last_chat_id = store.active_chat_id

func _find_composer_margin(node: Node) -> MarginContainer:
	if node is TextEdit:
		var cursor := node.get_parent()
		while cursor != null and cursor != get_parent():
			if cursor is MarginContainer: return cursor
			cursor = cursor.get_parent()
	for child in node.get_children():
		var found := _find_composer_margin(child)
		if found != null: return found
	return null

func _on_viewport_size_changed() -> void:
	_configure_mobile_scale()
	call_deferred("_apply_mobile_layout")

func _apply_mobile_layout() -> void:
	if OS.get_name() != "Android" or root_row == null: return
	_last_keyboard_height = DisplayServer.virtual_keyboard_get_height()
	_last_safe_area = DisplayServer.get_display_safe_area()
	_last_screen_size = DisplayServer.screen_get_size()
	var insets := _safe_insets_logical()

	root_row.offset_left = insets.x
	root_row.offset_top = insets.y
	root_row.offset_right = -insets.z
	root_row.offset_bottom = -insets.w

	if sidebar != null:
		sidebar.custom_minimum_size.x = 0.0
		sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sidebar.visible = sidebar_open
	if main_panel != null:
		main_panel.visible = not sidebar_open
		main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_make_touch_friendly(get_parent())
	_adjust_margins(get_parent())
	_ensure_menu_button()
	_position_menu_button(insets)
	_apply_keyboard_inset()

func _safe_insets_logical() -> Vector4:
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.x <= 0 or screen.y <= 0: return Vector4.ZERO
	if safe.size.x <= 0 or safe.size.y <= 0:
		safe = Rect2i(Vector2i.ZERO, screen)
	var scale := _physical_to_logical_scale()
	if scale <= 0.0: scale = 1.0
	var left := maxf(0.0, float(safe.position.x) / scale)
	var top := maxf(0.0, float(safe.position.y) / scale)
	var right := maxf(0.0, float(screen.x - safe.end.x) / scale)
	var bottom := maxf(0.0, float(screen.y - safe.end.y) / scale)
	return Vector4(left, top, right, bottom)

func _physical_to_logical_scale() -> float:
	var window_px := DisplayServer.window_get_size()
	var base := get_window().content_scale_size
	if window_px.x <= 0 or window_px.y <= 0 or base.x <= 0 or base.y <= 0: return 1.0
	# EXPAND preserves aspect and exposes extra logical space on the longer axis.
	return maxf(0.001, minf(float(window_px.x) / float(base.x), float(window_px.y) / float(base.y)))

func _apply_keyboard_inset() -> void:
	if composer_margin == null: return
	var keyboard_px := DisplayServer.virtual_keyboard_get_height()
	var extra := 0
	if keyboard_px > 0:
		var screen_px := DisplayServer.screen_get_size()
		var window_px := DisplayServer.window_get_size()
		# Some Android window modes already shrink the app when the IME opens.
		# Only add our own inset if the app window still occupies nearly the full display.
		var already_resized := screen_px.y > 0 and window_px.y <= screen_px.y - int(float(keyboard_px) * 0.55)
		if not already_resized:
			extra = int(ceil(float(keyboard_px) / _physical_to_logical_scale()))
	composer_margin.add_theme_constant_override("margin_bottom", _base_composer_bottom + extra)

func _ensure_menu_button() -> void:
	if menu_button != null: return
	menu_button = Button.new()
	menu_button.name = "MobileMenuButton"
	menu_button.text = "☰"
	menu_button.tooltip_text = "Чаты"
	menu_button.custom_minimum_size = Vector2(58, 58)
	menu_button.z_index = 100
	menu_button.pressed.connect(_toggle_sidebar)
	get_parent().add_child(menu_button)

func _position_menu_button(insets: Vector4) -> void:
	if menu_button == null: return
	menu_button.position = Vector2(insets.x + 10.0, insets.y + 8.0)
	menu_button.text = "←" if sidebar_open else "☰"
	menu_button.tooltip_text = "Вернуться в чат" if sidebar_open else "Чаты"

func _toggle_sidebar() -> void:
	set_sidebar_open(not sidebar_open)

func set_sidebar_open(value: bool) -> void:
	sidebar_open = value
	var main = get_parent()
	if main != null:
		var store = main.get("chats")
		if store is ChatStore: _last_chat_id = store.active_chat_id
	_apply_mobile_layout()

func close_sidebar() -> void:
	if sidebar_open: set_sidebar_open(false)

func _close_sidebar_after_chat_change() -> void:
	if not sidebar_open: return
	var main = get_parent()
	if main == null: return
	var store = main.get("chats")
	if not store is ChatStore: return
	if not _last_chat_id.is_empty() and store.active_chat_id != _last_chat_id:
		set_sidebar_open(false)
	_last_chat_id = store.active_chat_id

func _make_touch_friendly(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, 52.0)
			child.add_theme_font_size_override("font_size", 17)
		elif child is LineEdit:
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, 52.0)
			child.add_theme_font_size_override("font_size", 17)
		elif child is TextEdit:
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, 104.0)
			child.add_theme_font_size_override("font_size", 18)
		_make_touch_friendly(child)

func _adjust_margins(node: Node) -> void:
	for child in node.get_children():
		if child is MarginContainer:
			var left: int = child.get_theme_constant("margin_left")
			var right: int = child.get_theme_constant("margin_right")
			if left > 24: child.add_theme_constant_override("margin_left", 16)
			if right > 24: child.add_theme_constant_override("margin_right", 16)
		_adjust_margins(child)
