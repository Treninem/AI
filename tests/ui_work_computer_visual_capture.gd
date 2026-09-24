extends SceneTree

const OUT_DIR := "res://artifacts/ui"
const MANIFEST_PATH := OUT_DIR + "/work_computer_acceptance_manifest.json"

var _head_sha := ""
var _records: Array = []
var _clicks: Array = []

func _init() -> void:
	_head_sha = OS.get_environment("AURORA_UI_HEAD_SHA").strip_edges()
	call_deferred("_run")

func _fail(message: String, code: int) -> bool:
	push_error(message)
	quit(code)
	return false

func _prepare_output() -> bool:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if err != OK and err != ERR_ALREADY_EXISTS:
		return _fail("Cannot create Work/Computer UI artifact directory", 2)
	return true

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

func _press(button: Button, label: String) -> bool:
	if button == null:
		return _fail("UI click target missing: " + label, 3)
	if button.disabled or not button.visible:
		return _fail("UI click target unavailable: " + label, 4)
	_clicks.append(label)
	button.emit_signal("pressed")
	await process_frame
	await process_frame
	await create_timer(0.08).timeout
	return true

func _wait_visible(window: Window, label: String, timeout_seconds := 5.0) -> bool:
	if window == null:
		return _fail("Popup missing: " + label, 5)
	var left := timeout_seconds
	while left > 0.0:
		if window.visible:
			return true
		await create_timer(0.1).timeout
		left -= 0.1
	return _fail("Popup did not become visible: " + label, 6)

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
	await create_timer(1.25).timeout
	root.wrap_controls = false
	root.min_size = Vector2i(1, 1)
	root.size = size
	await process_frame
	await process_frame
	return main

func _open_tools(main: Control) -> AuroraSettingsOverlay:
	var settings := main.get_node_or_null("SettingsOverlay") as AuroraSettingsOverlay
	if settings == null:
		_fail("SettingsOverlay missing", 7)
		return null
	var settings_button := main.find_child("SettingsButton", true, false) as Button
	if not await _press(settings_button, "Настройки"):
		return null
	if not await _wait_visible(settings.popup, "SettingsPopup"):
		return null
	var tools := settings.popup.find_child("SettingsNav_tools", true, false) as Button
	if not await _press(tools, "Настройки → Инструменты"):
		return null
	return settings

func _assert_popup_geometry(popup: Window, viewport_size: Vector2i, label: String) -> bool:
	if popup == null or not popup.visible:
		return _fail(label + " is not visible", 8)
	if popup.size.x <= 0 or popup.size.y <= 0:
		return _fail(label + " has invalid size", 9)
	if popup.size.x > viewport_size.x or popup.size.y > viewport_size.y:
		return _fail("%s exceeds viewport: popup=%s viewport=%s" % [label, str(popup.size), str(viewport_size)], 10)
	return true

func _capture(name: String, surface: String, size: Vector2i, popup: Window) -> bool:
	if not _assert_popup_geometry(popup, size, surface):
		return false
	await process_frame
	await process_frame
	await create_timer(0.14).timeout
	var texture := root.get_texture()
	if texture == null:
		return _fail("Viewport texture unavailable for " + name, 11)
	var image := texture.get_image()
	if image == null or image.is_empty():
		return _fail("Viewport image unavailable for " + name, 12)
	if root.size != size or image.get_width() != size.x or image.get_height() != size.y:
		return _fail("Framebuffer mismatch for %s: requested=%s window=%s captured=%dx%d" % [name, str(size), str(root.size), image.get_width(), image.get_height()], 13)
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		return _fail("Cannot save " + path, 14)
	_records.append({
		"name": name,
		"surface": surface,
		"viewport": {"width": size.x, "height": size.y},
		"popup_size": {"width": popup.size.x, "height": popup.size.y},
		"clicks": _clicks.duplicate(),
		"head_sha": _head_sha
	})
	print("UI_WORK_COMPUTER_CAPTURE %s %s viewport=%s popup=%s clicks=%s" % [name, surface, str(size), str(popup.size), JSON.stringify(_clicks)])
	return true

func _capture_work(main: Control, size: Vector2i, suffix: String) -> bool:
	_clicks.clear()
	var settings := await _open_tools(main)
	if settings == null:
		return false
	var open_work := _button_by_text(settings.popup, "Открыть Работу")
	if not await _press(open_work, "Инструменты → Открыть Работу"):
		return false
	var work_popup := main.find_child("AuroraWorkPopup", true, false) as PopupPanel
	if not await _wait_visible(work_popup, "AuroraWorkPopup"):
		return false
	for action_name in ["WorkNewProjectButton", "WorkCloseButton"]:
		var action := work_popup.find_child(action_name, true, false) as Button
		if action == null or not action.is_visible_in_tree() or action.text.is_empty():
			return _fail("Work header action missing: " + action_name, 18)
		var font := action.get_theme_font("font")
		var text_width := font.get_string_size(action.text, HORIZONTAL_ALIGNMENT_LEFT, -1, action.get_theme_font_size("font_size")).x
		if action.clip_text or action.size.x < text_width + 24.0:
			return _fail("Work header action label collapsed: " + action_name, 19)
	if not await _capture("desktop_%s_work_%dx%d" % [suffix, size.x, size.y], "work", size, work_popup):
		return false
	var close := _button_by_text(work_popup, "Закрыть")
	if not await _press(close, "Работа → Закрыть"):
		return false
	return true

func _capture_computer(main: Control, size: Vector2i, suffix: String) -> bool:
	_clicks.clear()
	var settings := await _open_tools(main)
	if settings == null:
		return false
	var open_computer := _button_by_text(settings.popup, "Настроить компьютерный режим")
	if not await _press(open_computer, "Инструменты → Настроить компьютерный режим"):
		return false
	var computer_popup := main.find_child("ComputerAgentPopup", true, false) as PopupPanel
	if not await _wait_visible(computer_popup, "ComputerAgentPopup"):
		return false
	var toggle := computer_popup.find_child("ComputerAgentToggle", true, false) as CheckButton
	var auto_toggle := computer_popup.find_child("ComputerAgentAuto", true, false) as CheckButton
	if toggle == null or auto_toggle == null:
		return _fail("Computer permission controls missing", 15)
	if toggle.button_pressed:
		return _fail("Computer control must remain default OFF in visual acceptance", 16)
	if not auto_toggle.disabled:
		return _fail("Computer auto-chain control must be disabled while permission is OFF", 17)
	if not await _capture("desktop_%s_computer_%dx%d" % [suffix, size.x, size.y], "computer", size, computer_popup):
		return false
	var done := _button_by_text(computer_popup, "Готово")
	if not await _press(done, "Компьютерный режим → Готово"):
		return false
	return true

func _run_size(packed: PackedScene, size: Vector2i, suffix: String) -> bool:
	var main := await _instantiate(packed, size)
	if main == null:
		return _fail("Main scene instantiate failed", 18)
	if not await _capture_work(main, size, suffix):
		return false
	if not await _capture_computer(main, size, suffix):
		return false
	main.queue_free()
	await process_frame
	return true

func _write_manifest() -> bool:
	var payload := {
		"head_sha": _head_sha,
		"captures": _records,
		"desktop_only_surfaces": ["work", "computer"]
	}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if file == null:
		return _fail("Cannot write Work/Computer manifest", 19)
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	return true

func _run() -> void:
	if not _prepare_output():
		return
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded", 20)
		return
	if not await _run_size(packed, Vector2i(1440, 900), "wide"):
		return
	if not await _run_size(packed, Vector2i(960, 640), "compact"):
		return
	if not _write_manifest():
		return
	ProjectSettings.set_setting("aurorafox/testing/desktop_preview", false)
	print("AURORA_UI_WORK_COMPUTER_VISUAL_OK captures=%d" % _records.size())
	quit(0)
