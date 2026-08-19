extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _texture_size_from_style(button: Button, state: String) -> Vector2i:
	var style := button.get_theme_stylebox(state)
	if not style is StyleBoxTexture:
		return Vector2i.ZERO
	var texture := (style as StyleBoxTexture).texture
	if texture == null:
		return Vector2i.ZERO
	return Vector2i(texture.get_width(), texture.get_height())

func _has_texture_size(node: Node, wanted: Vector2i) -> bool:
	for child in node.get_children():
		if child is TextureRect:
			var rect := child as TextureRect
			if rect.texture != null and Vector2i(rect.texture.get_width(), rect.texture.get_height()) == wanted:
				return true
		if _has_texture_size(child, wanted):
			return true
	return false

func _run() -> void:
	for asset in ["res://assets/ui/aurora_background_final.svg", "res://assets/ui/fox_logo.svg"]:
		if load(asset) == null:
			_fail("Safe AuroraFox fallback cannot be loaded: " + asset, 2)
			return

	for forbidden_asset in ["res://assets/ui/aurora_fox_user.jpg", "res://assets/ui/aurora_button_user.jpg"]:
		if FileAccess.file_exists(forbidden_asset):
			_fail("Corrupted legacy UI asset must not be packaged: " + forbidden_asset, 3)
			return

	var scene_text := FileAccess.get_file_as_string("res://main.tscn")
	for node_name in [
		"PremiumUITheme", "DesktopVisualTheme", "SettingsVisualFix", "WindowsStartupCoordinator",
		"ApiAgentBridge", "ApiGatewayManager", "ApiSettings", "WorkManager", "WorkOverlay"
	]:
		if not scene_text.contains(node_name):
			_fail("main.tscn is missing integrated node: " + node_name, 4)
			return

	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded", 5)
		return

	# First validate the exact premium artwork at the normal desktop target size.
	root.content_scale_size = Vector2i(1440, 900)
	var main := packed.instantiate()
	root.add_child(main)
	await create_timer(1.25).timeout

	var required := [
		"RootLayout", "Sidebar", "NewChatButton", "ChatSearch", "ChatHistoryScroll", "ChatList",
		"MainPanel", "MainHeaderActions", "AvatarSlot", "MessageScroll", "MessageList", "ComposerMargin",
		"MessageInput", "AttachmentBar", "AttachButton", "VoiceDock", "SendButton", "SettingsButton",
		"VoiceMicButton", "VoiceSpeakButton", "VoiceSettingsButton", "ComputerAgentToggle", "ComputerAgentAuto",
		"AuroraFoxPremiumAvatar", "WorkButton", "PremiumUITheme"
	]
	for node_name in required:
		if main.find_child(str(node_name), true, false) == null:
			_fail("Desktop UI integration missing node: %s" % node_name, 10)
			return

	var premium_theme := main.find_child("PremiumUITheme", true, false)
	var premium_status: Dictionary = premium_theme.call("status")
	if not bool(premium_status.get("premium_ready", false)) or int(premium_status.get("png_count", 0)) != 75:
		_fail("Premium UI pack is not active: %s" % premium_status, 11)
		return

	var premium_avatar := main.find_child("AuroraFoxPremiumAvatar", true, false) as TextureRect
	if premium_avatar == null or not premium_avatar.visible or premium_avatar.texture == null:
		_fail("Premium AuroraFox avatar is not visible", 12)
		return
	if Vector2i(premium_avatar.texture.get_width(), premium_avatar.texture.get_height()) != Vector2i(256, 256):
		_fail("Premium avatar does not use the 256x256 source artwork", 13)
		return
	if not _has_texture_size(main, Vector2i(1920, 1080)):
		_fail("1920x1080 AuroraFox chat background is not active", 14)
		return

	var exact_buttons := {
		"NewChatButton": Vector2i(254, 48),
		"SettingsButton": Vector2i(254, 48),
		"AttachButton": Vector2i(44, 44),
		"SendButton": Vector2i(52, 52),
		"VoiceMicButton": Vector2i(44, 44),
		"VoiceSpeakButton": Vector2i(44, 44),
		"VoiceSettingsButton": Vector2i(44, 44),
		"ComputerAgentToggle": Vector2i(108, 44),
		"ComputerAgentAuto": Vector2i(72, 44)
	}
	for button_name in exact_buttons.keys():
		var button := main.find_child(str(button_name), true, false) as Button
		if button == null:
			_fail("Premium button missing: %s" % button_name, 15)
			return
		for state in ["normal", "hover", "pressed", "disabled"]:
			var actual := _texture_size_from_style(button, state)
			if actual != exact_buttons[button_name]:
				_fail("%s/%s texture size %s != %s" % [button_name, state, actual, exact_buttons[button_name]], 16)
				return

	# Compact mode must not squeeze the wide source PNGs.
	root.content_scale_size = Vector2i(960, 640)
	await create_timer(0.65).timeout
	var new_chat := main.find_child("NewChatButton", true, false) as Button
	if new_chat == null or new_chat.get_theme_stylebox("normal") is StyleBoxTexture:
		_fail("254px New Chat artwork is being squeezed in compact mode", 17)
		return

	var sidebar := main.find_child("Sidebar", true, false) as Control
	var panel := main.find_child("MainPanel", true, false) as Control
	var composer := main.find_child("ComposerMargin", true, false) as Control
	var header_actions := main.find_child("MainHeaderActions", true, false) as Control
	if sidebar == null or panel == null or composer == null or header_actions == null:
		_fail("Responsive layout nodes missing", 18)
		return
	if sidebar.custom_minimum_size.x > 240.0:
		_fail("Compact sidebar remained too wide at 960px", 19)
		return
	if composer.position.y + composer.size.y > root.size.y + 2.0:
		_fail("Composer exceeds compact viewport", 20)
		return
	if header_actions.position.x + header_actions.size.x > panel.size.x + 2.0:
		_fail("Header actions exceed main panel width", 21)
		return

	if main.find_child("AuroraReleaseStatus", true, false) != null or main.find_child("ReleaseStatusOverlay", true, false) != null:
		_fail("Misleading release-progress overlay is still present", 22)
		return

	var store = main.get("chats")
	if not store is ChatStore:
		_fail("Main UI is not connected to ChatStore", 23)
		return
	var before: String = str(store.active_chat_id)
	main.call("_new_chat")
	await process_frame
	if store.active_chat_id.is_empty() or store.active_chat_id == before:
		_fail("New chat action failed", 24)
		return
	store.rename_chat(store.active_chat_id, "UI smoke chat")
	if str(store.get_active_chat().get("title", "")) != "UI smoke chat":
		_fail("Chat rename path failed", 25)
		return

	main.queue_free()
	await process_frame
	print("AURORA_DESKTOP_UI_SMOKE_OK")
	quit(0)
