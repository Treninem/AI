class_name MobileUIAdapter
extends Node

var sidebar: Control
var root_row: HBoxContainer
var menu_button: Button
var sidebar_open := false

func _ready() -> void:
	if OS.get_name() != "Android": return
	await get_tree().process_frame
	_find_layout()
	_apply_mobile_layout()
	get_viewport().size_changed.connect(_apply_mobile_layout)

func _find_layout() -> void:
	var parent := get_parent()
	if parent == null: return
	for child in parent.get_children():
		if child is HBoxContainer and child.get_child_count() >= 2:
			root_row = child
			break
	if root_row == null: return
	for child in root_row.get_children():
		if child is ColorRect and child.custom_minimum_size.x >= 250:
			sidebar = child
			break

func _apply_mobile_layout() -> void:
	if OS.get_name() != "Android" or root_row == null: return
	var viewport_width := float(get_viewport().get_visible_rect().size.x)
	if sidebar != null:
		sidebar.custom_minimum_size.x = minf(360.0, viewport_width * 0.82)
		sidebar.visible = sidebar_open
	_make_touch_friendly(get_parent())
	_adjust_margins(get_parent())
	_ensure_menu_button()

func _ensure_menu_button() -> void:
	if menu_button != null: return
	menu_button = Button.new()
	menu_button.name = "MobileMenuButton"
	menu_button.text = "☰"
	menu_button.tooltip_text = "Чаты"
	menu_button.custom_minimum_size = Vector2(56, 56)
	menu_button.position = Vector2(10, 8)
	menu_button.z_index = 100
	menu_button.pressed.connect(_toggle_sidebar)
	get_parent().add_child(menu_button)

func _toggle_sidebar() -> void:
	sidebar_open = not sidebar_open
	if sidebar != null: sidebar.visible = sidebar_open

func _make_touch_friendly(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, 50.0)
			child.add_theme_font_size_override("font_size", 17)
		elif child is LineEdit:
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, 50.0)
			child.add_theme_font_size_override("font_size", 17)
		elif child is TextEdit:
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, 100.0)
			child.add_theme_font_size_override("font_size", 18)
		_make_touch_friendly(child)

func _adjust_margins(node: Node) -> void:
	for child in node.get_children():
		if child is MarginContainer:
			var left := child.get_theme_constant("margin_left")
			var right := child.get_theme_constant("margin_right")
			if left > 24: child.add_theme_constant_override("margin_left", 16)
			if right > 24: child.add_theme_constant_override("margin_right", 16)
		_adjust_margins(child)
