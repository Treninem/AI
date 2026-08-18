extends Node

var computer := ComputerClient.new()
var enabled := false
var auto_execute := false
var main: Control
var status_label: Label

func _ready() -> void:
	add_child(computer)
	await get_tree().process_frame
	main = get_parent() as Control
	if main == null:
		return
	_build_controls()
	var health := await computer.health()
	status_label.text = "Компьютер: %s" % ("готов" if health.get("ok", false) else "не запущен")

func _build_controls() -> void:
	var panel := HBoxContainer.new()
	panel.name = "ComputerControls"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-430, 72)
	panel.size = Vector2(410, 44)
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
	auto.tooltip_text = "Если включено, последовательность безопасных действий выполняется без подтверждения каждого шага"
	auto.pressed.connect(func():
		auto_execute = not auto_execute
		auto.text = "Авто: %s" % ("ВКЛ" if auto_execute else "ВЫКЛ")
	)
	panel.add_child(auto)

	status_label = Label.new()
	status_label.text = "Компьютер: проверка…"
	panel.add_child(status_label)

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
