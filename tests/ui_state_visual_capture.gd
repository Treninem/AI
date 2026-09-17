extends SceneTree

const OUT_DIR := "res://artifacts/ui"
const MANIFEST_PATH := OUT_DIR + "/state_acceptance_manifest.json"

var _records: Array = []
var _head_sha := ""

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
		return _fail("Cannot create transient UI artifact directory", 2)
	return true

func _reset_mobile_overrides() -> void:
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", false)
	ProjectSettings.set_setting("aurorafox/testing/safe_insets", Vector4.ZERO)
	ProjectSettings.set_setting("aurorafox/testing/keyboard_inset", 0)

func _instantiate(packed: PackedScene, size: Vector2i, mobile: bool, safe := Vector4.ZERO, keyboard := 0) -> Control:
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", mobile)
	ProjectSettings.set_setting("aurorafox/testing/safe_insets", safe)
	ProjectSettings.set_setting("aurorafox/testing/keyboard_inset", keyboard)
	root.wrap_controls = false
	root.min_size = Vector2i(1, 1)
	root.size = size
	root.content_scale_size = size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.gui_embed_subwindows = true
	var main := packed.instantiate() as Control
	root.add_child(main)
	await create_timer(1.2).timeout
	root.size = size
	await process_frame
	await process_frame
	return main

func _capture(name: String, state: String, expected_size: Vector2i, details: Dictionary = {}) -> bool:
	await process_frame
	await process_frame
	await create_timer(0.12).timeout
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		return _fail("Transient framebuffer unavailable: " + name, 3)
	if root.size != expected_size or image.get_width() != expected_size.x or image.get_height() != expected_size.y:
		return _fail("Transient framebuffer size mismatch: %s requested=%s window=%s captured=%dx%d" % [name, str(expected_size), str(root.size), image.get_width(), image.get_height()], 4)
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		return _fail("Cannot save transient UI capture: " + name, 5)
	_records.append({
		"name": name,
		"state": state,
		"viewport": {"width": expected_size.x, "height": expected_size.y},
		"details": details,
		"head_sha": _head_sha
	})
	print("UI_STATE_CAPTURE %s state=%s details=%s" % [name, state, JSON.stringify(details)])
	return true

func _press(button: Button, label: String) -> bool:
	if button == null or button.disabled:
		return _fail("Transient UI click unavailable: " + label, 6)
	button.emit_signal("pressed")
	await process_frame
	await process_frame
	await create_timer(0.08).timeout
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

func _open_settings(main: Control) -> AuroraSettingsOverlay:
	var settings := main.get_node_or_null("SettingsOverlay") as AuroraSettingsOverlay
	var button := main.find_child("SettingsButton", true, false) as Button
	if settings == null or not await _press(button, "Настройки"):
		return null
	await create_timer(0.08).timeout
	return settings

func _select_page(settings: AuroraSettingsOverlay, key: String) -> bool:
	var nav := settings.popup.find_child("SettingsNav_" + key, true, false) as Button
	if nav != null:
		return await _press(nav, "Настройки → " + key)
	var selector := settings.popup.find_child("SettingsMobileNavigation", true, false) as OptionButton
	if selector == null:
		return _fail("Transient settings selector missing for page " + key, 7)
	var target := -1
	for i in range(selector.item_count):
		if str(selector.get_item_metadata(i)) == key:
			target = i
			break
	if target < 0:
		return _fail("Transient settings page missing: " + key, 8)
	selector.select(target)
	selector.emit_signal("item_selected", target)
	await process_frame
	await process_frame
	return true

func _capture_safe_area(packed: PackedScene) -> bool:
	var size := Vector2i(720, 1280)
	var safe := Vector4(16, 32, 16, 24)
	var main := await _instantiate(packed, size, true, safe, 0)
	var row := main.find_child("RootLayout", true, false) as Control
	if row == null or absf(row.offset_top - safe.y) > 1.5:
		return _fail("Safe-area visual fixture was not applied", 10)
	if not await _capture("android_state_safe_area_720x1280", "safe_area", size, {"insets": [safe.x, safe.y, safe.z, safe.w]}):
		return false
	main.queue_free()
	await process_frame
	_reset_mobile_overrides()
	return true

func _capture_keyboard(packed: PackedScene) -> bool:
	var size := Vector2i(480, 960)
	var safe := Vector4(10, 24, 10, 16)
	var keyboard := 250
	var main := await _instantiate(packed, size, true, safe, keyboard)
	var composer := main.find_child("ComposerMargin", true, false) as MarginContainer
	if composer == null or composer.get_theme_constant("margin_bottom") < keyboard:
		return _fail("Keyboard visual fixture did not lift composer", 11)
	if not await _capture("android_state_keyboard_480x960", "keyboard", size, {"logical_keyboard_inset": keyboard}):
		return false
	main.queue_free()
	await process_frame
	_reset_mobile_overrides()
	return true

func _capture_account_loading(packed: PackedScene) -> bool:
	var size := Vector2i(960, 640)
	var main := await _instantiate(packed, size, false)
	var settings := await _open_settings(main)
	if settings == null or not await _select_page(settings, "account"):
		return false
	var api := main.get_node_or_null("ApiSettings") as AuroraApiSettingsOverlay
	if api == null:
		return _fail("ApiSettings missing for loading capture", 12)
	api.set("_personal_session", {})
	api.set("_personal_memory_cache", [])
	api.call("_refresh_personal_ui")
	api.call("_set_personal_controls_busy", true)
	await process_frame
	var login := main.find_child("PersonalLoginButton", true, false) as Button
	var guest := main.find_child("PersonalGuestButton", true, false) as Button
	if login == null or guest == null or not login.disabled or not guest.disabled:
		return _fail("Loading state is not visible through disabled account actions", 13)
	if not await _capture("desktop_state_account_loading_960x640", "loading", size, {"surface": "account"}):
		return false
	api.call("_set_personal_controls_busy", false)
	main.queue_free()
	await process_frame
	return true

func _capture_account_offline_error(packed: PackedScene) -> bool:
	var size := Vector2i(720, 1280)
	var main := await _instantiate(packed, size, true)
	var settings := await _open_settings(main)
	if settings == null or not await _select_page(settings, "account"):
		return false
	var api := main.get_node_or_null("ApiSettings") as AuroraApiSettingsOverlay
	if api == null:
		return _fail("ApiSettings missing for offline/error capture", 14)
	api.set("_personal_session", {})
	api.set("_personal_memory_cache", [])
	api.set("_last_personal_error", "Сервис личной синхронизации сейчас недоступен. Локальный AuroraFox Core продолжает работать офлайн.")
	api.call("_refresh_personal_ui")
	await process_frame
	var status := main.find_child("PersonalSessionStatus", true, false) as Label
	if status == null or status.text.findn("недоступ") < 0 or status.text.findn("офлайн") < 0:
		return _fail("Offline/error state is not visible on account page", 15)
	if not await _capture("android_state_account_offline_error_720x1280", "offline_error", size, {"local_core_available": true}):
		return false
	api.set("_last_personal_error", "")
	api.call("_refresh_personal_ui")
	main.queue_free()
	await process_frame
	_reset_mobile_overrides()
	return true

func _capture_knowledge_cancel(packed: PackedScene) -> bool:
	var size := Vector2i(1440, 900)
	var main := await _instantiate(packed, size, false)
	var settings := await _open_settings(main)
	if settings == null or not await _select_page(settings, "tools"):
		return false
	var open := _button_by_text(settings.popup, "Открыть базу знаний")
	if not await _press(open, "Открыть базу знаний"):
		return false
	var knowledge := main.get_node_or_null("KnowledgeBase") as KnowledgeBaseOverlay
	if knowledge == null:
		return _fail("KnowledgeBase missing for cancel capture", 16)
	await create_timer(0.08).timeout
	knowledge.call("_set_import_busy", true)
	knowledge.call("_request_import_cancel")
	await process_frame
	var cancel := main.find_child("KnowledgeCancelImportButton", true, false) as Button
	var progress := main.find_child("KnowledgeProgress", true, false) as Label
	if cancel == null or progress == null or not cancel.visible or not cancel.disabled or progress.text.findn("безопас") < 0:
		return _fail("Knowledge cancel visual state is incomplete", 17)
	if not await _capture("desktop_state_knowledge_cancel_1440x900", "cancel", size, {"current_file_finishes_safely": true}):
		return false
	knowledge.call("_set_import_busy", false)
	main.queue_free()
	await process_frame
	return true

func _write_manifest() -> bool:
	var payload := {"head_sha": _head_sha, "states": _records}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if file == null:
		return _fail("Cannot write transient state manifest", 20)
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	return true

func _run() -> void:
	if not _prepare_output():
		return
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded", 21)
		return
	if not await _capture_safe_area(packed):
		return
	if not await _capture_keyboard(packed):
		return
	if not await _capture_account_loading(packed):
		return
	if not await _capture_account_offline_error(packed):
		return
	if not await _capture_knowledge_cancel(packed):
		return
	if not _write_manifest():
		return
	_reset_mobile_overrides()
	print("AURORA_UI_STATE_VISUAL_ACCEPTANCE_OK states=5")
	quit(0)
