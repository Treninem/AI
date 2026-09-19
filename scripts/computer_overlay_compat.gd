extends "res://scripts/computer_overlay.gd"

func _apply_button(button: Button, active := false) -> void:
	var border := Color(0.32, 0.37, 0.50, 0.58)
	if active:
		border = Color(0.39, 1.0, 0.62, 0.72)
	button.add_theme_stylebox_override("normal", _style(Color(0.055, 0.066, 0.10, 0.96), border))
	button.add_theme_stylebox_override("hover", _style(Color(0.10, 0.12, 0.18, 1.0), Color(0.38, 0.83, 1.0, 0.82)))
	button.add_theme_stylebox_override("pressed", _style(Color(0.13, 0.12, 0.19, 1.0), Color(0.66, 0.54, 1.0, 0.86)))
	button.add_theme_stylebox_override("focus", _style(Color(0.10, 0.12, 0.18, 1.0), Color(0.66, 0.54, 1.0, 0.86)))
	button.add_theme_color_override("font_color", Color("eef5ff"))
	button.add_theme_font_size_override("font_size", 13)
	button.expand_icon = false
	button.clip_text = true

func _popup_viewport_size() -> Vector2i:
	var window := get_tree().root
	if window != null:
		var logical := window.content_scale_size
		if logical.x > 0 and logical.y > 0:
			return logical
		if window.size.x > 0 and window.size.y > 0:
			return window.size
	var fallback := get_viewport().get_visible_rect().size
	return Vector2i(maxi(1, int(fallback.x)), maxi(1, int(fallback.y)))

func _fit_popup() -> void:
	if popup == null:
		return
	var viewport := _popup_viewport_size()
	var available_width := maxi(1, viewport.x - 24)
	var available_height := maxi(1, viewport.y - 24)
	popup.size = Vector2i(
		mini(590, available_width),
		mini(470, available_height)
	)
	popup.position = Vector2i(
		maxi(0, (viewport.x - popup.size.x) / 2),
		maxi(0, (viewport.y - popup.size.y) / 2)
	)

func show_computer_panel() -> void:
	if not _desktop_panel_available() or popup == null:
		return
	_refresh_control_state()
	_fit_popup()
	popup.popup()
	# Embedded subwindows may reuse an old physical-screen position. Re-apply
	# the logical-canvas geometry after showing so pointer routing stays bounded.
	_fit_popup()
	_refresh_health()
