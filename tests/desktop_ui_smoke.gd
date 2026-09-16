extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _visible_placeholder_fox(node: Node) -> bool:
	if node is TextureRect:
		var rect := node as TextureRect
		if rect.texture != null and rect.texture.resource_path.ends_with("fox_logo.svg") and rect.is_visible_in_tree():
			return true
	for child in node.get_children():
		if _visible_placeholder_fox(child):
			return true
	return false

func _assert_core_layout(main: Control, mobile := false) -> bool:
	var required := [
		"RootLayout", "Sidebar", "SidebarMobileNavSlot", "NewChatButton", "ChatSearch", "ChatHistoryScroll", "ChatList",
		"MainPanel", "HeaderPanel", "HeaderMargin", "MobileNavSlot", "MainHeaderActions", "AvatarSlot", "MessageScroll", "MessageList", "MessagesMargin", "ComposerMargin",
		"MessageInput", "AttachmentBar", "AttachButton", "VoiceDock", "SendButton", "ComposerHint", "SettingsButton",
		"VoiceMicButton", "ComputerAgentToggle", "ComputerAgentAuto", "ComputerAgentPopup",
		"SettingsPopup", "SettingsPages", "SettingsNav_general", "SettingsNav_voice", "SettingsNav_files", "SettingsNav_autonomy", "SettingsNav_tools", "SettingsNav_updates",
		"KnowledgeBasePopup", "SelfImprovementPopup"
	]
	for node_name in required:
		if main.find_child(str(node_name), true, false) == null:
			_fail("UI integration missing node: %s" % node_name, 20)
			return false

	if main.find_child("ComputerAgentButton", true, false) != null:
		_fail("Computer Agent leaked back into the chat header", 21)
		return false
	if main.find_child("UpdateStatusButton", true, false) != null:
		_fail("Floating/header update control leaked back into the chat surface", 22)
		return false
	if _visible_placeholder_fox(main):
		_fail("Temporary fox/cat placeholder artwork is visible in production UI", 23)
		return false

	var avatar_slot := main.find_child("AvatarSlot", true, false) as Control
	if avatar_slot == null or avatar_slot.visible or avatar_slot.custom_minimum_size.x > 1.0:
		_fail("Avatar placeholder slot must stay hidden until owner artwork is supplied", 24)
		return false

	if main.find_child("VoiceSpeakButton", true, false) != null or main.find_child("VoiceSettingsButton", true, false) != null or main.find_child("VoiceSettingsPopup", true, false) != null:
		_fail("Redundant voice quick controls or separate voice settings leaked back into composer", 25)
		return false
	var mic := main.find_child("VoiceMicButton", true, false) as Button
	if mic == null or not mic.visible:
		_fail("Primary microphone action is missing from composer", 26)
		return false

	var attachment_bar := main.find_child("AttachmentBar", true, false)
	if not attachment_bar is HFlowContainer:
		_fail("Attachment chips must wrap instead of overflowing horizontally", 27)
		return false
	var title := main.find_child("ActiveChatTitle", true, false) as Label
	if title == null or title.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS:
		_fail("Chat title does not have ellipsis overflow protection", 28)
		return false

	var settings_pages := main.find_child("SettingsPages", true, false) as TabContainer
	if settings_pages == null or settings_pages.tabs_visible or settings_pages.get_child_count() < 6:
		_fail("Settings must be category pages, not one long scrolling ribbon", 29)
		return false
	var settings_overlay := main.get_node_or_null("SettingsOverlay") as AuroraSettingsOverlay
	if settings_overlay == null:
		_fail("Settings controller missing", 30)
		return false
	settings_overlay.call("_select_page", "voice")
	if settings_pages.current_tab != int(settings_overlay.nav_indices.get("voice", -1)):
		_fail("Settings navigation does not switch pages", 31)
		return false
	settings_overlay.call("_select_page", "general")

	var computer_toggle := main.find_child("ComputerAgentToggle", true, false) as CheckButton
	var computer_auto := main.find_child("ComputerAgentAuto", true, false) as CheckButton
	var computer_popup := main.find_child("ComputerAgentPopup", true, false) as PopupPanel
	if computer_toggle == null or computer_auto == null or computer_popup == null:
		_fail("Computer Agent settings panel is incomplete", 32)
		return false
	if not computer_popup.is_ancestor_of(computer_toggle) or not computer_popup.is_ancestor_of(computer_auto):
		_fail("Computer Agent toggles must live inside their settings panel", 33)
		return false
	if computer_auto.text.strip_edges().length() < 20:
		_fail("Computer Agent automatic mode label is ambiguous", 34)
		return false

	for node in main.find_children("*", "Button", true, false):
		var button := node as Button
		var normalized := button.text.to_lower()
		if normalized.contains("локальные модели") or normalized.contains("gguf"):
			_fail("Dead model-management button leaked into normal UI", 35)
			return false

	if mobile:
		var mobile_nav := main.find_child("SettingsMobileNavigation", true, false)
		if mobile_nav == null:
			_fail("Mobile settings do not expose compact category navigation", 36)
			return false
		var sidebar := main.find_child("Sidebar", true, false) as Control
		var panel := main.find_child("MainPanel", true, false) as Control
		var menu := main.find_child("MobileMenuButton", true, false) as Button
		var header_actions := main.find_child("MainHeaderActions", true, false) as Control
		if sidebar == null or panel == null or sidebar.visible or not panel.visible or menu == null or not menu.visible:
			_fail("Mobile chat/sidebar navigation state is incorrect", 37)
			return false
		if header_actions != null and header_actions.visible:
			_fail("Mobile header still contains unrelated action clutter", 38)
			return false
	return true

func _exercise_chat(main: Control) -> bool:
	var store = main.get("chats")
	if not store is ChatStore:
		_fail("Main UI is not connected to ChatStore", 50)
		return false
	var before: String = str(store.active_chat_id)
	main.call("_new_chat")
	await process_frame
	if store.active_chat_id.is_empty() or store.active_chat_id == before:
		_fail("New chat action did not create/activate a chat", 51)
		return false
	store.add_message("user", "Проверка ровной пользовательской карточки")
	store.add_message("assistant", "Проверка ответа AuroraFox без временной картинки рядом с сообщением.")
	store.rename_chat(store.active_chat_id, "Очень длинное название чата для проверки безопасного поведения заголовка AuroraFox без наложений")
	main.call("_render_active_chat")
	await process_frame
	await process_frame
	if _visible_placeholder_fox(main):
		_fail("Assistant message rendered temporary avatar artwork", 52)
		return false
	store.rename_chat(store.active_chat_id, "UI smoke chat")
	return str(store.get_active_chat().get("title", "")) == "UI smoke chat"

func _run_desktop(packed: PackedScene) -> bool:
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", false)
	root.content_scale_size = Vector2i(960, 640)
	var main := packed.instantiate() as Control
	root.add_child(main)
	await create_timer(1.1).timeout
	if not _assert_core_layout(main, false):
		return false

	var new_chat := main.find_child("NewChatButton", true, false) as Button
	if new_chat == null or not (new_chat.get_theme_stylebox("normal") is StyleBoxFlat) or new_chat.get_theme_stylebox("normal") is StyleBoxTexture:
		_fail("Desktop buttons are not using safe rounded flat states", 60)
		return false

	var sidebar := main.find_child("Sidebar", true, false) as Control
	var panel := main.find_child("MainPanel", true, false) as Control
	var composer := main.find_child("ComposerMargin", true, false) as Control
	var header_actions := main.find_child("MainHeaderActions", true, false) as Control
	for target_size in [Vector2i(960, 640), Vector2i(1180, 720), Vector2i(1440, 900)]:
		root.content_scale_size = target_size
		await process_frame
		await process_frame
		var viewport_size := main.get_viewport().get_visible_rect().size
		if target_size.x == 960 and sidebar.custom_minimum_size.x > 240.0:
			_fail("Compact sidebar remained too wide at 960px", 61)
			return false
		if composer.position.y + composer.size.y > viewport_size.y + 2.0:
			_fail("Composer exceeds desktop viewport at %s" % str(target_size), 62)
			return false
		if panel.size.x < 1.0 or composer.size.x < 1.0:
			_fail("Main desktop region collapsed at %s" % str(target_size), 63)
			return false
		if header_actions != null and header_actions.visible:
			_fail("Empty desktop header actions container should not consume space", 64)
			return false

	if not await _exercise_chat(main):
		_fail("Desktop chat behavior regression", 65)
		return false
	main.queue_free()
	await process_frame
	return true

func _run_mobile_preview(packed: PackedScene) -> bool:
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", true)
	root.content_scale_size = Vector2i(720, 1280)
	var main := packed.instantiate() as Control
	root.add_child(main)
	await create_timer(1.1).timeout
	if not _assert_core_layout(main, true):
		return false

	var composer := main.find_child("ComposerMargin", true, false) as Control
	var input := main.find_child("MessageInput", true, false) as TextEdit
	var viewport_size := main.get_viewport().get_visible_rect().size
	if composer == null or input == null:
		_fail("Mobile composer controls missing", 70)
		return false
	if composer.position.y + composer.size.y > viewport_size.y + 2.0:
		_fail("Mobile composer exceeds portrait viewport", 71)
		return false
	if input.custom_minimum_size.y > 90.0:
		_fail("Mobile composer input is unnecessarily tall", 72)
		return false
	if not await _exercise_chat(main):
		_fail("Mobile chat behavior regression", 73)
		return false

	var settings := main.get_node_or_null("SettingsOverlay") as AuroraSettingsOverlay
	settings.call("_fit_popup")
	var settings_popup := main.find_child("SettingsPopup", true, false) as PopupPanel
	if settings_popup == null or settings_popup.size.x > int(viewport_size.x) or settings_popup.size.y > int(viewport_size.y):
		_fail("Mobile settings popup exceeds portrait viewport", 74)
		return false

	main.queue_free()
	await process_frame
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", false)
	return true

func _run() -> void:
	for asset in ["res://assets/ui/aurora_background_final.svg"]:
		if load(asset) == null:
			_fail("AuroraFox background asset cannot be loaded: " + asset, 2)
			return
	for forbidden_asset in ["res://assets/ui/aurora_fox_user.jpg", "res://assets/ui/aurora_button_user.jpg"]:
		if FileAccess.file_exists(forbidden_asset):
			_fail("Corrupted legacy UI asset must not be packaged: " + forbidden_asset, 3)
			return

	var scene_text := FileAccess.get_file_as_string("res://main.tscn")
	for node_name in ["DesktopVisualTheme", "SettingsVisualFix", "WindowsStartupCoordinator", "ApiAgentBridge", "ApiGatewayManager", "ApiSettings", "WorkManager", "WorkOverlay"]:
		if not scene_text.contains(node_name):
			_fail("main.tscn is missing integrated node: " + node_name, 4)
			return

	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded", 5)
		return
	if not await _run_desktop(packed):
		return
	if not await _run_mobile_preview(packed):
		return
	print("AURORA_DESKTOP_AND_MOBILE_UI_SMOKE_OK")
	quit(0)
