extends Node

var computer := ComputerClient.new()
var enabled := false
var auto_execute := false
var main: Control
var status_label: Label
var setup_button: Button
var enabled_toggle: CheckButton
var auto_toggle: CheckButton
var popup: PopupPanel
var setup_busy := false

func _ready() -> void:
	add_child(computer)
	await get_tree().create_timer(0.7).timeout
	main = get_parent() as Control
	if main == null:
		return
	_build_panel()
	_sync_computer_permission()
	await _refresh_health()

func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _apply_button(button: Button, active := false) -> void:
	var border := Color(0.32, 0.37, 0.50, 0.58)
	if active:
		border = Color(0.39, 1.0, 0.62, 0.72)
	button.add_theme_stylebox_override("normal", _style(Color(0.055, 0.066, 0.10, 0.96), border))
	button.add_theme_stylebox_override("hover", _style(Color(0.10, 0.12, 0.18, 1.0), Color(0.38, 0.83, 1.0, 0.82)))
	button.add_theme_stylebox_override("pressed", _style(Color(0.13, 0.12, 0.19, 1.0), Color(0.66, 0.54, 1.0, 0.86)))
	button.add_theme_stylebox_override("focus", _style(Color(0.10, 0.12, 0.18, 1.0), Color(0.66, 0.54, 1.0, 0.86)))
	button.add_theme_color_override("font_color", Color("eef5ff"))
	button.add_theme_font_size_override("font_size", 14)
	button.expand_icon = true
	button.clip_text = true

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.022, 0.028, 0.05, 0.995)
	style.border_color = Color(0.34, 0.68, 0.94, 0.78)
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.72)
	style.shadow_size = 18
	return style

func _build_panel() -> void:
	popup = PopupPanel.new()
	popup.name = "ComputerAgentPopup"
	popup.size = Vector2i(590, 470)
	popup.add_theme_stylebox_override("panel", _panel_style())
	main.add_child(popup)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	popup.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Компьютерный режим"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Высокоуровневую задачу планирует только локальный AuroraFox Core. Computer Agent выполняет уже выбранные действия и остаётся выключенным, пока доступ не разрешён здесь."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("b9c7dc"))
	box.add_child(hint)

	enabled_toggle = CheckButton.new()
	enabled_toggle.name = "ComputerAgentToggle"
	enabled_toggle.text = "Разрешить доступ к экрану, мыши и клавиатуре"
	enabled_toggle.button_pressed = enabled
	enabled_toggle.toggled.connect(func(value):
		enabled = value
		_sync_computer_permission()
		_refresh_control_state()
	)
	box.add_child(enabled_toggle)

	auto_toggle = CheckButton.new()
	auto_toggle.name = "ComputerAgentAuto"
	auto_toggle.text = "Автопродолжение безопасной цепочки"
	auto_toggle.tooltip_text = "Разрешить локальному AuroraFox Core продолжать безопасную цепочку без подтверждения каждого шага"
	auto_toggle.button_pressed = auto_execute
	auto_toggle.toggled.connect(func(value):
		auto_execute = value
		_refresh_control_state()
	)
	box.add_child(auto_toggle)
	var auto_hint := Label.new()
	auto_hint.text = "Работает только после явного разрешения компьютерного режима; permission и master stop продолжают действовать."
	auto_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auto_hint.add_theme_font_size_override("font_size", 12)
	auto_hint.add_theme_color_override("font_color", Color("9fabc0"))
	box.add_child(auto_hint)

	status_label = Label.new()
	status_label.name = "ComputerAgentStatus"
	status_label.text = "Проверяю локальный Computer Agent…"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("8ddfff"))
	box.add_child(status_label)

	setup_button = Button.new()
	setup_button.name = "ComputerAgentSetup"
	setup_button.text = "Подготовить локальный Computer Agent"
	setup_button.tooltip_text = "Установить локальный runtime компьютерного режима"
	setup_button.custom_minimum_size.y = 44
	setup_button.pressed.connect(_setup_runtime)
	setup_button.visible = false
	_apply_button(setup_button, false)
	box.add_child(setup_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var close := Button.new()
	close.text = "Готово"
	close.pressed.connect(func(): popup.hide())
	_apply_button(close, false)
	box.add_child(close)
	_refresh_control_state()

func _desktop_panel_available() -> bool:
	return OS.get_name() == "Windows" or bool(ProjectSettings.get_setting("aurorafox/testing/desktop_preview", false))

func show_computer_panel() -> void:
	if not _desktop_panel_available() or popup == null:
		return
	_refresh_control_state()
	_fit_popup()
	popup.popup_centered()
	_refresh_health()

func _fit_popup() -> void:
	var viewport := get_viewport().get_visible_rect().size
	popup.size = Vector2i(
		maxi(360, mini(590, int(viewport.x - 40.0))),
		maxi(420, mini(470, int(viewport.y - 40.0)))
	)

func _sync_computer_permission() -> void:
	# ComputerClient in the reliability lane owns the process-wide permission.
	# Keep feature detection so this UI branch remains parse/runtime-compatible
	# until that lane is merged into main.
	if computer != null and computer.has_method("set_computer_control_enabled"):
		computer.call("set_computer_control_enabled", enabled)

func _computer_primitives_ready() -> bool:
	if main == null:
		return false
	var registry = main.get("tools")
	if not registry is ToolRegistry:
		return false
	for tool_name in ["computer_action", "computer_screenshot", "computer_windows"]:
		if not registry.tools.has(tool_name):
			return false
	return true

func _refresh_control_state() -> void:
	if enabled_toggle != null:
		enabled_toggle.set_pressed_no_signal(enabled)
	if auto_toggle != null:
		auto_toggle.set_pressed_no_signal(auto_execute)
		auto_toggle.disabled = not enabled

func _refresh_health() -> void:
	var health := await computer.health()
	var ok := bool(health.get("ok", false))
	var primitives_ready := _computer_primitives_ready()
	if status_label != null:
		if ok and primitives_ready:
			status_label.text = "Локальный Computer Agent готов. Планирование выполняет AuroraFox Core."
			status_label.add_theme_color_override("font_color", Color("64ff9d"))
		elif ok:
			status_label.text = "Computer Agent найден, но защищённые Core-примитивы ещё не интегрированы. Выполнение задач заблокировано до безопасного контракта."
			status_label.add_theme_color_override("font_color", Color("ffbd75"))
		else:
			status_label.text = "Локальный Computer Agent не запущен. Основной чат AuroraFox продолжает работать без него."
			status_label.add_theme_color_override("font_color", Color("ffbd75"))
	if setup_button != null:
		setup_button.visible = not ok and OS.get_name() == "Windows" and not computer.installer_path().is_empty()

func _setup_runtime() -> void:
	if setup_busy or OS.get_name() != "Windows":
		return
	var installer := computer.installer_path()
	if installer.is_empty():
		if status_label != null:
			status_label.text = "Установщик Computer Agent не найден в текущей сборке."
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
		setup_button.text = "Повторить подготовку"
		status_label.text = "Не удалось запустить подготовку Computer Agent."
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
			setup_button.text = "Подготовить локальный Computer Agent"
			await _refresh_health()
			return
	setup_busy = false
	setup_button.disabled = false
	setup_button.text = "Повторить подготовку"
	status_label.text = "Подготовка не завершилась. Можно повторить — основной чат не затронут."

func _agent_core() -> AgentCore:
	if main == null:
		return null
	var candidate = main.get("agent")
	return candidate as AgentCore if candidate is AgentCore else null

func _local_ai() -> AIClient:
	if main == null:
		return null
	var candidate = main.get("ai")
	return candidate as AIClient if candidate is AIClient else null

func execute_goal(goal: String, max_steps: int = 30) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "Компьютерный режим выключен пользователем"}
	var clean_goal := goal.strip_edges()
	if clean_goal.is_empty():
		return {"ok": false, "error": "empty_goal"}
	if not _computer_primitives_ready():
		if status_label != null:
			status_label.text = "Выполнение заблокировано: защищённые Computer-примитивы AuroraFox Core ещё не доступны."
		return {
			"ok": false,
			"error": "protected_computer_primitives_unavailable",
			"planning_owner": "aurorafox_core",
			"service_side_planning": false,
		}
	var core := _agent_core()
	if core == null:
		return {"ok": false, "error": "aurorafox_core_unavailable"}
	_sync_computer_permission()
	if status_label != null:
		status_label.text = "AuroraFox Core планирует и выполняет компьютерную задачу…"
	var bounded_steps := clampi(max_steps, 1, 100)
	var confirmation_rule := (
		"Продолжай безопасную цепочку без отдельного подтверждения каждого шага, но соблюдай все permission/master-stop ограничения."
		if auto_execute else
		"Не продолжай неоднозначное, потенциально опасное или необратимое действие без подтверждения пользователя."
	)
	var task := """Выполни текущую задачу пользователя на компьютере: %s
Планирование выполняй только собственным AuroraFox Core. Не используй sidecar/service-side AI planning. Используй доступные Computer primitives через ToolRegistry. Максимум логических шагов: %d. %s""" % [clean_goal, bounded_steps, confirmation_rule]
	var response := await core.run_task(task, [])
	var ok := not response.begins_with("Ошибка модели:") and not response.begins_with("__AURORA_WORK_CONTROL__:")
	if status_label != null:
		status_label.text = "Компьютерная задача завершена." if ok else "AuroraFox Core остановил компьютерную задачу."
	return {
		"ok": ok,
		"response": response,
		"planning_owner": "aurorafox_core",
		"service_side_planning": false,
	}

func preview_next_action(goal: String) -> Dictionary:
	var clean_goal := goal.strip_edges()
	if clean_goal.is_empty():
		return {"ok": false, "error": "empty_goal"}
	var local_ai := _local_ai()
	if local_ai == null:
		return {"ok": false, "error": "aurorafox_core_unavailable"}
	var result := await local_ai.chat([
		{
			"role": "system",
			"content": "Ты локальный AuroraFox Core. Составь только краткий план следующего компьютерного действия. Ничего не выполняй, не вызывай инструменты и не выдавай JSON tool-call. Учитывай, что Computer Agent — только исполнитель проверенных primitives."
		},
		{"role": "user", "content": clean_goal},
	])
	if not result.get("ok", false):
		return {"ok": false, "error": str(result.get("error", "core_preview_failed"))}
	return {
		"ok": true,
		"plan": str(result.get("content", "")),
		"planning_owner": "aurorafox_core",
		"executed": false,
	}
