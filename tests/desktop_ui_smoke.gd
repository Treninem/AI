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

	# Voice UI is deferred by one frame; Computer Agent intentionally waits 0.7s.
	await create_timer(1.0).timeout

	var required := [
		"RootLayout",
		"Sidebar",
		"NewChatButton",
		"ChatSearch",
		"ChatHistoryScroll",
		"ChatList",
		"MainPanel",
		"MainHeaderActions",
		"AvatarSlot",
		"MessageScroll",
		"MessageList",
		"ComposerMargin",
		"MessageInput",
		"AttachmentBar",
		"AttachButton",
		"VoiceDock",
		"SendButton",
		"SettingsButton",
		"VoiceMicButton",
		"VoiceSpeakButton",
		"VoiceSettingsButton",
		"ComputerAgentToggle",
		"ComputerAgentAuto",
		"DesktopVisualTheme"
	]
	for node_name in required:
		if main.find_child(str(node_name), true, false) == null:
			_fail("Desktop UI integration missing node: %s" % node_name, 10)
			return

	if main.find_child("AuroraReleaseStatus", true, false) != null or main.find_child("ReleaseStatusOverlay", true, false) != null:
		_fail("Misleading release-progress overlay is still present in production UI", 11)
		return

	for button_name in ["NewChatButton", "SettingsButton", "AttachButton", "SendButton", "VoiceMicButton", "VoiceSpeakButton", "VoiceSettingsButton", "ComputerAgentToggle"]:
		var button := main.find_child(button_name, true, false) as Button
		if button == null or button.icon == null:
			_fail("Desktop button has no real icon: %s" % button_name, 12)
			return

	var forbidden_text := ["◈", "＋", "➤", "✎", "×"]
	for node in main.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null:
			continue
		for marker in forbidden_text:
			if button.text == marker:
				_fail("Temporary text-glyph button remains: %s" % marker, 13)
				return

	# User-provided visual assets must replace the temporary SVG placeholders.
	for node in main.find_children("*", "TextureRect", true, false):
		var view := node as TextureRect
		if view == null or view.texture == null:
			continue
		var path := view.texture.resource_path.to_lower()
		if path.ends_with("aurora_background.svg") or path.ends_with("fox_logo.svg"):
			_fail("Temporary AuroraFox SVG placeholder remains visible: %s" % path, 19)
			return

	var new_chat := main.find_child("NewChatButton", true, false) as Button
	if new_chat == null or not new_chat.get_theme_stylebox("normal") is StyleBoxTexture:
		_fail("New Chat does not use the AuroraFox textured button surface", 20)
		return
	var settings_button := main.find_child("SettingsButton", true, false) as Button
	if settings_button == null or not settings_button.get_theme_stylebox("normal") is StyleBoxTexture:
		_fail("Settings does not use the AuroraFox textured button surface", 21)
		return

	# Force the smallest supported desktop layout and verify the major regions remain inside it.
	root.size = Vector2i(960, 640)
	await create_timer(0.12).timeout
	var root_layout := main.find_child("RootLayout", true, false) as Control
	var sidebar := main.find_child("Sidebar", true, false) as Control
	var main_panel := main.find_child("MainPanel", true, false) as Control
	var header_actions := main.find_child("MainHeaderActions", true, false) as Control
	var composer := main.find_child("ComposerMargin", true, false) as Control
	if root_layout == null or sidebar == null or main_panel == null or header_actions == null or composer == null:
		_fail("Responsive layout controls are missing", 22)
		return
	if root_layout.get_global_rect().end.x > 961.0 or root_layout.get_global_rect().end.y > 641.0:
		_fail("Root desktop layout overflows the 960x640 minimum window", 23)
		return
	if sidebar.get_global_rect().end.x > main_panel.get_global_rect().position.x + 1.0:
		_fail("Sidebar overlaps the main chat panel", 24)
		return
	if header_actions.get_global_rect().end.x > main_panel.get_global_rect().end.x + 1.0:
		_fail("Header actions overflow the main panel", 25)
		return
	if composer.get_global_rect().end.x > main_panel.get_global_rect().end.x + 1.0 or composer.get_global_rect().end.y > main_panel.get_global_rect().end.y + 1.0:
		_fail("Composer overflows the main panel", 26)
		return

	var store = main.get("chats")
	if not store is ChatStore:
		_fail("Main UI is not connected to ChatStore", 14)
		return
	var before: String = str(store.active_chat_id)
	main.call("_new_chat")
	await process_frame
	if store.active_chat_id.is_empty() or store.active_chat_id == before:
		_fail("New chat button path did not create/activate a new chat", 15)
		return
	store.rename_chat(store.active_chat_id, "UI smoke chat")
	if str(store.get_active_chat().get("title", "")) != "UI smoke chat":
		_fail("Chat rename path failed", 16)
		return
	if store.search("UI smoke").is_empty():
		_fail("Chat search path failed", 17)
		return

	var input := main.find_child("MessageInput", true, false) as TextEdit
	if input == null or not input.editable:
		_fail("Message input is not interactive", 18)
		return

	main.queue_free()
	await process_frame
	print("AURORA_DESKTOP_UI_SMOKE_OK")
	quit(0)
