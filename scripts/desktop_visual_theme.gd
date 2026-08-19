class_name AuroraDesktopVisualTheme
extends Node

const BACKGROUND: Texture2D = preload("res://assets/ui/aurora_background_user.jpg")
const FOX: Texture2D = preload("res://assets/ui/aurora_fox_user.jpg")
const BUTTON_TEXTURE: Texture2D = preload("res://assets/ui/aurora_button_user.jpg")

const MIN_WINDOW := Vector2i(960, 640)
const WIDE_WIDTH := 1300.0
const COMPACT_WIDTH := 1100.0

var root: Control
var _layout_queued := false

func _ready() -> void:
	if OS.get_name() == "Android":
		return
	root = get_parent() as Control
	if root == null:
		return
	get_window().min_size = MIN_WINDOW
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	await get_tree().process_frame
	_apply_all()
	# Voice/computer/update controls are added one frame later than the base chat.
	await get_tree().create_timer(0.35).timeout
	_apply_all()

func _on_viewport_size_changed() -> void:
	_queue_layout()

func _on_node_added(node: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	if node == root or root.is_ancestor_of(node):
		call_deferred("_apply_node", node)
		_queue_layout()

func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_apply_layout")

func _apply_all() -> void:
	if root == null:
		return
	_walk(root)
	_relocate_update_button()
	_apply_layout()

func _walk(node: Node) -> void:
	_apply_node(node)
	for child in node.get_children():
		_walk(child)

func _apply_node(node: Node) -> void:
	if node is TextureRect:
		_replace_placeholder_texture(node as TextureRect)
	elif node is Button:
		_style_text_button(node as Button)
	elif node is AuroraFoxAvatarView:
		_replace_header_avatar(node as AuroraFoxAvatarView)

func _replace_placeholder_texture(view: TextureRect) -> void:
	if view.texture == null:
		return
	var path := view.texture.resource_path.to_lower()
	if path.ends_with("aurora_background.svg"):
		view.texture = BACKGROUND
		view.modulate = Color.WHITE
	elif path.ends_with("fox_logo.svg"):
		view.texture = FOX
		view.modulate = Color.WHITE

func _replace_header_avatar(view: AuroraFoxAvatarView) -> void:
	var parent := view.get_parent() as Control
	if parent == null or parent.name != "AvatarSlot":
		return
	view.visible = false
	if parent.get_node_or_null("StaticFoxAvatar") != null:
		return
	var fox := TextureRect.new()
	fox.name = "StaticFoxAvatar"
	fox.texture = FOX
	fox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fox.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fox.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fox)

func _style_text_button(button: Button) -> void:
	# Icon-only controls keep their compact vector style. Text controls use the
	# user's AuroraFox neon button surface instead of default Godot rectangles.
	if button.text.strip_edges().is_empty():
		return
	var normal := _button_texture_style(Color(0.92, 0.96, 1.0, 1.0))
	var hover := _button_texture_style(Color(1.0, 1.0, 1.0, 1.0))
	var pressed := _button_texture_style(Color(0.84, 0.88, 1.0, 1.0))
	var disabled := _button_texture_style(Color(0.42, 0.44, 0.52, 0.72))
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color("f4f7ff"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)

func _button_texture_style(tint: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = BUTTON_TEXTURE
	style.modulate_color = tint
	style.texture_margin_left = 26.0
	style.texture_margin_right = 26.0
	style.texture_margin_top = 18.0
	style.texture_margin_bottom = 18.0
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style

func _relocate_update_button() -> void:
	var host := root.find_child("MainHeaderActions", true, false) as HBoxContainer
	var overlay := root.get_node_or_null("UpdateOverlay")
	if host == null or overlay == null:
		return
	var button = overlay.get("open_button")
	if not button is Button:
		return
	var update_button := button as Button
	if update_button.get_parent() != host:
		update_button.reparent(host)
	update_button.name = "UpdateButton"
	update_button.position = Vector2.ZERO
	update_button.custom_minimum_size = Vector2(40, 38)

func _apply_layout() -> void:
	_layout_queued = false
	if root == null or not is_instance_valid(root):
		return
	_relocate_update_button()
	var width := get_viewport().get_visible_rect().size.x
	var compact := width < COMPACT_WIDTH
	var wide := width >= WIDE_WIDTH

	var sidebar := root.find_child("Sidebar", true, false) as Control
	if sidebar != null:
		sidebar.custom_minimum_size.x = 286.0 if wide else (252.0 if not compact else 226.0)

	var header_actions := root.find_child("MainHeaderActions", true, false) as HBoxContainer
	if header_actions != null:
		header_actions.size_flags_horizontal = Control.SIZE_SHRINK_END
		header_actions.add_theme_constant_override("separation", 6 if compact else 8)
		var header := header_actions.get_parent() as HBoxContainer
		if header != null and header.get_child_count() > 0:
			var title_box := header.get_child(0) as Control
			if title_box != null:
				title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				title_box.custom_minimum_size.x = 150.0 if compact else 220.0
				for child in title_box.get_children():
					if child is Label:
						(child as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
						(child as Label).clip_text = true

	var avatar_slot := root.find_child("AvatarSlot", true, false) as Control
	if avatar_slot != null:
		avatar_slot.visible = wide
		avatar_slot.custom_minimum_size = Vector2(50, 46)

	var voice_status := root.find_child("VoiceStatus", true, false) as Label
	if voice_status != null:
		voice_status.visible = wide

	var computer_toggle := root.find_child("ComputerAgentToggle", true, false) as Button
	if computer_toggle != null:
		computer_toggle.custom_minimum_size.x = 102.0 if compact else 118.0
	var computer_auto := root.find_child("ComputerAgentAuto", true, false) as Button
	if computer_auto != null:
		computer_auto.custom_minimum_size.x = 58.0 if compact else 64.0
	var computer_setup := root.find_child("ComputerAgentSetup", true, false) as Button
	if computer_setup != null:
		computer_setup.custom_minimum_size.x = 84.0 if compact else 96.0

	var composer_margin := root.find_child("ComposerMargin", true, false) as MarginContainer
	if composer_margin != null:
		var side_margin := 12 if compact else 24
		composer_margin.add_theme_constant_override("margin_left", side_margin)
		composer_margin.add_theme_constant_override("margin_right", side_margin)
		composer_margin.add_theme_constant_override("margin_bottom", 12 if compact else 20)

	var message_input := root.find_child("MessageInput", true, false) as TextEdit
	if message_input != null:
		message_input.custom_minimum_size.y = 64.0 if compact else 72.0

	# Keep chat-row action buttons compact so long titles never push the sidebar wider.
	var history := root.find_child("ChatList", true, false) as Control
	if history != null:
		for row in history.get_children():
			if row is HBoxContainer:
				for child in row.get_children():
					if child is Button and (child as Button).text.strip_edges().is_empty():
						(child as Button).custom_minimum_size.x = 32.0 if compact else 36.0
