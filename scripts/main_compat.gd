extends "res://scripts/main.gd"

const OWNER_BACKGROUND: Texture2D = preload("res://assets/ui/aurora_background_owner.webp")
const OWNER_AVATAR: Texture2D = preload("res://assets/ui/aurora_avatar_owner.webp")

func _apply_button(button: Button, accent := false, danger := false, compact := false) -> void:
	var normal := SURFACE_2 if not accent else Color(0.15, 0.09, 0.25, 0.98)
	var hover := Color(0.105, 0.12, 0.18, 0.99)
	var pressed := Color(0.15, 0.10, 0.23, 1.0)
	var border := BORDER
	if accent:
		border = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.82)
		hover = Color(0.20, 0.13, 0.32, 1.0)
	if danger:
		border = Color(DANGER.r, DANGER.g, DANGER.b, 0.58)
		hover = Color(0.25, 0.08, 0.12, 0.98)
	button.add_theme_stylebox_override("normal", _style(normal, border, 13, 1))
	button.add_theme_stylebox_override("hover", _style(hover, Color(CYAN.r, CYAN.g, CYAN.b, 0.76) if not danger else border, 13, 1))
	button.add_theme_stylebox_override("pressed", _style(pressed, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.95), 13, 1))
	button.add_theme_stylebox_override("focus", _style(hover, Color(CYAN.r, CYAN.g, CYAN.b, 0.90), 13, 1))
	button.add_theme_stylebox_override("disabled", _style(Color(0.06, 0.07, 0.09, 0.72), Color(0.18, 0.20, 0.25, 0.55), 13, 1))
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_color_override("font_hover_color", WHITE)
	button.add_theme_color_override("font_pressed_color", WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.55, 0.75))
	button.add_theme_font_size_override("font_size", 14 if compact else 15)
	button.expand_icon = false
	button.clip_text = true

func _build_ui() -> void:
	super._build_ui()
	_apply_owner_background()
	_apply_owner_brand_art()
	var avatar_slot := find_child("AvatarSlot", true, false) as Control
	if avatar_slot != null:
		avatar_slot.visible = false
		avatar_slot.custom_minimum_size = Vector2.ZERO

func _apply_owner_background() -> void:
	for node in find_children("*", "TextureRect", true, false):
		var rect := node as TextureRect
		if rect.texture == null:
			continue
		var path := rect.texture.resource_path
		if path.ends_with("aurora_background.svg") or path.ends_with("aurora_background_final.svg"):
			rect.name = "OwnerBackground"
			rect.texture = OWNER_BACKGROUND
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			rect.modulate = Color(1, 1, 1, 0.88)

func _apply_owner_brand_art() -> void:
	var brand_row := find_child("BrandRow", true, false) as HBoxContainer
	if brand_row == null:
		return
	for child in brand_row.get_children():
		if child is TextureRect:
			var image := child as TextureRect
			if image.texture != null and image.texture.resource_path.ends_with("fox_logo.svg"):
				image.visible = false
				image.custom_minimum_size = Vector2.ZERO
				image.queue_free()
	var owner := TextureRect.new()
	owner.name = "OwnerAvatar"
	owner.texture = OWNER_AVATAR
	owner.custom_minimum_size = Vector2(52, 52)
	owner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	owner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	owner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand_row.add_child(owner)
	var brand_text := brand_row.get_node_or_null("BrandText")
	if brand_text == null:
		for child in brand_row.get_children():
			if child is VBoxContainer:
				brand_text = child
				break
	if brand_text != null:
		brand_row.move_child(owner, brand_text.get_index())

func _add_welcome_state() -> void:
	var center := VBoxContainer.new()
	center.name = "WelcomeState"
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size.y = maxf(280.0, get_viewport_rect().size.y * 0.46)
	center.add_theme_constant_override("separation", 10)
	message_list.add_child(center)

	var eyebrow := Label.new()
	eyebrow.text = "AURORAFOX CORE"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", ACCENT)
	center.add_child(eyebrow)

	var title := Label.new()
	title.text = "Чем займёмся?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", WHITE)
	center.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Чат, код, файлы и локальные инструменты — без лишних панелей."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size.x = minf(560.0, maxf(280.0, get_viewport_rect().size.x * 0.58))
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", MUTED)
	center.add_child(subtitle)

func _bubble_width() -> float:
	var available := get_viewport_rect().size.x
	if message_scroll != null and message_scroll.size.x > 0.0:
		available = message_scroll.size.x
	available = maxf(240.0, available - 10.0)
	if available < 760.0:
		return maxf(240.0, available * 0.90)
	return minf(780.0, maxf(320.0, available * 0.72))

func _add_message_card(message: Dictionary) -> void:
	super._add_message_card(message)
	if message_list == null or message_list.get_child_count() == 0:
		return
	var row := message_list.get_child(message_list.get_child_count() - 1)
	if not row is HBoxContainer:
		return
	for child in row.get_children():
		if child is TextureRect:
			child.visible = false
			child.custom_minimum_size = Vector2.ZERO
			child.queue_free()
