class_name WindowsOnboardingBanner
extends Node

const FOX_LOGO: Texture2D = preload("res://assets/ui/aurora_fox_user.jpg")
const ACCENT := Color("a98aff")
const CYAN := Color("45d8ff")
const WHITE := Color("f3f6ff")
const MUTED := Color("8d98ad")

var _banner: PanelContainer

func _ready() -> void:
	if OS.get_name() != "Windows":
		return
	call_deferred("_refresh")

func _style(fill: Color, border: Color, radius := 18) -> StyleBoxFlat:
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
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	return style

func _apply_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _style(Color(0.18, 0.11, 0.30, 0.98), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.82), 12))
	button.add_theme_stylebox_override("hover", _style(Color(0.24, 0.15, 0.38, 1.0), Color(CYAN.r, CYAN.g, CYAN.b, 0.88), 12))
	button.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.10, 0.24, 1.0), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.95), 12))
	button.add_theme_stylebox_override("focus", _style(Color(0.24, 0.15, 0.38, 1.0), Color(CYAN.r, CYAN.g, CYAN.b, 0.95), 12))
	button.add_theme_color_override("font_color", WHITE)
	button.custom_minimum_size.y = 42

func _refresh() -> void:
	var main := get_parent()
	if main == null:
		return
	var ai = main.get("ai")
	if not ai is AIClient:
		return
	var available: bool = bool(await ai.is_available())
	if available:
		_remove_banner()
		return
	_show_banner(main)

func _show_banner(main: Node) -> void:
	if _banner != null and is_instance_valid(_banner):
		return
	var host := main.find_child("MessageList", true, false) as VBoxContainer
	if host == null:
		return

	_banner = PanelContainer.new()
	_banner.name = "LocalAIOnboarding"
	_banner.add_theme_stylebox_override("panel", _style(Color(0.035, 0.043, 0.072, 0.96), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.48), 18))
	host.add_child(_banner)
	host.move_child(_banner, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_banner.add_child(row)

	var logo := TextureRect.new()
	logo.texture = FOX_LOGO
	logo.custom_minimum_size = Vector2(62, 62)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(logo)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	row.add_child(body)

	var title := Label.new()
	title.text = "Локальный AI ещё не подготовлен"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", WHITE)
	body.add_child(title)

	var text := Label.new()
	text.text = "Чат остаётся доступным. AuroraFox сначала проверит уже установленную Ollama и существующие модели; подготовка нужна только если подходящей chat-модели действительно нет."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 13)
	text.add_theme_color_override("font_color", MUTED)
	body.add_child(text)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)
	var prepare := Button.new()
	prepare.text = "Подготовить локальный AI"
	prepare.pressed.connect(func():
		var setup := main.get_node_or_null("ModelSetup")
		if setup != null:
			var popup = setup.get("popup")
			if popup is PopupPanel:
				popup.popup_centered()
	)
	_apply_button(prepare)
	actions.add_child(prepare)

	var settings := Button.new()
	settings.text = "Настройки"
	settings.pressed.connect(func():
		var panel := main.get_node_or_null("SettingsOverlay")
		if panel != null and panel.has_method("show_settings"):
			panel.call("show_settings")
	)
	_apply_button(settings)
	actions.add_child(settings)

func mark_model_ready() -> void:
	_remove_banner()

func _remove_banner() -> void:
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
	_banner = null
