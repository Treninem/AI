class_name MobileUIAdapter
extends Node

const PORTRAIT_BASE := Vector2i(720, 1280)
const LANDSCAPE_BASE := Vector2i(1280, 720)
const KEYBOARD_POLL_SECONDS := 0.12

var sidebar: Control
var main_panel: Control
var root_row: HBoxContainer
var main_nav_slot: HBoxContainer
var sidebar_nav_slot: HBoxContainer
var menu_button: Button
var back_button: Button
var composer_margin: MarginContainer
var sidebar_open := false
var _base_composer_bottom := 12
var _poll_left := 0.0
var _last_keyboard_height := -1
var _last_safe_area := Rect2i()
var _last_screen_size := Vector2i()
var _last_chat_id := ""

func _is_mobile_context() -> bool:
	return OS.get_name() == "Android" or bool(ProjectSettings.get_setting("aurorafox/testing/mobile_preview", false))

func _ready() -> void:
	if not _is_mobile_context():
		return
	_configure_mobile_scale()
	await get_tree().process_frame
	_find_layout()
	_apply_mobile_layout()
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	set_process(true)

func _process(delta: float) -> void:
	if not _is_mobile_context():
		return
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = KEYBOARD_POLL_SECONDS
	var keyboard_height := DisplayServer.virtual_keyboard_get_height() if OS.get_name() == "Android" else 0
	var safe_area := DisplayServer.get_display_safe_area()
	var screen_size := DisplayServer.screen_get_size()
	if keyboard_height != _last_keyboard_height or safe_area != _last_safe_area or screen_size != _last_screen_size:
		_apply_mobile_layout()
	_close_sidebar_after_chat_change()

func _configure_mobile_scale() -> void:
	var screen := DisplayServer.screen_get_size()
	if bool(ProjectSettings.get_setting("aurorafox/testing/mobile_preview", false)):
		var viewport := get_viewport().get_visible_rect().size
		screen = Vector2i(int(viewport.x), int(viewport.y))
	var base := PORTRAIT_BASE if screen.y >= screen.x else LANDSCAPE_BASE
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = base

func _find_layout() -> void:
	var parent := get_parent()
	if parent == null:
		return
	root_row = parent.find_child("RootLayout", true, false) as HBoxContainer
	sidebar = parent.find_child("Sidebar", true, false) as Control
	main_panel = parent.find_child("MainPanel", true, false) as Control
	main_nav_slot = parent.find_child("MobileNavSlot", true, false) as HBoxContainer
	sidebar_nav_slot = parent.find_child("SidebarMobileNavSlot", true, false) as HBoxContainer
	composer_margin = parent.find_child("ComposerMargin", true, false) as MarginContainer
	if composer_margin != null:
		_base_composer_bottom = maxi(10, composer_margin.get_theme_constant("margin_bottom"))
	var store = parent.get("chats")
	if store is ChatStore:
		_last_chat_id = store.active_chat_id
	_ensure_navigation_buttons()

func _on_viewport_size_changed() -> void:
	_configure_mobile_scale()
	call_deferred("_apply_mobile_layout")

func _apply_mobile_layout() -> void:
	if not _is_mobile_context() or root_row == null:
		return
	_last_keyboard_height = DisplayServer.virtual_keyboard_get_height() if OS.get_name() == "Android" else 0
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

	if main_nav_slot != null:
		main_nav_slot.visible = not sidebar_open
	if sidebar_nav_slot != null:
		sidebar_nav_slot.visible = sidebar_open
	if menu_button != null:
		menu_button.visible = not sidebar_open
	if back_button != null:
		back_button.visible = sidebar_open

	var parent := get_parent()
	_make_touch_friendly(parent)
	_adjust_mobile_surfaces(parent)
	_fit_popups(parent)
	_apply_keyboard_inset()

func _safe_insets_logical() -> Vector4:
	if bool(ProjectSettings.get_setting("aurorafox/testing/mobile_preview", false)) and OS.get_name() != "Android":
		return Vector4.ZERO
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.x <= 0 or screen.y <= 0:
		return Vector4.ZERO
	if safe.size.x <= 0 or safe.size.y <= 0:
		safe = Rect2i(Vector2i.ZERO, screen)
	var scale := _physical_to_logical_scale()
	if scale <= 0.0:
		scale = 1.0
	var left := maxf(0.0, float(safe.position.x) / scale)
	var top := maxf(0.0, float(safe.position.y) / scale)
	var right := maxf(0.0, float(screen.x - safe.end.x) / scale)
	var bottom := maxf(0.0, float(screen.y - safe.end.y) / scale)
	return Vector4(left, top, right, bottom)

func _physical_to_logical_scale() -> float:
	var window_px := DisplayServer.window_get_size()
	var base := get_window().content_scale_size
	if window_px.x <= 0 or window_px.y <= 0 or base.x <= 0 or base.y <= 0:
		return 1.0
	return maxf(0.001, minf(float(window_px.x) / float(base.x), float(window_px.y) / float(base.y)))

func _apply_keyboard_inset() -> void:
	if composer_margin == null:
		return
	var keyboard_px := DisplayServer.virtual_keyboard_get_height() if OS.get_name() == "Android" else 0
	var extra := 0
	if keyboard_px > 0:
		var screen_px := DisplayServer.screen_get_size()
		var window_px := DisplayServer.window_get_size()
		var already_resized := screen_px.y > 0 and window_px.y <= screen_px.y - int(float(keyboard_px) * 0.55)
		if not already_resized:
			extra = int(ceil(float(keyboard_px) / _physical_to_logical_scale()))
	composer_margin.add_theme_constant_override("margin_bottom", _base_composer_bottom + extra)

func _ensure_navigation_buttons() -> void:
	if main_nav_slot != null and menu_button == null:
		menu_button = Button.new()
		menu_button.name = "MobileMenuButton"
		menu_button.text = "Чаты"
		menu_button.tooltip_text = "Открыть список чатов"
		menu_button.custom_minimum_size = Vector2(70, 44)
		menu_button.pressed.connect(func(): set_sidebar_open(true))
		main_nav_slot.add_child(menu_button)
		_apply_main_button_style(menu_button)
	if sidebar_nav_slot != null and back_button == null:
		back_button = Button.new()
		back_button.name = "MobileBackButton"
		back_button.text = "Назад"
		back_button.tooltip_text = "Вернуться в текущий чат"
		back_button.custom_minimum_size = Vector2(74, 44)
		back_button.pressed.connect(func(): set_sidebar_open(false))
		sidebar_nav_slot.add_child(back_button)
		_apply_main_button_style(back_button)

func _apply_main_button_style(button: Button) -> void:
	var main := get_parent()
	if main != null and main.has_method("_apply_button"):
		main.call("_apply_button", button, false, false, true)

func set_sidebar_open(value: bool) -> void:
	sidebar_open = value
	var main := get_parent()
	if main != null:
		var store = main.get("chats")
		if store is ChatStore:
			_last_chat_id = store.active_chat_id
	_apply_mobile_layout()

func close_sidebar() -> void:
	if sidebar_open:
		set_sidebar_open(false)

func _close_sidebar_after_chat_change() -> void:
	if not sidebar_open:
		return
	var main := get_parent()
	if main == null:
		return
	var store = main.get("chats")
	if not store is ChatStore:
		return
	if not _last_chat_id.is_empty() and store.active_chat_id != _last_chat_id:
		set_sidebar_open(false)
	_last_chat_id = store.active_chat_id

func _make_touch_friendly(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		if child is Button:
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, 44.0)
			child.add_theme_font_size_override("font_size", 15)
		elif child is LineEdit:
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, 46.0)
			child.add_theme_font_size_override("font_size", 15)
		elif child is TextEdit:
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, 66.0)
			child.add_theme_font_size_override("font_size", 16)
		_make_touch_friendly(child)

func _adjust_mobile_surfaces(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		if child is MarginContainer:
			var margin := child as MarginContainer
			var left := margin.get_theme_constant("margin_left")
			var right := margin.get_theme_constant("margin_right")
			if left > 16:
				margin.add_theme_constant_override("margin_left", 12)
			if right > 16:
				margin.add_theme_constant_override("margin_right", 12)
		_adjust_mobile_surfaces(child)

	var hint := get_parent().find_child("ComposerHint", true, false) as Label
	if hint != null:
		hint.visible = false
	var voice_status := get_parent().find_child("VoiceStatus", true, false) as Label
	if voice_status != null:
		voice_status.visible = false
	for redundant in ["VoiceSpeakButton", "VoiceSettingsButton", "ComputerAgentButton"]:
		var control := get_parent().find_child(redundant, true, false) as Control
		if control != null:
			control.visible = false
	var avatar_slot := get_parent().find_child("AvatarSlot", true, false) as Control
	if avatar_slot != null:
		avatar_slot.visible = false
		avatar_slot.custom_minimum_size = Vector2.ZERO
	var header_actions := get_parent().find_child("MainHeaderActions", true, false) as HBoxContainer
	if header_actions != null:
		header_actions.visible = false
	var header_margin := get_parent().find_child("HeaderMargin", true, false) as MarginContainer
	if header_margin != null:
		header_margin.add_theme_constant_override("margin_left", 10)
		header_margin.add_theme_constant_override("margin_right", 10)
		header_margin.add_theme_constant_override("margin_top", 8)
		header_margin.add_theme_constant_override("margin_bottom", 8)
	var messages_margin := get_parent().find_child("MessagesMargin", true, false) as MarginContainer
	if messages_margin != null:
		messages_margin.add_theme_constant_override("margin_left", 10)
		messages_margin.add_theme_constant_override("margin_right", 10)
		messages_margin.add_theme_constant_override("margin_top", 10)
	var composer := get_parent().find_child("ComposerMargin", true, false) as MarginContainer
	if composer != null:
		composer.add_theme_constant_override("margin_left", 10)
		composer.add_theme_constant_override("margin_right", 10)
		composer.add_theme_constant_override("margin_top", 6)
	var input := get_parent().find_child("MessageInput", true, false) as TextEdit
	if input != null:
		input.custom_minimum_size.y = 66

func _fit_popups(node: Node) -> void:
	if node == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var max_width := maxi(320, int(viewport_size.x - 20.0))
	var max_height := maxi(420, int(viewport_size.y - 28.0))
	for child in node.get_children():
		if child is PopupPanel or child is AcceptDialog:
			var popup := child as Window
			var current := popup.size
			if current.x <= 0:
				current.x = max_width
			if current.y <= 0:
				current.y = max_height
			popup.size = Vector2i(mini(current.x, max_width), mini(current.y, max_height))
		_fit_popups(child)
