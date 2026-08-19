class_name AuroraDesktopVisualTheme
extends Node

const FINAL_BACKGROUND: Texture2D = preload("res://assets/ui/aurora_background_final.svg")
const FOX_IMAGE: Texture2D = preload("res://assets/ui/aurora_fox_user.jpg")
const BUTTON_TEXTURE: Texture2D = preload("res://assets/ui/aurora_button_user.jpg")

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
	_apply_button_textures(_root)
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
				elif path.ends_with("fox_logo.svg") or path.ends_with("aurora_fox_user.jpg"):
					rect.texture = FOX_IMAGE
					rect.modulate = Color.WHITE
		_replace_visual_assets(child)

func _texture_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = BUTTON_TEXTURE
	style.texture_margin_left = 18.0
	style.texture_margin_right = 18.0
	style.texture_margin_top = 14.0
	style.texture_margin_bottom = 14.0
	style.expand_margin_left = 1.0
	style.expand_margin_right = 1.0
	style.expand_margin_top = 1.0
	style.expand_margin_bottom = 1.0
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return style

func _flat_state(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(11)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _apply_button_textures(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			var button := child as Button
			button.add_theme_stylebox_override("normal", _texture_style())
			button.add_theme_stylebox_override("hover", _flat_state(Color(0.12, 0.08, 0.22, 0.97), Color(0.38, 0.83, 1.0, 0.78)))
			button.add_theme_stylebox_override("pressed", _flat_state(Color(0.16, 0.08, 0.28, 1.0), Color(0.67, 0.54, 1.0, 0.92)))
			button.add_theme_stylebox_override("focus", _flat_state(Color(0.10, 0.08, 0.18, 0.98), Color(0.40, 0.83, 1.0, 0.90)))
			button.add_theme_stylebox_override("disabled", _flat_state(Color(0.04, 0.045, 0.07, 0.78), Color(0.20, 0.23, 0.31, 0.55)))
			button.add_theme_color_override("font_color", Color("f4f6ff"))
			button.add_theme_color_override("font_hover_color", Color.WHITE)
			button.clip_text = true
		_apply_button_textures(child)

func _replace_header_avatar() -> void:
	var slot := _root.find_child("AvatarSlot", true, false) as Control
	if slot == null:
		return
	for child in slot.get_children():
		child.visible = false
	var fox := TextureRect.new()
	fox.name = "AuroraFoxRealAvatar"
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
				(child as Button).custom_minimum_size.x = minf((child as Button).custom_minimum_size.x, 104.0 if compact else 132.0)

	var voice_status := _root.find_child("VoiceStatus", true, false) as Label
	if voice_status != null:
		voice_status.visible = not compact

	var title := _root.find_child("MainPanel", true, false) as Control
	if title != null:
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var composer := _root.find_child("ComposerMargin", true, false) as MarginContainer
	if composer != null:
		composer.add_theme_constant_override("margin_left", 12 if compact else 24)
		composer.add_theme_constant_override("margin_right", 12 if compact else 24)
		composer.add_theme_constant_override("margin_bottom", 10 if compact else 20)

	var message_scroll := _root.find_child("MessageScroll", true, false) as ScrollContainer
	if message_scroll != null:
		message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
