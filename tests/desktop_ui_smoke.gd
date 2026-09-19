extends SceneTree

const OWNER_AVATAR_MASTER := "res://assets/ui/aurorafox_avatar_master.png"
const OWNER_BACKGROUND_MASTER := "res://assets/ui/aurorafox_background_master.png"

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

func _assert_personal_surfaces(main: Control) -> bool:
	var api := main.get_node_or_null("ApiSettings") as AuroraApiSettingsOverlay
	if api == null:
		_fail("Personal account transport is missing", 46)
		return false
	for method_name in ["login_personal", "enter_guest", "refresh_personal_session", "logout_personal", "fetch_personal_memories", "delete_personal_memory", "retry_guest_migration"]:
		if not api.has_method(method_name):
			_fail("Personal account transport missing method: %s" % method_name, 47)
			return false
	var state := api.personal_state()
	for secret_key in ["access_token", "refresh_token", "guest_token", "pending_guest_token"]:
		if state.has(secret_key):
			_fail("Personal state leaked secret into UI-facing state: %s" % secret_key, 48)
			return false
	if not api.personal_base_url().begins_with("https://"):
		_fail("Personal sync must default to HTTPS", 49)
		return false
	for node_name in ["PersonalSessionStatus", "PersonalLoginForm", "PersonalEmail", "PersonalPassword", "PersonalLoginButton", "PersonalGuestButton", "PersonalSessionActions", "PersonalMemoryRefreshButton", "PersonalLogoutButton", "PersonalMemoryStatus", "PersonalMemoryList"]:
		if main.find_child(node_name, true, false) == null:
			_fail("Account/memory UI missing node: %s" % node_name, 50)
			return false
	var password := main.find_child("PersonalPassword", true, false) as LineEdit
	if password == null or not password.secret:
		_fail("Personal password field must stay secret", 51)
		return false
	var login := main.find_child("PersonalLoginButton", true, false) as Button
	var guest := main.find_child("PersonalGuestButton", true, false) as Button
	if login == null or guest == null or login.text.strip_edges().is_empty() or guest.text.strip_edges().is_empty():
		_fail("Account/guest entry actions are ambiguous", 52)
		return false
	if login.pressed.get_connections().is_empty() or guest.pressed.get_connections().is_empty():
		_fail("Account/guest buttons are not wired to real actions", 53)
		return false
	return true

func _assert_knowledge_surfaces(main: Control) -> bool:
	var popup := main.find_child("KnowledgeBasePopup", true, false) as PopupPanel
	var close := main.find_child("KnowledgeCloseButton", true, false) as Button
	var cancel := main.find_child("KnowledgeCancelImportButton", true, false) as Button
	var actions := main.find_child("KnowledgeActions", true, false)
	if popup == null or close == null or cancel == null or actions == null:
		_fail("Knowledge responsive controls are incomplete", 54)
		return false
	if close.text != "Готово" or close.custom_minimum_size.y < 40.0:
		_fail("Knowledge close action is not a stable top-level Done control", 55)
		return false
	if not actions is HFlowContainer:
		_fail("Knowledge actions must wrap instead of overflowing", 56)
		return false
	if cancel.text.findn("текущего файла") < 0:
		_fail("Knowledge cancel action overpromises mid-transaction cancellation", 57)
		return false
	for node in popup.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text.strip_edges() == "Закрыть":
			_fail("Legacy bottom Knowledge close button leaked back into the surface", 58)
			return false
	return true

func _assert_owner_art(main: Control, mobile: bool) -> bool:
	var avatar := main.find_child("OwnerAvatar", true, false) as TextureRect
	var background := main.find_child("OwnerBackground", true, false) as TextureRect
	var brand_row := main.find_child("BrandRow", true, false) as HBoxContainer
	var avatar_slot := main.find_child("AvatarSlot", true, false) as Control
	if avatar == null or background == null or brand_row == null:
		_fail("Owner-approved AuroraFox art is missing", 59)
		return false
	if avatar.texture == null or avatar.texture.resource_path != OWNER_AVATAR_MASTER:
		_fail("Owner avatar is not the canonical master asset", 63)
		return false
	if not background.texture is AtlasTexture:
		_fail("Owner background is not using focal AtlasTexture cropping", 64)
		return false
	var atlas := background.texture as AtlasTexture
	if atlas.atlas == null or atlas.atlas.resource_path != OWNER_BACKGROUND_MASTER:
		_fail("Owner background is not sourced from the canonical master asset", 65)
		return false
	if mobile:
		if atlas.region.position.x <= 0.0:
			_fail("Portrait owner background is not right-biased", 66)
			return false
	else:
		if atlas.region.position.y <= 0.0:
			_fail("Wide owner background is not bottom-biased", 67)
			return false
	if not brand_row.is_ancestor_of(avatar):
		_fail("Owner avatar must remain in the brand surface", 68)
		return false
	if avatar_slot == null or avatar_slot.visible or avatar_slot.custom_minimum_size.x > 1.0:
		_fail("Header avatar slot must stay empty to avoid duplicate owner art", 69)
		return false
	if _visible_placeholder_fox(main):
		_fail("Legacy placeholder fox is visible with owner artwork", 76)
		return false
	return true

func _assert_core_layout(main: Control, mobile := false) -> bool:
	var required := [
		"RootLayout", "Sidebar", "SidebarMobileNavSlot", "NewChatButton", "ChatSearch", "ChatHistoryScroll", "ChatList",
		"MainPanel", "HeaderPanel", "HeaderMargin", "MobileNavSlot", "MainHeaderActions", "AvatarSlot", "MessageScroll", "MessageList", "MessagesMargin", "ComposerMargin",
		"MessageInput", "AttachmentBar", "AttachButton", "VoiceDock", "SendButton", "ComposerHint", "SettingsButton",
		"VoiceMicButton", "ComputerAgentToggle", "ComputerAgentAuto", "ComputerAgentPopup",
		"SettingsPopup", "SettingsPages", "SettingsPage_account", "KnowledgeBasePopup", "SelfImprovementPopup"
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
	var work_button := main.find_child("WorkButton", true, false) as Button
	if mobile:
		if work_button != null and work_button.is_visible_in_tree():
			_fail("Desktop Work shortcut is visible on mobile", 23)
			return false
	else:
		if work_button == null or work_button.text.strip_edges() != "Работа" or work_button.pressed.get_connections().is_empty():
			_fail("Desktop Work entry is missing or not wired", 23)
			return false
	if _visible_placeholder_fox(main):
		_fail("Temporary fox/cat placeholder artwork is visible in production UI", 24)
		return false

	var avatar_slot := main.find_child("AvatarSlot", true, false) as Control
	if avatar_slot == null or avatar_slot.visible or avatar_slot.custom_minimum_size.x > 1.0:
		_fail("Header avatar slot must stay empty because owner art belongs to the brand surface", 25)
		return false

	if main.find_child("VoiceSpeakButton", true, false) != null or main.find_child("VoiceSettingsButton", true, false) != null or main.find_child("VoiceSettingsPopup", true, false) != null:
		_fail("Redundant voice quick controls or separate voice settings leaked back into composer", 26)
		return false
	var mic := main.find_child("VoiceMicButton", true, false) as Button
	if mic == null or not mic.visible:
		_fail("Primary microphone action is missing from composer", 27)
		return false

	var attachment_bar := main.find_child("AttachmentBar", true, false)
	if not attachment_bar is HFlowContainer:
		_fail("Attachment chips must wrap instead of overflowing horizontally", 28)
		return false
	var title := main.find_child("ActiveChatTitle", true, false) as Label
	if title == null or title.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS:
		_fail("Chat title does not have ellipsis overflow protection", 29)
		return false

	var settings_pages := main.find_child("SettingsPages", true, false) as TabContainer
	if settings_pages == null or settings_pages.tabs_visible or settings_pages.get_child_count() < 7:
		_fail("Settings must contain seven category pages including account/memory", 30)
		return false
	var settings_overlay := main.get_node_or_null("SettingsOverlay") as AuroraSettingsOverlay
	if settings_overlay == null:
		_fail("Settings controller missing", 31)
		return false
	settings_overlay.call("_select_page", "account")
	if settings_pages.current_tab != int(settings_overlay.nav_indices.get("account", -1)):
		_fail("Account/memory navigation does not switch pages", 32)
		return false
	settings_overlay.call("_select_page", "general")

	if not _assert_personal_surfaces(main):
		return false
	if not _assert_knowledge_surfaces(main):
		return false
	if not _assert_owner_art(main, mobile):
		return false

	var computer_toggle := main.find_child("ComputerAgentToggle", true, false) as CheckButton
	var computer_auto := main.find_child("ComputerAgentAuto", true, false) as CheckButton
	var computer_popup := main.find_child("ComputerAgentPopup", true, false) as PopupPanel
	if computer_toggle == null or computer_auto == null or computer_popup == null:
		_fail("Computer Agent settings panel is incomplete", 33)
		return false
	if not computer_popup.is_ancestor_of(computer_toggle) or not computer_popup.is_ancestor_of(computer_auto):
		_fail("Computer Agent toggles must live inside their settings panel", 34)
		return false
	if computer_auto.text.strip_edges().length() < 20:
		_fail("Computer Agent automatic mode label is ambiguous", 35)
		return false

	for node in main.find_children("*", "Button", true, false):
		var button := node as Button
		var normalized := button.text.to_lower()
		if normalized.contains("локальные модели") or normalized.contains("gguf"):
			_fail("Dead model-management button leaked into normal UI", 36)
			return false

	var nav_names := ["SettingsNav_general", "SettingsNav_voice", "SettingsNav_files", "SettingsNav_autonomy", "SettingsNav_tools", "SettingsNav_updates", "SettingsNav_account"]
	if mobile:
		var selector := main.find_child("SettingsMobileNavigation", true, false) as OptionButton
		if selector == null or selector.item_count != 7:
			_fail("Mobile settings must expose one seven-page category selector", 37)
			return false
		if main.find_child("SettingsMobileNavigationScroll", true, false) != null:
			_fail("Legacy horizontally scrolling settings ribbon leaked back into mobile UI", 38)
			return false
		if selector.custom_minimum_size.y < 44.0 or selector.custom_minimum_size.y > 60.0 or selector.size_flags_horizontal != Control.SIZE_EXPAND_FILL:
			_fail("Mobile settings page selector has unsafe geometry", 39)
			return false
		var expected_keys := ["general", "voice", "files", "autonomy", "tools", "updates", "account"]
		for i in range(selector.item_count):
			if selector.get_item_text(i).strip_edges().is_empty() or str(selector.get_item_metadata(i)) != expected_keys[i]:
				_fail("Mobile settings selector contains an unreadable or mismatched page", 40)
				return false
		for nav_name in nav_names:
			if main.find_child(nav_name, true, false) != null:
				_fail("Desktop settings button leaked into compact mobile selector: %s" % nav_name, 41)
				return false

		var sidebar := main.find_child("Sidebar", true, false) as Control
		var panel := main.find_child("MainPanel", true, false) as Control
		var menu := main.find_child("MobileMenuButton", true, false) as Button
		var header_actions := main.find_child("MainHeaderActions", true, false) as Control
		if sidebar == null or panel == null or sidebar.visible or not panel.visible or menu == null or not menu.visible:
			_fail("Mobile chat/sidebar navigation state is incorrect", 42)
			return false
		if header_actions != null and header_actions.visible:
			_fail("Mobile header still contains unrelated action clutter", 43)
			return false
	else:
		if main.find_child("SettingsMobileNavigation", true, false) != null:
			_fail("Mobile settings selector leaked into desktop navigation", 44)
			return false
		for nav_name in nav_names:
			var nav_button := main.find_child(nav_name, true, false) as Button
			if nav_button == null or nav_button.text.strip_edges().is_empty():
				_fail("Desktop settings category is missing or unreadable: %s" % nav_name, 45)
				return false
	return true

func _exercise_computer_contract(main: Control) -> bool:
	var overlay := main.get_node_or_null("ComputerOverlay")
	var toggle := main.find_child("ComputerAgentToggle", true, false) as CheckButton
	if overlay == null or toggle == null:
		_fail("Computer overlay is missing for routing regression", 77)
		return false
	if bool(overlay.get("enabled")) or toggle.button_pressed:
		_fail("Computer control must be default OFF", 78)
		return false
	toggle.toggled.emit(true)
	await process_frame
	if not bool(overlay.get("enabled")):
		_fail("Computer enable toggle is not wired to overlay permission state", 79)
		return false
	toggle.toggled.emit(false)
	await process_frame
	if bool(overlay.get("enabled")):
		_fail("Computer disable toggle did not revoke overlay permission state", 85)
		return false
	var disabled_result = overlay.call("execute_goal", "UI smoke must not execute while disabled", 1)
	if not disabled_result is Dictionary or bool(disabled_result.get("ok", true)):
		_fail("Disabled Computer mode did not fail closed", 86)
		return false
	var source := FileAccess.get_file_as_string("res://scripts/computer_overlay.gd")
	for forbidden in ["computer.run(", "computer.plan("]:
		if source.contains(forbidden):
			_fail("Computer UI restored forbidden sidecar planning call: " + forbidden, 87)
			return false
	for required in ["core.run_task", "set_computer_control_enabled", "_computer_primitives_ready", "computer_action", "computer_screenshot", "computer_windows", "protected_computer_primitives_unavailable"]:
		if not source.contains(required):
			_fail("Computer UI missing Core-routing/fail-closed contract: " + required, 88)
			return false
	return true

func _exercise_work_header(main: Control) -> bool:
	var overlay := main.get_node_or_null("WorkOverlay")
	if overlay == null:
		_fail("Work overlay is missing", 90)
		return false
	overlay.show_work()
	await process_frame
	await process_frame
	var popup := main.find_child("AuroraWorkPopup", true, false) as PopupPanel
	if popup == null or not popup.visible:
		_fail("Work popup did not open", 91)
		return false
	for action_name in ["WorkNewProjectButton", "WorkCloseButton"]:
		var action := popup.find_child(action_name, true, false) as Button
		if action == null or not action.is_visible_in_tree() or action.text.is_empty():
			_fail("Work header action is missing: " + action_name, 92)
			return false
		var font := action.get_theme_font("font")
		var text_width := font.get_string_size(action.text, HORIZONTAL_ALIGNMENT_LEFT, -1, action.get_theme_font_size("font_size")).x
		if action.clip_text or action.size.x < text_width + 24.0:
			_fail("Work header action label collapsed: " + action_name, 93)
			return false
	popup.hide()
	return true

func _exercise_chat(main: Control) -> bool:
	var store = main.get("chats")
	if not store is ChatStore:
		_fail("Main UI is not connected to ChatStore", 60)
		return false
	var before: String = str(store.active_chat_id)
	main.call("_new_chat")
	await process_frame
	if store.active_chat_id.is_empty() or store.active_chat_id == before:
		_fail("New chat action did not create/activate a chat", 61)
		return false
	store.add_message("user", "Проверка ровной пользовательской карточки")
	store.add_message("assistant", "Проверка ответа AuroraFox без временной картинки рядом с сообщением.")
	store.rename_chat(store.active_chat_id, "Очень длинное название чата для проверки безопасного поведения заголовка AuroraFox без наложений")
	main.call("_render_active_chat")
	await process_frame
	await process_frame
	if _visible_placeholder_fox(main):
		_fail("Assistant message rendered temporary avatar artwork", 62)
		return false
	var messages := main.find_child("MessageList", true, false)
	if messages != null:
		for node in messages.find_children("*", "TextureRect", true, false):
			var rect := node as TextureRect
			if rect.texture != null and rect.texture.resource_path == OWNER_AVATAR_MASTER:
				_fail("Owner avatar was duplicated beside an assistant message", 89)
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
	if not await _exercise_computer_contract(main):
		return false
	if not await _exercise_work_header(main):
		return false

	var new_chat := main.find_child("NewChatButton", true, false) as Button
	if new_chat == null or not (new_chat.get_theme_stylebox("normal") is StyleBoxFlat) or new_chat.get_theme_stylebox("normal") is StyleBoxTexture:
		_fail("Desktop buttons are not using safe rounded flat states", 70)
		return false

	var sidebar := main.find_child("Sidebar", true, false) as Control
	var panel := main.find_child("MainPanel", true, false) as Control
	var composer := main.find_child("ComposerMargin", true, false) as Control
	var header_actions := main.find_child("MainHeaderActions", true, false) as Control
	for target_size in [Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1440, 900)]:
		root.content_scale_size = target_size
		await process_frame
		await process_frame
		var viewport_size := main.get_viewport().get_visible_rect().size
		if target_size.x == 960 and sidebar.custom_minimum_size.x > 240.0:
			_fail("Compact sidebar remained too wide at 960px", 71)
			return false
		if composer.position.y + composer.size.y > viewport_size.y + 2.0:
			_fail("Composer exceeds desktop viewport at %s" % str(target_size), 72)
			return false
		if panel.size.x < 1.0 or composer.size.x < 1.0:
			_fail("Main desktop region collapsed at %s" % str(target_size), 73)
			return false
		if header_actions != null and header_actions.visible:
			_fail("Empty desktop header actions container should not consume space", 74)
			return false

	if not await _exercise_chat(main):
		_fail("Desktop chat behavior regression", 75)
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
		_fail("Mobile composer controls missing", 80)
		return false
	if composer.position.y + composer.size.y > viewport_size.y + 2.0:
		_fail("Mobile composer exceeds portrait viewport", 81)
		return false
	if input.custom_minimum_size.y > 90.0:
		_fail("Mobile composer input is unnecessarily tall", 82)
		return false
	if not await _exercise_chat(main):
		_fail("Mobile chat behavior regression", 83)
		return false

	var settings := main.get_node_or_null("SettingsOverlay") as AuroraSettingsOverlay
	settings.call("_fit_popup")
	var settings_popup := main.find_child("SettingsPopup", true, false) as PopupPanel
	if settings_popup == null or settings_popup.size.x > int(viewport_size.x) or settings_popup.size.y > int(viewport_size.y):
		_fail("Mobile settings popup exceeds portrait viewport", 84)
		return false

	main.queue_free()
	await process_frame
	ProjectSettings.set_setting("aurorafox/testing/mobile_preview", false)
	return true

func _run() -> void:
	for asset in [OWNER_AVATAR_MASTER, OWNER_BACKGROUND_MASTER]:
		if load(asset) == null:
			_fail("Owner-approved AuroraFox asset cannot be loaded: " + asset, 2)
			return
	for forbidden_asset in ["res://assets/ui/aurora_fox_user.jpg", "res://assets/ui/aurora_button_user.jpg"]:
		if FileAccess.file_exists(forbidden_asset):
			_fail("Corrupted legacy UI asset must not be packaged: " + forbidden_asset, 3)
			return

	var scene_text := FileAccess.get_file_as_string("res://main.tscn")
	for node_name in ["DesktopVisualTheme", "SettingsVisualFix", "WindowsStartupCoordinator", "ApiAgentBridge", "ApiGatewayManager", "ApiSettings", "WorkManager", "WorkOverlay", "ComputerOverlay"]:
		if not scene_text.contains(node_name):
			_fail("main.tscn is missing integrated node: " + node_name, 4)
			return

	var api_text := FileAccess.get_file_as_string("res://api/settings_overlay.gd")
	for endpoint in ["/v1/auth/login", "/v1/auth/guest", "/v1/auth/refresh", "/v1/account/devices/", "/v1/account/migrate-guest", "/v1/sync/pull", "/v1/sync/push"]:
		if not api_text.contains(endpoint):
			_fail("Personal account UI is missing real server contract: " + endpoint, 5)
			return

	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded", 6)
		return
	if not await _run_desktop(packed):
		return
	if not await _run_mobile_preview(packed):
		return
	print("AURORA_DESKTOP_AND_MOBILE_UI_SMOKE_OK")
	quit(0)
