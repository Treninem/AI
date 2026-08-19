class_name AuroraSettingsVisualFix
extends Node

func _ready() -> void:
	if OS.get_name() == "Android":
		return
	call_deferred("_apply")

func _apply() -> void:
	for _i in range(4):
		await get_tree().process_frame
	var main := get_parent()
	if main == null:
		return
	var overlay := main.get_node_or_null("SettingsOverlay")
	if overlay == null:
		return
	var popup = overlay.get("popup")
	if not popup is PopupPanel:
		return
	var panel := popup as PopupPanel
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.transparent_bg = false
	var viewport_size := get_viewport().get_visible_rect().size
	var target_w := clampi(int(viewport_size.x * 0.72), 720, 980)
	var target_h := clampi(int(viewport_size.y * 0.86), 620, 860)
	panel.size = Vector2i(target_w, target_h)
	_apply_controls(panel)

func _apply_controls(node: Node) -> void:
	for child in node.get_children():
		if child is Label:
			var label := child as Label
			label.add_theme_color_override("font_color", Color("edf3ff"))
			label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
			label.add_theme_constant_override("shadow_offset_x", 1)
			label.add_theme_constant_override("shadow_offset_y", 1)
		elif child is LineEdit:
			var line := child as LineEdit
			line.add_theme_stylebox_override("normal", _input_style(false))
			line.add_theme_stylebox_override("focus", _input_style(true))
			line.add_theme_color_override("font_color", Color("f4f7ff"))
			line.add_theme_color_override("font_placeholder_color", Color("8592a8"))
		elif child is TextEdit:
			var edit := child as TextEdit
			edit.add_theme_stylebox_override("normal", _input_style(false))
			edit.add_theme_stylebox_override("focus", _input_style(true))
			edit.add_theme_color_override("font_color", Color("f4f7ff"))
			edit.add_theme_color_override("font_placeholder_color", Color("8592a8"))
		elif child is Button:
			var button := child as Button
			button.add_theme_stylebox_override("normal", _button_style(Color(0.07, 0.075, 0.12, 1.0), Color(0.30, 0.52, 0.78, 0.72)))
			button.add_theme_stylebox_override("hover", _button_style(Color(0.11, 0.08, 0.19, 1.0), Color(0.64, 0.50, 1.0, 0.94)))
			button.add_theme_stylebox_override("pressed", _button_style(Color(0.14, 0.07, 0.22, 1.0), Color(0.38, 0.82, 1.0, 1.0)))
			button.add_theme_color_override("font_color", Color("f4f7ff"))
		elif child is OptionButton:
			var option := child as OptionButton
			option.add_theme_stylebox_override("normal", _button_style(Color(0.055, 0.06, 0.095, 1.0), Color(0.30, 0.52, 0.78, 0.65)))
			option.add_theme_color_override("font_color", Color("f4f7ff"))
		elif child is CheckButton:
			(child as CheckButton).add_theme_color_override("font_color", Color("f4f7ff"))
		_apply_controls(child)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.022, 0.026, 0.045, 1.0)
	style.border_color = Color(0.38, 0.55, 0.86, 0.90)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.82)
	style.shadow_size = 20
	return style

func _input_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.041, 0.068, 1.0)
	style.border_color = Color(0.46, 0.76, 1.0, 0.92) if focused else Color(0.22, 0.31, 0.48, 0.88)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
