extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _check_layout(packed: PackedScene, mobile_preview: bool) -> bool:
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", mobile_preview)
	root.min_size = Vector2i(1, 1)
	root.size = Vector2i(720, 1280) if mobile_preview else Vector2i(960, 640)
	var main := packed.instantiate() as Control
	root.add_child(main)
	await create_timer(0.8).timeout
	await process_frame
	var button := main.find_child("EvolutionOpenButton", true, false) as Button
	var sidebar := main.find_child("SidebarContent", true, false) as VBoxContainer
	var surface := main.get_node_or_null("EvolutionRuntime/UserControlSurface")
	if button == null or sidebar == null or surface == null:
		_fail("Evolution navigation controls are missing", 10)
		return false
	if mobile_preview:
		if button.get_parent() == sidebar:
			_fail("Mobile Evolution opener was moved into the hidden sidebar", 11)
			return false
	else:
		if button.get_parent() != sidebar or not button.is_visible_in_tree():
			_fail("Desktop Evolution opener is not visible in the sidebar", 12)
			return false
		var composer := main.find_child("ComposerMargin", true, false) as Control
		if composer == null or button.get_global_rect().intersects(composer.get_global_rect()):
			_fail("Evolution opener overlaps the desktop composer", 13)
			return false
	button.pressed.emit()
	await process_frame
	var popup := surface.get("_popup") as PopupPanel
	if popup == null or not popup.visible:
		_fail("Evolution opener no longer opens its control surface", 14)
		return false
	popup.hide()
	main.queue_free()
	await process_frame
	return true

func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("Main scene did not load", 9)
		return
	if not await _check_layout(packed, false):
		return
	if not await _check_layout(packed, true):
		return
	print("AURORA_EVOLUTION_COMPACT_NAV_OK")
	quit(0)
