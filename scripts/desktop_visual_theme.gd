class_name AuroraDesktopVisualTheme
extends Node

const FINAL_BACKGROUND: Texture2D = preload("res://assets/ui/aurora_background_final.svg")
const FOX_IMAGE: Texture2D = preload("res://assets/ui/fox_logo.svg")

const MIN_WINDOW := Vector2i(960, 640)
const SIDEBAR_WIDE := 286.0
const SIDEBAR_COMPACT := 228.0

var _root: Control
var _last_size := Vector2.ZERO

func _ready() -> void:
	_root = get_parent() as Control
	if _root == null:
		return
	if OS.get_name() != "Android":
		get_window().min_size = MIN_WINDOW
	if not get_viewport().size_changed.is_connected(_apply_responsive_layout):
		get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_after_build")

func _apply_after_build() -> void:
	for _i in range(4):
		await get_tree().process_frame
	if OS.get_name() != "Android":
		_replace_background(_root)
		# Avatar intentionally stays on the repository fallback until the owner
		# supplies the final AuroraFox artwork. Do not redesign it here.
		_replace_header_avatar()
	_apply_safe_button_styles(_root)
	_apply_popup_styles(_root)
	_apply_responsive_layout()

func _replace_background(node: Node) -> void:
	for child in node.get_children():
		if child is TextureRect:
			var rect := child as TextureRect
			if rect.texture != null and rect.texture.resource_path.ends_with("aurora_background.svg"):
				rect.texture = FINAL_BACKGROUND
				rect.modulate = Color(1, 1, 1, 0.96)
		_replace_background(child)

func _flat_state(fill: Color, border: Color, radius := 11) -> StyleBoxFlat:
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

func _popup_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.022, 0.026, 0.045, 0.995)
	style.border_color = Color(0.34, 0.56, 0.88, 0.82)
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.72)
	style.shadow_size = 18
	return style

func _apply_popup_styles(node: Node) -> void:
	for child in node.get_children():
		if child is PopupPanel:
			(child as PopupPanel).add_theme_stylebox_override("panel", _popup_style())
		_apply_popup_styles(child)

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
	var viewport := get_viewport().get_visible_rect().size
	if viewport.is_equal_approx(_last_size):
		return
	_last_size = viewport
	var compact := viewport.x < 1180.0
	var tight := viewport.x < 1040.0

	var sidebar := _root.find_child("Sidebar", true, false) as Control
	if sidebar != null and OS.get_name() != "Android":
		sidebar.custom_minimum_size.x = SIDEBAR_COMPACT if compact else SIDEBAR_WIDE

	var avatar_slot := _root.find_child("AvatarSlot", true, false) as Control
	if avatar_slot != null and OS.get_name() != "Android":
		avatar_slot.custom_minimum_size = Vector2(44, 40) if tight else (Vector2(46, 42) if compact else Vector2(58, 48))

	var header_margin := _root.find_child("HeaderMargin", true, false) as MarginContainer
	if header_margin != null and OS.get_name() != "Android":
		header_margin.add_theme_constant_override("margin_left", 12 if compact else 24)
		header_margin.add_theme_constant_override("margin_right", 12 if compact else 20)

	var header_actions := _root.find_child("MainHeaderActions", true, false) as HBoxContainer
	if header_actions != null:
		header_actions.add_theme_constant_override("separation", 5 if compact else 8)
		for child in header_actions.get_children():
			if child is Button:
				var button := child as Button
				button.clip_text = true
				if OS.get_name() != "Android":
					button.custom_minimum_size.x = minf(button.custom_minimum_size.x, 108.0 if compact else 132.0)

	var voice_status := _root.find_child("VoiceStatus", true, false) as Label
	if voice_status != null and OS.get_name() != "Android":
		voice_status.visible = not compact

	var main_panel := _root.find_child("MainPanel", true, false) as Control
	if main_panel != null:
		main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var composer := _root.find_child("ComposerMargin", true, false) as MarginContainer
	if composer != null and OS.get_name() != "Android":
		composer.add_theme_constant_override("margin_left", 12 if compact else 24)
		composer.add_theme_constant_override("margin_right", 12 if compact else 24)
		composer.add_theme_constant_override("margin_bottom", 10 if compact else 20)

	var messages := _root.find_child("MessagesMargin", true, false) as MarginContainer
	if messages != null and OS.get_name() != "Android":
		messages.add_theme_constant_override("margin_left", 14 if compact else 26)
		messages.add_theme_constant_override("margin_right", 14 if compact else 26)

	var message_scroll := _root.find_child("MessageScroll", true, false) as ScrollContainer
	if message_scroll != null:
		message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_fit_popups(_root, viewport)

func _fit_popups(node: Node, viewport: Vector2) -> void:
	var max_width := maxi(420, int(viewport.x - 48.0))
	var max_height := maxi(420, int(viewport.y - 48.0))
	for child in node.get_children():
		if child is PopupPanel:
			var popup := child as PopupPanel
			var current := popup.size
			if current.x > 0 and current.y > 0:
				popup.size = Vector2i(mini(current.x, max_width), mini(current.y, max_height))
		_fit_popups(child, viewport)
