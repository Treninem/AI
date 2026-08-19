extends Node

const ICON_COMPUTER: Texture2D = preload("res://assets/ui/icon_computer.svg")

var computer := ComputerClient.new()
var enabled := false
var auto_execute := false
var main: Control
var status_label: Label
var setup_button: Button
var toggle_button: Button
var auto_button: Button
var setup_busy := false

func _ready() -> void:
	add_child(computer)
	await get_tree().create_timer(0.7).timeout
	main = get_parent() as Control
	if main == null:
		return
	_build_controls()
	await _refresh_health()

func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 11
	style.corner_radius_top_right = 11
	style.corner_radius_bottom_left = 11
	style.corner_radius_bottom_right = 11
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

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
	button.icon_max_width = 18

func _build_controls() -> void:
	var host := main.find_child("MainHeaderActions", true, false) as HBoxContainer
	if host == null:
		host = HBoxContainer.new()
		host.visible = false
		main.add_child(host)

	toggle_button = Button.new()
	toggle_button.name = "ComputerAgentToggle"
	toggle_button.text = "Компьютер"
	toggle_button.icon = ICON_COMPUTER
	toggle_button.tooltip_text = "Разрешить AuroraFox видеть экран и управлять мышью/клавиатурой"
	toggle_button.custom_minimum_size = Vector2(118, 38)
	toggle_button.pressed.connect(func():
		enabled = not enabled
		_refresh_control_state()
	)
	_apply_button(toggle_button, false)
	host.add_child(toggle_button)

	auto_button = Button.new()
	auto_button.name = "ComputerAgentAuto"
	auto_button.text = "Авто"
	auto_button.tooltip_text = "Выполнять разрешённую последовательность действий без подтверждения каждого шага"
	auto_button.custom_minimum_size = Vector2(64, 38)
	auto_button.pressed.connect(func():
		auto_execute = not auto_execute
		_refresh_control_state()
	)
	_apply_button(auto_button, false)
	host.add_child(auto_button)

	setup_button = Button.new()
	setup_button.name = "ComputerAgentSetup"
	setup_button.text = "Подготовить"
	setup_button.tooltip_text = "Установить локальный Computer Agent runtime"
	setup_button.custom_minimum_size = Vector2(96, 38)
	setup_button.pressed.connect(_setup_runtime)
	setup_button.visible = false
	_apply_button(setup_button, false)
	host.add_child(setup_button)

	status_label = Label.new()
	status_label.name = "ComputerAgentStatus"
	status_label.visible = false
	main.add_child(status_label)
	_refresh_control_state()

func _refresh_control_state() -> void:
	if toggle_button != null:
		toggle_button.text = "Компьютер" if not enabled else "Компьютер ON"
		_apply_button(toggle_button, enabled)
	if auto_button != null:
		auto_button.text = "Авто" if not auto_execute else "Авто ON"
		_apply_button(auto_button, auto_execute)

func _refresh_health() -> void:
	var health := await computer.health()
	var ok := bool(health.get("ok", false))
	if status_label != null:
		status_label.text = "Компьютер: %s" % ("готов" if ok else "не запущен")
	if toggle_button != null:
		toggle_button.tooltip_text = "Computer Agent готов" if ok else "Computer Agent runtime не запущен"
	if setup_button != null:
		setup_button.visible = not ok and OS.get_name() == "Windows" and not computer.installer_path().is_empty()

func _setup_runtime() -> void:
	if setup_busy or OS.get_name() != "Windows":
		return
	var installer := computer.installer_path()
	if installer.is_empty():
		if toggle_button != null:
			toggle_button.tooltip_text = "Computer Agent: установщик не найден"
		return
	setup_busy = true
	setup_button.disabled = true
	setup_button.text = "Подготовка…"
	var args := PackedStringArray([
		"-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", installer
	])
	var pid := OS.create_process("powershell.exe", args, false)
	if pid <= 0:
		setup_busy = false
		setup_button.disabled = false
		setup_button.text = "Подготовить"
		return

	for _i in range(120):
		await get_tree().create_timer(3.0).timeout
		computer.restart_backend()
		await get_tree().create_timer(0.8).timeout
		var health := await computer.health()
		if bool(health.get("ok", false)):
			setup_busy = false
			setup_button.disabled = false
			setup_button.visible = false
			setup_button.text = "Подготовить"
			await _refresh_health()
			return
	setup_busy = false
	setup_button.disabled = false
	setup_button.text = "Повторить"
	if toggle_button != null:
		toggle_button.tooltip_text = "Computer Agent: установка не завершилась"

func execute_goal(goal: String, max_steps: int = 30) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "Компьютерный режим выключен пользователем"}
	if toggle_button != null:
		toggle_button.text = "Компьютер…"
	var result := await computer.run(goal, max_steps, auto_execute)
	_refresh_control_state()
	if toggle_button != null:
		toggle_button.tooltip_text = "Computer Agent: готов" if result.get("ok", false) else "Computer Agent: ошибка"
	return result

func preview_next_action(goal: String) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "Компьютерный режим выключен пользователем"}
	return await computer.plan(goal)
