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
		"ComputerAgentAuto"
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

	var store = main.get("chats")
	if not store is ChatStore:
		_fail("Main UI is not connected to ChatStore", 14)
		return
	var before := store.active_chat_id
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
