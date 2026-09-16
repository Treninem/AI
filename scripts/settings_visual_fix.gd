class_name AuroraSettingsVisualFix
extends Node

func _ready() -> void:
	call_deferred("_apply")

func _apply() -> void:
	for _i in range(5):
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
	if overlay.has_method("_fit_popup"):
		overlay.call("_fit_popup")
	_fix_mobile_navigation(panel)
	_apply_controls(panel)
	# Generic visual normalization must not flatten the selected state of
	# the category navigation. Ask the settings controller to repaint it last.
	if overlay.has_method("_select_page"):
		var pages = overlay.get("page_stack")
		var indices = overlay.get("nav_indices")
		if pages is TabContainer and indices is Dictionary:
			var current_key := "general"
			for key in indices.keys():
				if int(indices[key]) == pages.current_tab:
					current_key = str(key)
					break
			overlay.call("_select_page", current_key)

func _is_mobile_layout() -> bool:
	return OS.get_name() == "Android" or bool(ProjectSettings.get_setting("aurorafox/testing/mobile_preview", false))

func _fix_mobile_navigation(panel: PopupPanel) -> void:
	if not _is_mobile_layout():
		return
	var scroll := panel.find_child("SettingsMobileNavigationScroll", true, false) as ScrollContainer
	var nav := panel.find_child("SettingsMobileNavigation", true, false) as HFlowContainer
	if scroll == null or nav == null:
		return

	# HFlowContainer inside ScrollContainer otherwise receives the viewport's
	# minimum width and wraps every category into a narrow vertical column.
	# Give the category strip a deterministic content width so it remains one
	# horizontal row and the ScrollContainer handles the overflow naturally.
	scroll.custom_minimum_size.y = 52
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	nav.custom_minimum_size = Vector2(930, 46)
	nav.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	nav.add_theme_constant_override("h_separation", 7)
	nav.add_theme_constant_override("v_separation", 0)

	var widths := {
		"SettingsNav_general": 132.0,
		"SettingsNav_voice": 112.0,
		"SettingsNav_files": 168.0,
		"SettingsNav_autonomy": 154.0,
		"SettingsNav_tools": 144.0,
		"SettingsNav_updates": 146.0
	}
	for child in nav.get_children():
		if child is Button:
			var button := child as Button
			button.custom_minimum_size = Vector2(float(widths.get(button.name, 140.0)), 44)
			button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			button.clip_text = false

func _apply_controls(node: Node) -> void:
	for child in node.get_children():
		if child is Label:
			var label := child as Label
			label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.42))
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
			if not button.name.begins_with("SettingsNav_"):
				button.add_theme_stylebox_override("normal", _button_style(Color(0.058, 0.064, 0.105, 1.0), Color(0.28, 0.44, 0.68, 0.66)))
				button.add_theme_stylebox_override("hover", _button_style(Color(0.105, 0.08, 0.19, 1.0), Color(0.48, 0.77, 1.0, 0.90)))
				button.add_theme_stylebox_override("pressed", _button_style(Color(0.14, 0.07, 0.22, 1.0), Color(0.66, 0.53, 1.0, 0.94)))
				button.add_theme_stylebox_override("focus", _button_style(Color(0.10, 0.08, 0.18, 1.0), Color(0.38, 0.82, 1.0, 0.90)))
				button.add_theme_color_override("font_color", Color("f4f7ff"))
			# clip_text removes the text contribution from Button minimum width.
			# In HFlowContainer this collapsed action buttons into empty pills.
			# Keep labels visible and let flow containers wrap them naturally.
			button.clip_text = false
			if button.get_parent() is HFlowContainer:
				button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 40.0)
				button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_apply_controls(child)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.020, 0.024, 0.041, 1.0)
	style.border_color = Color(0.34, 0.50, 0.78, 0.78)
	style.set_border_width_all(1)
	style.set_corner_radius_all(20)
	style.shadow_color = Color(0, 0, 0, 0.76)
	style.shadow_size = 20
	return style

func _input_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.041, 0.068, 1.0)
	style.border_color = Color(0.46, 0.76, 1.0, 0.86) if focused else Color(0.22, 0.31, 0.48, 0.76)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 11
	style.content_margin_right = 11
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
