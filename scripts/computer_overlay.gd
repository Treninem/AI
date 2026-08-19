extends Node

var computer := ComputerClient.new()
var enabled := false
var auto_execute := false
var main: Control
var status_label: Label
var setup_button: Button
var setup_busy := false

func _ready() -> void:
	add_child(computer)
	await get_tree().create_timer(0.7).timeout
	main = get_parent() as Control
	if main == null:
		return
	_build_controls()
	await _refresh_health()

func _build_controls() -> void:
	var panel := HBoxContainer.new()
	panel.name = "ComputerControls"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-590, 72)
	panel.size = Vector2(570, 44)
	panel.add_theme_constant_override("separation", 8)
	main.add_child(panel)

	var toggle := Button.new()
	toggle.text = "🖥 Компьютер: ВЫКЛ"
	toggle.tooltip_text = "Разрешить AuroraFox видеть экран и управлять мышью/клавиатурой"
	toggle.pressed.connect(func():
		enabled = not enabled
		toggle.text = "🖥 Компьютер: %s" % ("ВКЛ" if enabled else "ВЫКЛ")
	)
	panel.add_child(toggle)

	var auto := Button.new()
	auto.text = "Авто: ВЫКЛ"
	auto.tooltip_text = "Если включено, последовательность разрешённых действий выполняется без подтверждения каждого шага"
	auto.pressed.connect(func():
		auto_execute = not auto_execute
		auto.text = "Авто: %s" % ("ВКЛ" if auto_execute else "ВЫКЛ")
	)
	panel.add_child(auto)

	setup_button = Button.new()
	setup_button.text = "Подготовить"
	setup_button.tooltip_text = "Установить локальный Computer Agent runtime"
	setup_button.pressed.connect(_setup_runtime)
	setup_button.visible = false
	panel.add_child(setup_button)

	status_label = Label.new()
	status_label.text = "Компьютер: проверка…"
	panel.add_child(status_label)

func _refresh_health() -> void:
	var health := await computer.health()
	var ok := bool(health.get("ok", false))
	status_label.text = "Компьютер: %s" % ("готов" if ok else "не запущен")
	if setup_button != null:
		setup_button.visible = not ok and OS.get_name() == "Windows" and not computer.installer_path().is_empty()

func _setup_runtime() -> void:
	if setup_busy or OS.get_name() != "Windows": return
	var installer := computer.installer_path()
	if installer.is_empty():
		status_label.text = "Компьютер: установщик не найден"
		return
	setup_busy = true
	setup_button.disabled = true
	status_label.text = "Компьютер: подготовка…"
	var args := PackedStringArray([
		"-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", installer
	])
	var pid := OS.create_process("powershell.exe", args, false)
	if pid <= 0:
		setup_busy = false
		setup_button.disabled = false
		status_label.text = "Компьютер: не удалось запустить установку"
		return

	# No fake progress: poll only real /health while the installer works.
	for _i in range(120):
		await get_tree().create_timer(3.0).timeout
		computer.restart_backend()
		await get_tree().create_timer(0.8).timeout
		var health := await computer.health()
		if bool(health.get("ok", false)):
			setup_busy = false
			setup_button.disabled = false
			setup_button.visible = false
			status_label.text = "Компьютер: готов"
			return
	setup_busy = false
	setup_button.disabled = false
	status_label.text = "Компьютер: установка не завершилась"

func execute_goal(goal: String, max_steps: int = 30) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "Компьютерный режим выключен пользователем"}
	status_label.text = "Компьютер: выполняю…"
	var result := await computer.run(goal, max_steps, auto_execute)
	status_label.text = "Компьютер: готов" if result.get("ok", false) else "Компьютер: ошибка"
	return result

func preview_next_action(goal: String) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "Компьютерный режим выключен пользователем"}
	return await computer.plan(goal)
