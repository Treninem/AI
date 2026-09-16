extends SceneTree

const OUT_DIR := "res://artifacts/ui"

func _init() -> void:
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

func _capture(name: String) -> bool:
	await process_frame
	await process_frame
	await create_timer(0.15).timeout
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
	print("UI_VISUAL_CAPTURE %s %dx%d" % [name, image.get_width(), image.get_height()])
	return true

func _populate_chat(main: Control, mobile: bool) -> bool:
	var store = main.get("chats")
	if not store is ChatStore:
		_fail("ChatStore missing during visual capture", 10)
		return false

	# The structural smoke runs before visual capture in the same workspace and
	# intentionally creates several chats. Visual review must represent the clean
	# product surface, not test-history leftovers from the previous step.
	store.chats.clear()
	store.active_chat_id = ""
	store.save_all()
	main.call("_refresh_chat_list")
	main.call("_new_chat")
	await process_frame
	store.add_message("user", "Покажи, как теперь выглядит аккуратный интерфейс без лишних элементов.")
	store.add_message("assistant", "Готово. Основной чат оставляет только нужные действия, а расширенные функции собраны по понятным разделам настроек.")
	# The first user message intentionally auto-generates a title in ChatStore.
	# Rename after populating so screenshots exercise a stable, readable title.
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

func _capture_desktop(packed: PackedScene) -> bool:
	var main := await _instantiate(packed, Vector2i(1440, 900), false)
	if main == null:
		_fail("Desktop scene instantiate failed", 20)
		return false
	if not await _populate_chat(main, false):
		return false
	if not await _capture("desktop_chat_1440x900"):
		return false

	var settings := main.get_node_or_null("SettingsOverlay") as AuroraSettingsOverlay
	if settings == null:
		_fail("SettingsOverlay missing for desktop visual capture", 21)
		return false
	await settings.show_settings("general")
	await create_timer(0.2).timeout
	if not await _capture("desktop_settings_1440x900"):
		return false
	settings.popup.hide()
	main.queue_free()
	await process_frame
	return true

func _capture_mobile(packed: PackedScene) -> bool:
	var main := await _instantiate(packed, Vector2i(720, 1280), true)
	if main == null:
		_fail("Mobile scene instantiate failed", 30)
		return false
	if not await _populate_chat(main, true):
		return false
	if not await _capture("android_portrait_chat_720x1280"):
		return false

	var settings := main.get_node_or_null("SettingsOverlay") as AuroraSettingsOverlay
	if settings == null:
		_fail("SettingsOverlay missing for mobile visual capture", 31)
		return false
	await settings.show_settings("general")
	await create_timer(0.2).timeout
	if not await _capture("android_portrait_settings_720x1280"):
		return false
	settings.popup.hide()
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
	if not await _capture_desktop(packed):
		return
	if not await _capture_mobile(packed):
		return
	print("AURORA_UI_VISUAL_CAPTURE_OK")
	quit(0)
