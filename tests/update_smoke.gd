extends SceneTree

func _init() -> void:
	var updater := AuroraUpdateManager.new()
	if updater == null:
		push_error("AuroraUpdateManager failed to instantiate")
		quit(2)
		return

	if updater._compare_versions("0.4.1", "0.4.0") != 1:
		push_error("Updater failed newer-version comparison")
		quit(3)
		return
	if updater._compare_versions("v0.4.0", "0.4.0") != 0:
		push_error("Updater failed equal-version comparison")
		quit(4)
		return
	if updater._compare_versions("0.3.99", "0.4.0") != -1:
		push_error("Updater failed older-version comparison")
		quit(5)
		return

	var file := FileAccess.open("res://update/manifest.template.json", FileAccess.READ)
	if file == null:
		push_error("Update manifest template is missing")
		quit(6)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Update manifest template is invalid JSON")
		quit(7)
		return
	var assets = parsed.get("assets", {})
	if not assets is Dictionary or not assets.has("windows") or not assets.has("android"):
		push_error("Update manifest does not define both platform assets")
		quit(8)
		return

	updater.free()
	print("AURORA_UPDATE_GODOT_SMOKE_OK")
	quit(0)
