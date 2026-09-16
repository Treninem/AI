extends SceneTree

const MASTER_AVATAR_PATH := "res://assets/ui/aurorafox_avatar_master.png"
const MASTER_BACKGROUND_PATH := "res://assets/ui/aurorafox_background_master.png"

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _tree_contains_texture(node: Node, suffix: String, visible_only := false) -> bool:
	if node is TextureRect:
		var rect := node as TextureRect
		if rect.texture != null and rect.texture.resource_path.ends_with(suffix):
			if not visible_only or rect.is_visible_in_tree():
				return true
	for child in node.get_children():
		if _tree_contains_texture(child, suffix, visible_only):
			return true
	return false

func _background_master_path(rect: TextureRect) -> String:
	if rect.texture is AtlasTexture:
		var atlas := rect.texture as AtlasTexture
		return atlas.atlas.resource_path if atlas.atlas != null else ""
	return rect.texture.resource_path if rect.texture != null else ""

func _assert_owner_surface(main: Control, mobile := false) -> bool:
	var avatar := main.find_child("OwnerAvatar", true, false) as TextureRect
	var background := main.find_child("OwnerBackground", true, false) as TextureRect
	var brand_row := main.find_child("BrandRow", true, false) as HBoxContainer
	var avatar_slot := main.find_child("AvatarSlot", true, false) as Control
	if avatar == null or background == null or brand_row == null:
		_fail("Owner-approved AuroraFox art is missing from the UI tree", 10)
		return false
	if avatar.texture == null or avatar.texture.resource_path != MASTER_AVATAR_PATH:
		_fail("Brand avatar is not using the canonical owner master asset", 11)
		return false
	if _background_master_path(background) != MASTER_BACKGROUND_PATH:
		_fail("Application background is not using the canonical owner master asset", 12)
		return false
	if not background.texture is AtlasTexture:
		_fail("Owner background must use focal AtlasTexture cropping", 13)
		return false
	if not background.modulate.is_equal_approx(Color(1, 1, 1, 1)):
		_fail("Owner background must render with neutral modulate; owner pixels may not be dimmed or tinted", 14)
		return false
	var atlas := background.texture as AtlasTexture
	var viewport := main.get_viewport().get_visible_rect().size
	if viewport.x >= viewport.y and atlas.region.position.y <= 0.0:
		_fail("Wide owner background is not bottom-biased; fox/paws may be cropped", 15)
		return false
	if viewport.y > viewport.x and atlas.region.position.x <= 0.0:
		_fail("Portrait owner background is not right-biased; fox may be cropped", 16)
		return false
	if not brand_row.is_ancestor_of(avatar):
		_fail("Owner avatar must stay in the AuroraFox brand row", 17)
		return false
	if avatar.custom_minimum_size.x < 44.0 or avatar.custom_minimum_size.y < 44.0:
		_fail("Owner avatar is too small for a clear brand mark", 18)
		return false
	if avatar_slot == null or avatar_slot.visible or avatar_slot.custom_minimum_size.x > 1.0:
		_fail("Header avatar slot must remain empty to avoid duplicate owner artwork", 19)
		return false
	if _tree_contains_texture(main, "fox_logo.svg", true):
		_fail("Legacy placeholder fox is visible together with owner artwork", 20)
		return false
	if not mobile and not avatar.is_visible_in_tree():
		_fail("Owner avatar is not visible in the desktop brand surface", 21)
		return false
	return true

func _assert_messages_stay_clean(main: Control) -> bool:
	var store = main.get("chats")
	if not store is ChatStore:
		_fail("ChatStore is unavailable for owner-art regression", 22)
		return false
	main.call("_new_chat")
	await process_frame
	store.add_message("assistant", "Owner-art regression: сообщения не должны дублировать аватар.")
	main.call("_render_active_chat")
	await process_frame
	await process_frame
	var messages := main.find_child("MessageList", true, false)
	if messages == null:
		_fail("MessageList is missing", 23)
		return false
	if _tree_contains_texture(messages, "aurorafox_avatar_master.png", false):
		_fail("Owner avatar was duplicated beside an assistant message", 24)
		return false
	if _tree_contains_texture(messages, "fox_logo.svg", false):
		_fail("Legacy placeholder fox remained in a message row", 25)
		return false
	return true

func _run_scene(packed: PackedScene, mobile: bool) -> bool:
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", mobile)
	root.content_scale_size = Vector2i(720, 1280) if mobile else Vector2i(1440, 900)
	var main := packed.instantiate() as Control
	root.add_child(main)
	await create_timer(1.1).timeout
	if not _assert_owner_surface(main, mobile):
		return false
	if not await _assert_messages_stay_clean(main):
		return false
	main.queue_free()
	await process_frame
	return true

func _run() -> void:
	for path in [MASTER_AVATAR_PATH, MASTER_BACKGROUND_PATH]:
		if not FileAccess.file_exists(path):
			_fail("Required owner artwork is missing: " + path, 2)
			return
		if load(path) == null:
			_fail("Canonical owner artwork cannot be loaded by Godot: " + path, 3)
			return
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded", 4)
		return
	if not await _run_scene(packed, false):
		return
	if not await _run_scene(packed, true):
		return
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", false)
	print("AURORA_OWNER_ART_UI_SMOKE_OK")
	quit(0)
