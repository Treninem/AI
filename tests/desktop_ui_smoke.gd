extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _run() -> void:
	for asset in [
		"res://assets/ui/aurora_background_final.svg",
		"res://assets/ui/fox_logo.svg"
	]:
		var resource = load(asset)
		if resource == null:
			_fail("Safe AuroraFox visual asset cannot be loaded: " + asset, 2)
			return

	# Regression for the striped/stretched UI seen in V1.1.0.0.
	for forbidden_asset in [
		"res://assets/ui/aurora_fox_user.jpg",
		"res://assets/ui/aurora_button_user.jpg"
	]:
		if FileAccess.file_exists(forbidden_asset):
			_fail("Corrupted legacy UI asset must not be packaged: " + forbidden_asset, 3)
			return

	var theme_script = load("res://scripts/desktop_visual_theme.gd")
	var startup_script = load("res://scripts/windows_startup_coordinator.gd")
	if theme_script == null or not theme_script.can_instantiate():
		_fail("Desktop visual theme cannot be instantiated", 4)
		return
	if startup_script == null or not startup_script.can_instantiate():
		_fail("Windows startup coordinator cannot be instantiated", 5)
		return

	var scene_text := FileAccess.get_file_as_string("res://main.tscn")
	for node_name in [
		"DesktopVisualTheme", "SettingsVisualFix", "WindowsStartupCoordinator",
		"ApiAgentBridge", "ApiGatewayManager", "ApiSettings", "WorkManager", "WorkOverlay"
	]:
		if not scene_text.contains(node_name):
			_fail("main.tscn is missing integrated node: " + node_name, 6)
			return

	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded", 7)
		return
	var main := packed.instantiate()
	root.add_child(main)
	root.content_scale_size = Vector2i(960, 640)

	# Voice UI is deferred by one frame; Computer Agent intentionally waits 0.7s.
	await create_timer(1.0).timeout

	var required := [
		"RootLayout", "Sidebar", "SidebarMobileNavSlot", "NewChatButton", "ChatSearch", "ChatHistoryScroll", "ChatList",
		"MainPanel", "HeaderPanel", "HeaderMargin", "MobileNavSlot", "MainHeaderActions", "AvatarSlot", "MessageScroll", "MessageList", "MessagesMargin", "ComposerMargin",
		"MessageInput", "AttachmentBar", "AttachButton", "VoiceDock", "SendButton", "ComposerHint", "SettingsButton",
		"VoiceMicButton", "VoiceSpeakButton", "VoiceSettingsButton", "ComputerAgentButton", "ComputerAgentToggle", "ComputerAgentAuto", "ComputerAgentPopup",
		"AuroraFoxSafeAvatar", "WorkButton", "SettingsPopup", "KnowledgeBasePopup", "SelfImprovementPopup"
	]
	for node_name in required:
		if main.find_child(str(node_name), true, false) == null:
			_fail("Desktop UI integration missing node: %s" % node_name, 10)
			return

	if main.find_child("AuroraReleaseStatus", true, false) != null or main.find_child("ReleaseStatusOverlay", true, false) != null:
		_fail("Misleading release-progress overlay is still present in production UI", 11)
		return

	var safe_avatar := main.find_child("AuroraFoxSafeAvatar", true, false) as TextureRect
	if safe_avatar == null or safe_avatar.texture == null or not safe_avatar.texture.resource_path.ends_with("fox_logo.svg"):
		_fail("Header does not use the existing AuroraFox fallback artwork", 12)
		return

	var new_chat := main.find_child("NewChatButton", true, false) as Button
	if new_chat == null or not (new_chat.get_theme_stylebox("normal") is StyleBoxFlat):
		_fail("Safe flat button state is not active", 13)
		return
	if new_chat.get_theme_stylebox("normal") is StyleBoxTexture:
		_fail("Shared stretched button texture must not be active before final artwork is supplied", 14)
		return

	var attachment_bar := main.find_child("AttachmentBar", true, false)
	if not attachment_bar is HFlowContainer:
		_fail("Attachment chips must use a wrapping flow container", 15)
		return
	var title := main.find_child("ActiveChatTitle", true, false) as Label
	if title == null or title.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS:
		_fail("Active chat title does not have ellipsis overflow protection", 16)
		return

	var header_actions := main.find_child("MainHeaderActions", true, false) as HBoxContainer
	var computer_open := main.find_child("ComputerAgentButton", true, false) as Button
	var computer_toggle := main.find_child("ComputerAgentToggle", true, false) as CheckButton
	var computer_auto := main.find_child("ComputerAgentAuto", true, false) as CheckButton
	if computer_open == null or computer_open.get_parent() != header_actions:
		_fail("Computer Agent must have exactly one clear header entry point", 17)
		return
	if computer_toggle == null or computer_auto == null or computer_toggle.get_parent() == header_actions or computer_auto.get_parent() == header_actions:
		_fail("Detailed Computer Agent toggles must stay inside its panel, not crowd the header", 18)
		return
	if computer_auto.text == "Авто":
		_fail("Ambiguous Computer Agent 'Авто' control is still present", 19)
		return

	var work_button := main.find_child("WorkButton", true, false) as Button
	if work_button == null or work_button.text != "Работа":
		_fail("Work entry must use consistent Russian wording", 20)
		return

	for node in main.find_children("*", "Button", true, false):
		var button := node as Button
		var normalized := button.text.to_lower()
		if normalized.contains("локальные модели") or normalized.contains("gguf"):
			_fail("Dead model-management button leaked back into normal settings", 21)
			return

	var sidebar := main.find_child("Sidebar", true, false) as Control
	var panel := main.find_child("MainPanel", true, false) as Control
	var composer := main.find_child("ComposerMargin", true, false) as Control
	if sidebar == null or panel == null or composer == null or header_actions == null:
		_fail("Responsive layout nodes missing", 22)
		return

	for target_size in [Vector2i(960, 640), Vector2i(1180, 720), Vector2i(1440, 900)]:
		root.content_scale_size = target_size
		await process_frame
		await process_frame
		var viewport_size := main.get_viewport().get_visible_rect().size
		if target_size.x == 960 and sidebar.custom_minimum_size.x > 240.0:
			_fail("Compact sidebar remained too wide at 960px", 23)
			return
		if composer.position.y + composer.size.y > viewport_size.y + 2.0:
			_fail("Composer exceeds viewport at %s" % str(target_size), 24)
			return
		if header_actions.position.x + header_actions.size.x > panel.size.x + 2.0:
			_fail("Header actions exceed main panel width at %s" % str(target_size), 25)
			return
		if panel.size.x < 1.0 or composer.size.x < 1.0:
			_fail("Main responsive region collapsed at %s" % str(target_size), 26)
			return

	var store = main.get("chats")
	if not store is ChatStore:
		_fail("Main UI is not connected to ChatStore", 27)
		return
	var before: String = str(store.active_chat_id)
	main.call("_new_chat")
	await process_frame
	if store.active_chat_id.is_empty() or store.active_chat_id == before:
		_fail("New chat button path did not create/activate a new chat", 28)
		return
	store.rename_chat(store.active_chat_id, "Очень длинное название чата для проверки безопасного поведения заголовка AuroraFox без наложения кнопок")
	main.call("_render_active_chat")
	await process_frame
	if header_actions.position.x + header_actions.size.x > panel.size.x + 2.0:
		_fail("Long chat title pushes header actions outside the panel", 29)
		return
	store.rename_chat(store.active_chat_id, "UI smoke chat")
	if str(store.get_active_chat().get("title", "")) != "UI smoke chat":
		_fail("Chat rename path failed", 30)
		return

	main.queue_free()
	await process_frame
	print("AURORA_DESKTOP_UI_SMOKE_OK")
	quit(0)
