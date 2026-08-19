extends "res://scripts/computer_overlay.gd"

func _apply_button(button: Button, active := false) -> void:
	var border := Color(0.32, 0.37, 0.50, 0.58)
	if active:
		border = Color(0.39, 1.0, 0.62, 0.72)
	button.add_theme_stylebox_override("normal", _style(Color(0.055, 0.066, 0.10, 0.96), border))
	button.add_theme_stylebox_override("hover", _style(Color(0.10, 0.12, 0.18, 1.0), border))
	button.add_theme_stylebox_override("pressed", _style(Color(0.13, 0.12, 0.19, 1.0), Color(0.66, 0.54, 1.0, 0.86)))
	button.add_theme_stylebox_override("focus", _style(Color(0.10, 0.12, 0.18, 1.0), Color(0.66, 0.54, 1.0, 0.86)))
	button.add_theme_color_override("font_color", Color("eef5ff"))
	button.add_theme_font_size_override("font_size", 12)
	button.expand_icon = true
