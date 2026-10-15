extends SceneTree

const DesktopVisualTheme = preload("res://scripts/desktop_visual_theme.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", false)
	root.min_size = Vector2i(1, 1)
	root.size = Vector2i(960, 640)
	root.content_scale_size = Vector2i(1440, 900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

	var host := Control.new()
	root.add_child(host)
	var theme := DesktopVisualTheme.new()
	host.add_child(theme)
	await process_frame

	if root.content_scale_mode != Window.CONTENT_SCALE_MODE_DISABLED:
		push_error("Desktop content still shrinks with the window")
		quit(1)
		return
	if root.min_size != Vector2i(960, 640):
		push_error("Desktop minimum usable window changed")
		quit(2)
		return
	for size in [Vector2i(960, 640), Vector2i(1440, 900), Vector2i(1920, 1032)]:
		root.size = size
		await process_frame
		var scale := root.get_stretch_transform().get_scale()
		if not scale.is_equal_approx(Vector2.ONE):
			push_error("Desktop content scale changed at %s: %s" % [size, scale])
			quit(3)
			return

	print("AURORA_WINDOWS_UI_SCALING_OK")
	quit(0)
