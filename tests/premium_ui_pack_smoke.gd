extends SceneTree

const MAP_PATH := "res://assets/ui/AuroraFox_UI/ASSET_MAP.json"

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _expect_size(pack: AuroraPremiumAssetPack, path: String, expected: Vector2i, code: int) -> bool:
	var actual := pack.image_size(path)
	if actual != expected:
		_fail("Premium PNG size mismatch %s: %s != %s" % [path, actual, expected], code)
		return false
	return true

func _run() -> void:
	var pack := AuroraPremiumAssetPack.new()
	if not pack.prepare():
		_fail("Premium pack failed: %s" % str(pack.status()), 2)
		return
	if pack.png_count() != 75:
		_fail("Premium pack must contain exactly 75 PNG files, got %d" % pack.png_count(), 3)
		return

	if not _expect_size(pack, "icons/aurorafox_logo.png", Vector2i(256, 256), 4): return
	if not _expect_size(pack, "icons/aurorafox_app_icon.png", Vector2i(512, 512), 5): return
	if not _expect_size(pack, "backgrounds/aurorafox_chat_background.png", Vector2i(1920, 1080), 6): return

	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	if not parsed is Dictionary:
		_fail("ASSET_MAP.json is invalid", 7)
		return
	var buttons: Dictionary = parsed.get("buttons", {})
	if buttons.size() != 18:
		_fail("Expected 18 button groups, got %d" % buttons.size(), 8)
		return

	var state_count := 0
	for kind in buttons.keys():
		var spec: Dictionary = buttons[kind]
		var size: Array = spec.get("size", [])
		if size.size() != 2:
			_fail("Missing exact size for button group %s" % kind, 9)
			return
		var expected := Vector2i(int(size[0]), int(size[1]))
		var states: Dictionary = spec.get("states", {})
		if states.size() != 4:
			_fail("Button group %s does not have four states" % kind, 10)
			return
		var state_textures: Array[Texture2D] = []
		for state in ["normal", "hover", "pressed", "disabled"]:
			var path := str(states.get(state, ""))
			if path.is_empty() or not pack.has(path):
				_fail("Missing premium PNG for %s/%s: %s" % [kind, state, path], 11)
				return
			if not _expect_size(pack, path, expected, 12): return
			var texture := pack.texture(path)
			if texture == null:
				_fail("Cannot decode premium PNG: %s" % path, 13)
				return
			state_textures.append(texture)
			state_count += 1
		# Prevent accidental reuse of one atlas/texture for all visual states.
		for i in range(state_textures.size()):
			for j in range(i + 1, state_textures.size()):
				if state_textures[i] == state_textures[j]:
					_fail("Button states share one texture in group %s" % kind, 14)
					return

	if state_count != 72:
		_fail("Expected 72 button-state PNGs, got %d" % state_count, 15)
		return

	pack.close()
	print("AURORA_PREMIUM_UI_PACK_OK")
	quit(0)
