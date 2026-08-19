class_name AuroraDesktopVisualTheme
extends Node

const FINAL_BACKGROUND: Texture2D = preload("res://assets/ui/aurora_background_final.svg")
# Temporary safe fallback until the final per-element AuroraFox PNG archive is imported.
# Do not use the previously corrupted aurora_fox_user.jpg / aurora_button_user.jpg assets.
const FOX_IMAGE: Texture2D = preload("res://assets/ui/fox_logo.svg")

const MIN_WINDOW := Vector2i(960, 640)
const SIDEBAR_WIDE := 286.0
const SIDEBAR_COMPACT := 228.0

var _root: Control
var _last_width := -1.0

func _ready() -> void:
	if OS.get_name() == "Android":
		return
	_root = get_parent() as Control
	if _root == null:
		return
	get_window().min_size = MIN_WINDOW
	get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_after_build")

func _apply_after_build() -> void:
	for _i in range(3):
		await get_tree().process_frame
	_replace_visual_assets(_root)
	_apply_safe_button_styles(_root)
	_replace_header_avatar()
	_apply_responsive_layout()

func _replace_visual_assets(node: Node) -> void:
	for child in node.get_children():
		if child is TextureRect:
			var rect := child as TextureRect
			if rect.texture != null:
				var path := rect.texture.resource_path
				if path.ends_with("aurora_background.svg") or path.ends_with("aurora_background_user.jpg"):
					rect.texture = FINAL_BACKGROUND
					rect.modulate = Color(1, 1, 1, 0.96)
				elif path.ends_with("aurora_fox_user.jpg"):
					rect.texture = FOX_IMAGE
					rect.modulate = Color.WHITE
		_replace_visual_assets(child)

func _flat_state(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 11
	style.corner_radius_top_right = 11
	style.corner_radius_bottom_left = 11
	style.corner_radius_bottom_right = 11
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _apply_safe_button_styles(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			var button := child as Button
			button.add_theme_stylebox_override("normal", _flat_state(Color(0.065, 0.07, 0.115, 0.98), Color(0.28, 0.47, 0.70, 0.70)))
			button.add_theme_stylebox_override("hover", _flat_state(Color(0.12, 0.08, 0.22, 0.99), Color(0.38, 0.83, 1.0, 0.86)))
			button.add_theme_stylebox_override("pressed", _flat_state(Color(0.16, 0.08, 0.28, 1.0), Color(0.67, 0.54, 1.0, 0.94)))
			button.add_theme_stylebox_override("focus", _flat_state(Color(0.10, 0.08, 0.18, 0.99), Color(0.40, 0.83, 1.0, 0.90)))
			button.add_theme_stylebox_override("disabled", _flat_state(Color(0.04, 0.045, 0.07, 0.86), Color(0.20, 0.23, 0.31, 0.55)))
			button.add_theme_color_override("font_color", Color("f4f6ff"))
			button.add_theme_color_override("font_hover_color", Color.WHITE)
			button.clip_text = true
		_apply_safe_button_styles(child)

func _replace_header_avatar() -> void:
	var slot := _root.find_child("AvatarSlot", true, false) as Control
	if slot == null:
		return
	for child in slot.get_children():
		child.visible = false
	if slot.find_child("AuroraFoxSafeAvatar", false, false) != null:
		return
	var fox := TextureRect.new()
	fox.name = "AuroraFoxSafeAvatar"
	fox.texture = FOX_IMAGE
	fox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fox.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fox.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(fox)

func _apply_responsive_layout() -> void:
	if _root == null:
		return
	var width := get_viewport().get_visible_rect().size.x
	if is_equal_approx(width, _last_width):
		return
	_last_width = width
	var compact := width < 1180.0

	var sidebar := _root.find_child("Sidebar", true, false) as Control
	if sidebar != null:
		sidebar.custom_minimum_size.x = SIDEBAR_COMPACT if compact else SIDEBAR_WIDE

	var avatar_slot := _root.find_child("AvatarSlot", true, false) as Control
	if avatar_slot != null:
		avatar_slot.custom_minimum_size = Vector2(46, 42) if compact else Vector2(58, 48)

	var header_actions := _root.find_child("MainHeaderActions", true, false) as HBoxContainer
	if header_actions != null:
		header_actions.add_theme_constant_override("separation", 5 if compact else 8)
		for child in header_actions.get_children():
			if child is Button:
				var button := child as Button
				var max_width := 104.0 if compact else 132.0
				if button.custom_minimum_size.x > max_width:
					button.custom_minimum_size.x = max_width

	var voice_status := _root.find_child("VoiceStatus", true, false) as Label
	if voice_status != null:
		voice_status.visible = not compact

	var main_panel := _root.find_child("MainPanel", true, false) as Control
	if main_panel != null:
		main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var composer := _root.find_child("ComposerMargin", true, false) as MarginContainer
	if composer != null:
		composer.add_theme_constant_override("margin_left", 12 if compact else 24)
		composer.add_theme_constant_override("margin_right", 12 if compact else 24)
		composer.add_theme_constant_override("margin_bottom", 10 if compact else 20)

	var message_scroll := _root.find_child("MessageScroll", true, false) as ScrollContainer
	if message_scroll != null:
		message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
