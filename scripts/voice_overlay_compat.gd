extends "res://scripts/voice_overlay.gd"

func _apply_button(button: Button, accent: bool) -> void:
	var border := Color(0.30, 0.34, 0.46, 0.6)
	if accent:
		border = Color(0.27, 0.83, 1.0, 0.68)
	button.add_theme_stylebox_override("normal", _style(Color(0.055, 0.066, 0.10, 0.96), border))
	button.add_theme_stylebox_override("hover", _style(Color(0.10, 0.12, 0.18, 1.0), border))
	button.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.11, 0.22, 1.0), Color(0.66, 0.54, 1.0, 0.85)))
	button.add_theme_stylebox_override("focus", _style(Color(0.10, 0.12, 0.18, 1.0), Color(0.66, 0.54, 1.0, 0.85)))
	button.add_theme_color_override("font_color", Color("eef5ff"))
	button.expand_icon = true
