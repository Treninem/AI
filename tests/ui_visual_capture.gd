extends SceneTree

const OUT_DIR := "res://artifacts/ui"
const MANIFEST_PATH := OUT_DIR + "/acceptance_manifest.json"

var _records: Array = []
var _click_trail: Array = []
var _platform := ""
var _scenario := ""
var _requested_size := Vector2i.ZERO
var _head_sha := ""

func _init() -> void:
	_head_sha = OS.get_environment("AURORA_UI_HEAD_SHA").strip_edges()
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _prepare_output() -> bool:
	var absolute := ProjectSettings.globalize_path(OUT_DIR)
	var err := DirAccess.make_dir_recursive_absolute(absolute)
	if err != OK and err != ERR_ALREADY_EXISTS:
		_fail("Cannot create UI artifact directory: %s" % error_string(err), 2)
		return false
	return true

func _start_scenario(platform: String, scenario: String, size: Vector2i) -> void:
	_platform = platform
	_scenario = scenario
	_requested_size = size
	_click_trail.clear()
	print("UI_SCENARIO %s %s %dx%d" % [platform, scenario, size.x, size.y])

func _capture(name: String, surface: String) -> bool:
	await process_frame
	await process_frame
	await create_timer(0.16).timeout
	var texture := root.get_texture()
	if texture == null:
		_fail("Viewport texture unavailable for %s" % name, 3)
		return false
	var image := texture.get_image()
	if image == null or image.is_empty():
		_fail("Viewport image is empty for %s" % name, 4)
		return false
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		_fail("Cannot save %s: %s" % [path, error_string(err)], 5)
		return false
	_records.append({
		"name": name,
		"surface": surface,
		"platform": _platform,
		"scenario": _scenario,
		"requested_viewport": {"width": _requested_size.x, "height": _requested_size.y},
		"captured_viewport": {"width": image.get_width(), "height": image.get_height()},
		"clicks": _click_trail.duplicate(),
		"head_sha": _head_sha
	})
	print("UI_VISUAL_CAPTURE %s %s %dx%d clicks=%s" % [name, surface, image.get_width(), image.get_height(), JSON.stringify(_click_trail)])
	return true

func _write_manifest() -> bool:
	var payload := {
		"head_sha": _head_sha,
		"generated_at_utc": Time.get_datetime_string_from_system(true),
		"captures": _records,
		"known_missing_client_surfaces": [
			{
				"surface": "login_guest",
				"reason": "No dedicated login/guest client surface exists in the current Godot main scene; visual acceptance does not fabricate one."
			},
			{
				"surface": "user_memory_management",
				"reason": "MemoryStore is present in runtime, but there is no dedicated user memory-management screen in the current client; visual acceptance reports the gap instead of inventing UI."
			}
		]
	}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write visual acceptance manifest", 6)
		return false
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("UI_ACCEPTANCE_MANIFEST %s captures=%d head=%s" % [MANIFEST_PATH, _records.size(), _head_sha])
	return true

func _button_by_name(node: Node, name: String) -> Button:
	if node == null:
		return null
	return node.find_child(name, true, false) as Button

func _button_by_text(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and str((node as Button).text) == text:
		return node as Button
	for child in node.get_children():
		var found := _button_by_text(child, text)
		if found != null:
			return found
	return null

func _press(button: Button, label: String) -> bool:
	if button == null:
		_fail("UI click target missing: %s" % label, 7)
		return false
	if button.disabled:
		_fail("UI click target disabled: %s" % label, 8)
		return false
	_click_trail.append(label)
	print("UI_CLICK %s" % label)
	button.emit_signal("pressed")
	await process_frame
	await process_frame
	await create_timer(0.08).timeout
	return true

func _wait_popup_visible(popup: Window, label: String, timeout_seconds := 5.0) -> bool:
	if popup == null:
		_fail("Popup missing: %s" % label, 9)
		return false
	var left := timeout_seconds
	while left > 0.0:
		if popup.visible:
			return true
		await create_timer(0.1).timeout
		left -= 0.1
	_fail("Popup did not become visible: %s" % label, 9)
	return false

func _populate_chat(main: Control, mobile: bool) -> bool:
	var store = main.get("chats")
	if not store is ChatStore:
		_fail("ChatStore missing during visual capture", 10)
		return false

	# Structural smoke may leave local test chats behind in the same workspace.
	# Visual review must represent a deterministic clean product surface.
	store.chats.clear()
	store.active_chat_id = ""
	store.save_all()
	main.call("_refresh_chat_list")
	main.call("_new_chat")
	await process_frame
	store.add_message("user", "Покажи, как теперь выглядит аккуратный интерфейс без лишних элементов.")
	store.add_message("assistant", "Готово. Основной чат оставляет только нужные действия, а расширенные функции собраны по понятным разделам настроек.")
	store.rename_chat(store.active_chat_id, "Интерфейс AuroraFox" if mobile else "Проверка интерфейса AuroraFox")
	main.call("_render_active_chat")
	main.call("_refresh_chat_list")
	await process_frame
	await process_frame
	return true

func _instantiate(packed: PackedScene, size: Vector2i, mobile: bool) -> Control:
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", mobile)
	root.size = size
	root.content_scale_size = size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.gui_embed_subwindows = true
	var main := packed.instantiate() as Control
	root.add_child(main)
	await create_timer(1.25).timeout
	await process_frame
	return main

func _open_settings_by_click(main: Control) -> AuroraSettingsOverlay:
	var settings := main.get_node_or_null("SettingsOverlay") as AuroraSettingsOverlay
	if settings == null:
		_fail("SettingsOverlay missing during visual acceptance", 11)
		return null
	var settings_button := _button_by_name(main, "SettingsButton")
	if not await _press(settings_button, "Настройки"):
		return null
	if not await _wait_popup_visible(settings.popup, "SettingsPopup"):
		return null
	return settings

func _capture_settings_page(settings: AuroraSettingsOverlay, key: String, click_label: String, image_name: String, surface: String) -> bool:
	var nav := _button_by_name(settings.popup, "SettingsNav_" + key)
	if not await _press(nav, click_label):
		return false
	return await _capture(image_name, surface)

func _open_knowledge_by_click(settings: AuroraSettingsOverlay) -> KnowledgeBaseOverlay:
	var open_button := _button_by_text(settings.popup, "Открыть базу знаний")
	if not await _press(open_button, "Инструменты → Открыть базу знаний"):
		return null
	var knowledge := settings.get_parent().get_node_or_null("KnowledgeBase") as KnowledgeBaseOverlay
	if knowledge == null:
		_fail("KnowledgeBase surface missing during visual acceptance", 12)
		return null
	if not await _wait_popup_visible(knowledge.popup, "KnowledgeBasePopup"):
		return null
	return knowledge

func _close_knowledge_by_click(knowledge: KnowledgeBaseOverlay) -> bool:
	var close := _button_by_text(knowledge.popup, "Закрыть")
	return await _press(close, "База знаний → Закрыть")

func _close_settings_by_click(settings: AuroraSettingsOverlay) -> bool:
	var done := _button_by_name(settings.popup, "SettingsDoneButton")
	return await _press(done, "Настройки → Готово")

func _capture_desktop_full(packed: PackedScene) -> bool:
	var size := Vector2i(1440, 900)
	_start_scenario("Windows", "full_acceptance", size)
	var main := await _instantiate(packed, size, false)
	if main == null:
		_fail("Desktop scene instantiate failed", 20)
		return false
	if not await _populate_chat(main, false):
		return false
	if not await _capture("desktop_chat_1440x900", "chat"):
		return false

	var settings := await _open_settings_by_click(main)
	if settings == null:
		return false
	if not await _capture("desktop_settings_general_1440x900", "settings/degraded_runtime"):
		return false
	if not await _capture_settings_page(settings, "files", "Настройки → Файлы и проекты", "desktop_files_projects_1440x900", "files_projects"):
		return false
	if not await _capture_settings_page(settings, "tools", "Настройки → Инструменты", "desktop_tools_1440x900", "tools"):
		return false
	var knowledge := await _open_knowledge_by_click(settings)
	if knowledge == null:
		return false
	if not await _capture("desktop_knowledge_base_1440x900", "knowledge_base"):
		return false
	if not await _close_knowledge_by_click(knowledge):
		return false

	settings = await _open_settings_by_click(main)
	if settings == null:
		return false
	if not await _capture_settings_page(settings, "updates", "Настройки → Обновления", "desktop_updates_1440x900", "updates_error_resilience"):
		return false
	if not await _close_settings_by_click(settings):
		return false
	main.queue_free()
	await process_frame
	return true

func _capture_desktop_compact(packed: PackedScene) -> bool:
	var size := Vector2i(960, 640)
	_start_scenario("Windows", "compact_responsive", size)
	var main := await _instantiate(packed, size, false)
	if main == null:
		_fail("Compact desktop scene instantiate failed", 22)
		return false
	if not await _populate_chat(main, false):
		return false
	if not await _capture("desktop_compact_chat_960x640", "chat_compact"):
		return false
	var settings := await _open_settings_by_click(main)
	if settings == null:
		return false
	if not await _capture("desktop_compact_settings_960x640", "settings_compact"):
		return false
	if not await _close_settings_by_click(settings):
		return false
	main.queue_free()
	await process_frame
	return true

func _capture_mobile_full(packed: PackedScene) -> bool:
	var size := Vector2i(720, 1280)
	_start_scenario("Android", "portrait_acceptance", size)
	var main := await _instantiate(packed, size, true)
	if main == null:
		_fail("Mobile scene instantiate failed", 30)
		return false
	if not await _populate_chat(main, true):
		return false
	if not await _capture("android_portrait_chat_720x1280", "chat"):
		return false

	var menu := _button_by_name(main, "MobileMenuButton")
	if not await _press(menu, "Чаты"):
		return false
	if not await _capture("android_portrait_chat_drawer_720x1280", "chat_navigation"):
		return false

	var settings := await _open_settings_by_click(main)
	if settings == null:
		return false
	if not await _capture("android_portrait_settings_general_720x1280", "settings/degraded_runtime"):
		return false
	if not await _capture_settings_page(settings, "files", "Настройки → Файлы и проекты", "android_portrait_files_projects_720x1280", "files_projects"):
		return false
	if not await _capture_settings_page(settings, "tools", "Настройки → Инструменты", "android_portrait_tools_720x1280", "tools"):
		return false
	var knowledge := await _open_knowledge_by_click(settings)
	if knowledge == null:
		return false
	if not await _capture("android_portrait_knowledge_base_720x1280", "knowledge_base"):
		return false
	if not await _close_knowledge_by_click(knowledge):
		return false

	settings = await _open_settings_by_click(main)
	if settings == null:
		return false
	if not await _capture_settings_page(settings, "updates", "Настройки → Обновления", "android_portrait_updates_720x1280", "updates_error_resilience"):
		return false
	if not await _close_settings_by_click(settings):
		return false
	var back := _button_by_name(main, "MobileBackButton")
	if not await _press(back, "Назад в чат"):
		return false
	main.queue_free()
	await process_frame
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", false)
	return true

func _capture_mobile_narrow(packed: PackedScene) -> bool:
	var size := Vector2i(480, 960)
	_start_scenario("Android", "narrow_responsive", size)
	var main := await _instantiate(packed, size, true)
	if main == null:
		_fail("Narrow mobile scene instantiate failed", 32)
		return false
	if not await _populate_chat(main, true):
		return false
	if not await _capture("android_narrow_chat_480x960", "chat_narrow"):
		return false
	var menu := _button_by_name(main, "MobileMenuButton")
	if not await _press(menu, "Чаты"):
		return false
	var settings := await _open_settings_by_click(main)
	if settings == null:
		return false
	if not await _capture("android_narrow_settings_480x960", "settings_narrow"):
		return false
	if not await _close_settings_by_click(settings):
		return false
	main.queue_free()
	await process_frame
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", false)
	return true

func _run() -> void:
	if not _prepare_output():
		return
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded", 40)
		return
	if not await _capture_desktop_full(packed):
		return
	if not await _capture_desktop_compact(packed):
		return
	if not await _capture_mobile_full(packed):
		return
	if not await _capture_mobile_narrow(packed):
		return
	if not _write_manifest():
		return
	print("AURORA_UI_VISUAL_ACCEPTANCE_OK captures=%d" % _records.size())
	quit(0)
