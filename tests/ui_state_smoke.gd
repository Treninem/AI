extends SceneTree

const MOBILE_SIZE := Vector2i(720, 1280)
const SAFE_INSETS := Vector4(14, 28, 16, 24)
const KEYBOARD_INSET := 220

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> bool:
	push_error(message)
	quit(code)
	return false

func _approx(a: float, b: float, tolerance := 1.5) -> bool:
	return absf(a - b) <= tolerance

func _instantiate_mobile(packed: PackedScene) -> Control:
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", true)
	ProjectSettings.set_setting("aurorafox/testing/safe_insets", Vector4.ZERO)
	ProjectSettings.set_setting("aurorafox/testing/keyboard_inset", 0)
	root.wrap_controls = false
	root.min_size = Vector2i(1, 1)
	root.size = MOBILE_SIZE
	root.content_scale_size = MOBILE_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var main := packed.instantiate() as Control
	root.add_child(main)
	await create_timer(1.15).timeout
	await process_frame
	return main

func _exercise_mobile_insets(main: Control) -> bool:
	var adapter := main.get_node_or_null("MobileUI") as MobileUIAdapter
	var root_row := main.find_child("RootLayout", true, false) as Control
	var composer := main.find_child("ComposerMargin", true, false) as MarginContainer
	if adapter == null or root_row == null or composer == null:
		return _fail("Mobile safe-area test controls are missing", 10)

	ProjectSettings.set_setting("aurorafox/testing/safe_insets", SAFE_INSETS)
	ProjectSettings.set_setting("aurorafox/testing/keyboard_inset", KEYBOARD_INSET)
	adapter.call("_apply_mobile_layout")
	await process_frame
	await process_frame

	if not _approx(root_row.offset_left, SAFE_INSETS.x) or not _approx(root_row.offset_top, SAFE_INSETS.y):
		return _fail("Mobile safe-area left/top inset was not applied", 11)
	if not _approx(root_row.offset_right, -SAFE_INSETS.z) or not _approx(root_row.offset_bottom, -SAFE_INSETS.w):
		return _fail("Mobile safe-area right/bottom inset was not applied", 12)
	var composer_bottom := composer.get_theme_constant("margin_bottom")
	if composer_bottom < KEYBOARD_INSET:
		return _fail("Virtual keyboard inset did not lift the composer", 13)
	var viewport := main.get_viewport().get_visible_rect().size
	if composer.position.y + composer.size.y > viewport.y + 2.0:
		return _fail("Composer escaped the mobile viewport after keyboard inset", 14)

	ProjectSettings.set_setting("aurorafox/testing/safe_insets", Vector4.ZERO)
	ProjectSettings.set_setting("aurorafox/testing/keyboard_inset", 0)
	adapter.call("_apply_mobile_layout")
	await process_frame
	return true

func _exercise_account_states(main: Control) -> bool:
	var api := main.get_node_or_null("ApiSettings") as AuroraApiSettingsOverlay
	var login := main.find_child("PersonalLoginButton", true, false) as Button
	var guest := main.find_child("PersonalGuestButton", true, false) as Button
	var status := main.find_child("PersonalSessionStatus", true, false) as Label
	if api == null or login == null or guest == null or status == null:
		return _fail("Account loading/error state controls are missing", 20)

	api.call("_set_personal_controls_busy", true)
	await process_frame
	if not login.disabled or not guest.disabled:
		return _fail("Account loading state does not disable entry actions", 21)
	api.call("_set_personal_controls_busy", false)
	await process_frame
	if login.disabled or guest.disabled:
		return _fail("Account actions did not recover after loading state", 22)

	api.set("_last_personal_error", "OFFLINE_SMOKE • сервис личной синхронизации недоступен")
	api.call("_refresh_personal_ui")
	await process_frame
	if status.text.find("OFFLINE_SMOKE") < 0:
		return _fail("Account offline/error state is not surfaced to the user", 23)
	if status.text.findn("локаль") < 0 and status.text.findn("вход не выполнен") < 0:
		return _fail("Offline account state does not preserve local-mode guidance", 24)
	api.set("_last_personal_error", "")
	api.call("_refresh_personal_ui")
	await process_frame
	return true

func _exercise_knowledge_cancel(main: Control) -> bool:
	var knowledge := main.get_node_or_null("KnowledgeBase") as KnowledgeBaseOverlay
	var cancel := main.find_child("KnowledgeCancelImportButton", true, false) as Button
	var progress := main.find_child("KnowledgeProgress", true, false) as Label
	if knowledge == null or cancel == null or progress == null:
		return _fail("Knowledge cancel-state controls are missing", 30)

	knowledge.call("_set_import_busy", true)
	await process_frame
	if not cancel.visible or cancel.disabled:
		return _fail("Knowledge busy state does not expose safe cancel action", 31)
	knowledge.call("_request_import_cancel")
	await process_frame
	if not cancel.disabled:
		return _fail("Knowledge cancel action can be submitted repeatedly", 32)
	if progress.text.findn("текущ") < 0 or progress.text.findn("безопас") < 0:
		return _fail("Knowledge cancel state does not explain safe completion of current file", 33)
	knowledge.call("_set_import_busy", false)
	await process_frame
	if cancel.visible:
		return _fail("Knowledge cancel action remained visible after busy state ended", 34)
	return true

func _assert_owner_neutral(main: Control) -> bool:
	var background := main.find_child("OwnerBackground", true, false) as TextureRect
	if background == null:
		return _fail("Owner background is missing from state smoke", 40)
	if not background.modulate.is_equal_approx(Color(1, 1, 1, 1)):
		return _fail("Owner background is tinted/dimmed in fast UI state gate", 41)
	return true

func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded", 2)
		return
	var main := await _instantiate_mobile(packed)
	if main == null:
		_fail("Mobile scene could not be instantiated", 3)
		return
	if not _assert_owner_neutral(main):
		return
	if not await _exercise_mobile_insets(main):
		return
	if not await _exercise_account_states(main):
		return
	if not await _exercise_knowledge_cancel(main):
		return
	main.queue_free()
	await process_frame
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", false)
	ProjectSettings.set_setting("aurorafox/testing/safe_insets", Vector4.ZERO)
	ProjectSettings.set_setting("aurorafox/testing/keyboard_inset", 0)
	print("AURORA_UI_STATE_SMOKE_OK safe_area keyboard loading offline error cancel")
	quit(0)
