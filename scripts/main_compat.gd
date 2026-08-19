extends "res://scripts/main.gd"

func _apply_button(button: Button, accent := false, danger := false, compact := false) -> void:
	var normal := SURFACE_2 if not accent else Color(0.18, 0.11, 0.30, 0.98)
	var hover := Color(0.12, 0.14, 0.21, 0.99)
	var pressed := Color(0.15, 0.11, 0.23, 1.0)
	var border := BORDER
	if accent:
		border = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.8)
		hover = Color(0.23, 0.15, 0.36, 1.0)
	if danger:
		border = Color(DANGER.r, DANGER.g, DANGER.b, 0.55)
		hover = Color(0.27, 0.09, 0.13, 0.98)
	button.add_theme_stylebox_override("normal", _style(normal, border, 12, 1))
	button.add_theme_stylebox_override("hover", _style(hover, border, 12, 1))
	button.add_theme_stylebox_override("pressed", _style(pressed, border, 12, 1))
	button.add_theme_stylebox_override("focus", _style(hover, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.95), 12, 1))
	button.add_theme_stylebox_override("disabled", _style(Color(0.06, 0.07, 0.09, 0.72), Color(0.18, 0.20, 0.25, 0.55), 12, 1))
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_color_override("font_hover_color", WHITE)
	button.add_theme_color_override("font_pressed_color", WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.55, 0.75))
	button.add_theme_font_size_override("font_size", 14 if compact else 15)
	button.expand_icon = true
