extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> bool:
	push_error(message)
	quit(code)
	return false

func _button_by_text(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _button_by_text(child, text)
		if found != null:
			return found
	return null

func _wait_visible(window: Window, label: String, timeout_seconds := 8.0) -> bool:
	if window == null:
		return _fail("Window missing: " + label, 2)
	var left := timeout_seconds
	while left > 0.0:
		if window.visible:
			return true
		await create_timer(0.08).timeout
		left -= 0.08
	return _fail("Window did not become visible after real input: " + label, 3)

func _control_screen_center(control: Control) -> Vector2:
	var local_center := control.size * 0.5
	return control.get_viewport().get_screen_transform() * control.get_global_transform_with_canvas() * local_center

func _real_click(button: Button, label: String) -> bool:
	if button == null:
		return _fail("Real-input target missing: " + label, 4)
	if button.disabled or not button.is_visible_in_tree():
		return _fail("Real-input target unavailable: " + label, 5)
	if button.size.x < 2.0 or button.size.y < 2.0:
		return _fail("Real-input target has invalid hit area: " + label, 6)

	var received := {"pressed": false}
	var listener := func(): received["pressed"] = true
	button.pressed.connect(listener)

	var position := _control_screen_center(button)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await process_frame
	await create_timer(0.03).timeout

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.position = position
	down.global_position = position
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.button_mask = 0
	up.position = position
	up.global_position = position
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	await create_timer(0.10).timeout

	if is_instance_valid(button) and button.pressed.is_connected(listener):
		button.pressed.disconnect(listener)
	if not bool(received["pressed"]):
		return _fail("Pointer dispatch did not hit intended control: " + label, 7)
	print("UI_REAL_CLICK %s position=%s" % [label, str(position)])
	return true

func _instantiate(packed: PackedScene, size: Vector2i) -> Control:
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", false)
	ProjectSettings.set_setting("aurorafox/testing/desktop_preview", true)
	root.wrap_controls = false
	root.min_size = Vector2i(1, 1)
	root.size = size
	root.content_scale_size = size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.gui_embed_subwindows = true
	var main := packed.instantiate() as Control
	root.add_child(main)
	await create_timer(1.3).timeout
	root.wrap_controls = false
	root.min_size = Vector2i(1, 1)
	root.size = size
	await process_frame
	await process_frame
	return main

func _open_tools_real(main: Control) -> AuroraSettingsOverlay:
	var settings := main.get_node_or_null("SettingsOverlay") as AuroraSettingsOverlay
	var settings_button := main.find_child("SettingsButton", true, false) as Button
	if settings == null:
		_fail("SettingsOverlay missing in real-input smoke", 8)
		return null
	if not await _real_click(settings_button, "Настройки"):
		return null
	if not await _wait_visible(settings.popup, "SettingsPopup"):
		return null
	var tools := settings.popup.find_child("SettingsNav_tools", true, false) as Button
	if not await _real_click(tools, "Настройки → Инструменты"):
		return null
	return settings

func _assert_window_inside(window: Window, size: Vector2i, label: String) -> bool:
	if window == null or not window.visible:
		return _fail(label + " is not visible", 9)
	if window.size.x <= 0 or window.size.y <= 0 or window.size.x > size.x or window.size.y > size.y:
		return _fail("%s geometry exceeds viewport: %s vs %s" % [label, str(window.size), str(size)], 10)
	return true

func _exercise_work(main: Control, size: Vector2i) -> bool:
	var settings := await _open_tools_real(main)
	if settings == null:
		return false
	var open_work := _button_by_text(settings.popup, "Открыть Работу")
	if not await _real_click(open_work, "Инструменты → Открыть Работу"):
		return false
	var work_popup := main.find_child("AuroraWorkPopup", true, false) as PopupPanel
	if not await _wait_visible(work_popup, "AuroraWorkPopup"):
		return false
	if not _assert_window_inside(work_popup, size, "Work popup"):
		return false
	var task_scroll := work_popup.find_child("WorkTaskScroll", true, false) as ScrollContainer
	if task_scroll == null or not task_scroll.is_visible_in_tree():
		return _fail("Compact-safe Work task scroll is missing", 11)
	var close := _button_by_text(work_popup, "Закрыть")
	if not await _real_click(close, "Работа → Закрыть"):
		return false
	return true

func _exercise_computer(main: Control, size: Vector2i) -> bool:
	var settings := await _open_tools_real(main)
	if settings == null:
		return false
	var open_computer := _button_by_text(settings.popup, "Настроить компьютерный режим")
	if not await _real_click(open_computer, "Инструменты → Настроить компьютерный режим"):
		return false
	var computer_popup := main.find_child("ComputerAgentPopup", true, false) as PopupPanel
	if not await _wait_visible(computer_popup, "ComputerAgentPopup"):
		return false
	if not _assert_window_inside(computer_popup, size, "Computer popup"):
		return false
	var enabled := computer_popup.find_child("ComputerAgentToggle", true, false) as CheckButton
	var automatic := computer_popup.find_child("ComputerAgentAuto", true, false) as CheckButton
	if enabled == null or automatic == null:
		return _fail("Computer permission controls missing", 12)
	if enabled.button_pressed:
		return _fail("Computer permission must remain default OFF", 13)
	if not automatic.disabled:
		return _fail("Computer auto-chain must stay disabled while permission is OFF", 14)
	var done := _button_by_text(computer_popup, "Готово")
	if not await _real_click(done, "Компьютерный режим → Готово"):
		return false
	return true

func _run_size(packed: PackedScene, size: Vector2i) -> bool:
	var main := await _instantiate(packed, size)
	if main == null:
		return _fail("Main scene instantiate failed", 15)
	if not await _exercise_work(main, size):
		return false
	if not await _exercise_computer(main, size):
		return false
	main.queue_free()
	await process_frame
	return true

func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded", 16)
		return
	if not await _run_size(packed, Vector2i(1440, 900)):
		return
	if not await _run_size(packed, Vector2i(960, 640)):
		return
	ProjectSettings.set_setting("aurorafox/testing/desktop_preview", false)
	print("AURORA_UI_REAL_INPUT_OK wide_and_compact work computer")
	quit(0)
