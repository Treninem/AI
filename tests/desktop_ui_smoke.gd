extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _run() -> void:
	for asset in [
		"res://assets/ui/aurora_background_final.svg",
		"res://assets/ui/aurora_fox_user.jpg",
		"res://assets/ui/aurora_button_user.jpg"
	]:
		var resource = load(asset)
		if resource == null:
			_fail("Final AuroraFox visual asset cannot be loaded: " + asset, 2)
			return

	var theme_script = load("res://scripts/desktop_visual_theme.gd")
	var startup_script = load("res://scripts/windows_startup_coordinator.gd")
	if theme_script == null or not theme_script.can_instantiate():
		_fail("Desktop visual theme cannot be instantiated", 3)
		return
	if startup_script == null or not startup_script.can_instantiate():
		_fail("Windows startup coordinator cannot be instantiated", 4)
		return

	var scene_text := FileAccess.get_file_as_string("res://main.tscn")
	for node_name in ["DesktopVisualTheme", "WindowsStartupCoordinator", "ApiAgentBridge", "ApiGatewayManager", "ApiSettings"]:
		if not scene_text.contains(node_name):
			_fail("main.tscn is missing integrated node: " + node_name, 5)
			return

	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded", 6)
		return
	var main := packed.instantiate()
	root.add_child(main)
	root.content_scale_size = Vector2i(960, 640)

	# Voice UI is deferred by one frame; Computer Agent intentionally waits 0.7s.
	await create_timer(1.0).timeout

	var required := [
		"RootLayout", "Sidebar", "NewChatButton", "ChatSearch", "ChatHistoryScroll", "ChatList",
		"MainPanel", "MainHeaderActions", "AvatarSlot", "MessageScroll", "MessageList", "ComposerMargin",
		"MessageInput", "AttachmentBar", "AttachButton", "VoiceDock", "SendButton", "SettingsButton",
		"VoiceMicButton", "VoiceSpeakButton", "VoiceSettingsButton", "ComputerAgentToggle", "ComputerAgentAuto",
		"AuroraFoxRealAvatar"
	]
	for node_name in required:
		if main.find_child(str(node_name), true, false) == null:
			_fail("Desktop UI integration missing node: %s" % node_name, 10)
			return

	if main.find_child("AuroraReleaseStatus", true, false) != null or main.find_child("ReleaseStatusOverlay", true, false) != null:
		_fail("Misleading release-progress overlay is still present in production UI", 11)
		return

	var real_avatar := main.find_child("AuroraFoxRealAvatar", true, false) as TextureRect
	if real_avatar == null or real_avatar.texture == null or not real_avatar.texture.resource_path.ends_with("aurora_fox_user.jpg"):
		_fail("Header does not use AuroraFox fox artwork", 12)
		return

	var new_chat := main.find_child("NewChatButton", true, false) as Button
	if new_chat == null or not (new_chat.get_theme_stylebox("normal") is StyleBoxTexture):
		_fail("AuroraFox button texture is not active", 13)
		return

	var sidebar := main.find_child("Sidebar", true, false) as Control
	var panel := main.find_child("MainPanel", true, false) as Control
	var composer := main.find_child("ComposerMargin", true, false) as Control
	var header_actions := main.find_child("MainHeaderActions", true, false) as Control
	if sidebar == null or panel == null or composer == null or header_actions == null:
		_fail("Responsive layout nodes missing", 14)
		return
	if sidebar.custom_minimum_size.x > 240.0:
		_fail("Compact sidebar remained too wide at 960px", 15)
		return
	if composer.position.y + composer.size.y > root.size.y + 2.0:
		_fail("Composer exceeds compact viewport", 16)
		return
	if header_actions.position.x + header_actions.size.x > panel.size.x + 2.0:
		_fail("Header actions exceed main panel width", 17)
		return

	var store = main.get("chats")
	if not store is ChatStore:
		_fail("Main UI is not connected to ChatStore", 18)
		return
	var before: String = str(store.active_chat_id)
	main.call("_new_chat")
	await process_frame
	if store.active_chat_id.is_empty() or store.active_chat_id == before:
		_fail("New chat button path did not create/activate a new chat", 19)
		return
	store.rename_chat(store.active_chat_id, "UI smoke chat")
	if str(store.get_active_chat().get("title", "")) != "UI smoke chat":
		_fail("Chat rename path failed", 20)
		return

	main.queue_free()
	await process_frame
	print("AURORA_DESKTOP_UI_SMOKE_OK")
	quit(0)
