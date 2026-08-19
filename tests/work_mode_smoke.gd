extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded", 2)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout

	var work_manager := main.get_node_or_null("WorkManager") as AuroraWorkManager
	var work_overlay := main.get_node_or_null("WorkOverlay") as AuroraWorkOverlay
	if work_manager == null or work_overlay == null:
		_fail("AuroraFox Work nodes missing", 3)
		return
	var work_button := main.find_child("WorkButton", true, false) as Button
	if work_button == null:
		_fail("AuroraFox Work button was not injected", 4)
		return

	var project := work_manager.store.create_project("Smoke Work", "Keep project context")
	var project_id := str(project.get("id", ""))
	if project_id.is_empty() or work_manager.store.get_project(project_id).is_empty():
		_fail("Work project persistence path failed", 5)
		return
	var task := work_manager.store.create_task(project_id, "Prepare a result", "smoke.md")
	if str(task.get("status", "")) != "queued":
		_fail("Work task queue path failed", 6)
		return

	var settings := main.get_node_or_null("SettingsOverlay")
	if settings == null:
		_fail("SettingsOverlay missing", 7)
		return
	settings.call("show_settings")
	await process_frame
	var popup = settings.get("popup")
	if not popup is PopupPanel:
		_fail("Settings popup missing", 8)
		return
	var panel_style := (popup as PopupPanel).get_theme_stylebox("panel")
	if not panel_style is StyleBoxFlat:
		_fail("Settings panel does not have opaque StyleBoxFlat", 9)
		return
	if (panel_style as StyleBoxFlat).bg_color.a < 0.99:
		_fail("Settings panel is still transparent", 10)
		return

	var theme_text := FileAccess.get_file_as_string("res://scripts/desktop_visual_theme.gd")
	if theme_text.contains("aurora_button_user.jpg") or theme_text.contains("const FOX_IMAGE: Texture2D = preload(\"res://assets/ui/aurora_fox_user.jpg\")"):
		_fail("Corrupted legacy JPG assets are still active in desktop theme", 11)
		return

	main.queue_free()
	await process_frame
	print("AURORA_WORK_MODE_SMOKE_OK")
	quit(0)
