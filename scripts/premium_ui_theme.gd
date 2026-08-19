class_name AuroraPremiumUITheme
extends Node

const ASSET_ROOT := "res://assets/ui/AuroraFox_UI/"
const MAP_PATH := ASSET_ROOT + "ASSET_MAP.json"
const BACKGROUND_PATH := ASSET_ROOT + "backgrounds/aurorafox_chat_background.png"
const LOGO_PATH := ASSET_ROOT + "icons/aurorafox_logo.png"
const APP_ICON_PATH := ASSET_ROOT + "icons/aurorafox_app_icon.png"

var _root: Control
var _map: Dictionary = {}
var _premium_ready := false

func _ready() -> void:
	_root = get_parent() as Control
	if _root == null:
		return
	_load_map()
	_premium_ready = _has_required_assets()
	if not _premium_ready:
		return
	call_deferred("_apply_after_main_build")

func _load_map() -> void:
	if not FileAccess.file_exists(MAP_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	if parsed is Dictionary:
		_map = parsed

func _has_required_assets() -> bool:
	if _map.is_empty():
		return false
	for path in [BACKGROUND_PATH, LOGO_PATH, APP_ICON_PATH]:
		if not ResourceLoader.exists(path):
			return false
	var buttons: Dictionary = _map.get("buttons", {})
	for required in ["new_chat", "settings", "attach", "send", "computer", "auto", "microphone", "speaker"]:
		if not buttons.has(required):
			return false
		var states: Dictionary = buttons[required].get("states", {})
		for state in ["normal", "hover", "pressed", "disabled"]:
			var rel := str(states.get(state, ""))
			if rel.is_empty() or not ResourceLoader.exists(ASSET_ROOT + rel):
				return false
	return true

func _apply_after_main_build() -> void:
	for _i in range(3):
		await get_tree().process_frame
	_replace_main_artwork(_root)
	_apply_button_tree(_root)
	_apply_runtime_window_icon()

func _replace_main_artwork(node: Node) -> void:
	var background := load(BACKGROUND_PATH) as Texture2D
	var logo := load(LOGO_PATH) as Texture2D
	for child in node.get_children():
		if child is TextureRect:
			var rect := child as TextureRect
			var path := rect.texture.resource_path if rect.texture != null else ""
			if path.ends_with("aurora_background.svg") or path.ends_with("aurora_background_final.svg") or path.ends_with("aurorafox_chat_background.png"):
				rect.texture = background
				rect.modulate = Color.WHITE
				rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			elif path.ends_with("fox_logo.svg") or path.ends_with("aurorafox_logo.png"):
				rect.texture = logo
				rect.modulate = Color.WHITE
		_replace_main_artwork(child)

	var avatar_slot := _root.find_child("AvatarSlot", true, false) as Control
	if avatar_slot != null:
		for old in avatar_slot.get_children():
			old.visible = false
		var premium := avatar_slot.find_child("AuroraFoxPremiumAvatar", false, false) as TextureRect
		if premium == null:
			premium = TextureRect.new()
			premium.name = "AuroraFoxPremiumAvatar"
			premium.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			premium.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			premium.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			premium.mouse_filter = Control.MOUSE_FILTER_IGNORE
			avatar_slot.add_child(premium)
		premium.texture = logo
		premium.visible = true

func _apply_button_tree(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			var button := child as Button
			var kind := _button_kind(button)
			if not kind.is_empty():
				_apply_button_kind(button, kind)
		_apply_button_tree(child)

func _button_kind(button: Button) -> String:
	match button.name:
		"NewChatButton": return "new_chat"
		"SettingsButton": return "settings"
		"AttachButton": return "attach"
		"SendButton": return "send"
		"VoiceMicButton": return "microphone"
		"VoiceSpeakButton": return "speaker"
		"VoiceSettingsButton": return "chat_options"
		"ComputerAgentToggle": return "computer"
		"ComputerAgentAuto": return "auto"
		"ComputerAgentSetup": return "prepare_ai"
		"WorkButton": return "settings_secondary"

	var tooltip := button.tooltip_text.to_lower()
	var text := button.text.to_lower()
	if tooltip.contains("переименовать чат"):
		return "chat_rename"
	if tooltip.contains("удалить чат"):
		return "chat_delete"
	if _has_ancestor_named(button, "ChatList"):
		return "chat_history"
	if button.name.to_lower().contains("update") or tooltip.contains("обновлен"):
		return "update"
	if text.contains("подготов"):
		return "prepare_ai"
	if text.contains("закрыть") or text.contains("готово"):
		return "settings_close"
	if _has_popup_ancestor(button):
		var width := button.custom_minimum_size.x
		if width >= 280.0:
			return "settings_primary"
		if width >= 180.0:
			return "settings_secondary"
		return "settings_small"
	return ""

func _has_ancestor_named(node: Node, wanted: String) -> bool:
	var current := node.get_parent()
	while current != null:
		if current.name == wanted:
			return true
		current = current.get_parent()
	return false

func _has_popup_ancestor(node: Node) -> bool:
	var current := node.get_parent()
	while current != null:
		if current is PopupPanel or current is AcceptDialog or current is ConfirmationDialog:
			return true
		current = current.get_parent()
	return false

func _apply_button_kind(button: Button, kind: String) -> void:
	var buttons: Dictionary = _map.get("buttons", {})
	if not buttons.has(kind):
		return
	var spec: Dictionary = buttons[kind]
	var states: Dictionary = spec.get("states", {})
	for state in ["normal", "hover", "pressed", "disabled"]:
		var rel := str(states.get(state, ""))
		if rel.is_empty():
			continue
		var path := ASSET_ROOT + rel
		if not ResourceLoader.exists(path):
			continue
		var texture := load(path) as Texture2D
		if texture == null:
			continue
		var style := StyleBoxTexture.new()
		style.texture = texture
		button.add_theme_stylebox_override(state, style)
	if button.has_theme_stylebox_override("hover"):
		button.add_theme_stylebox_override("focus", button.get_theme_stylebox("hover"))
	button.add_theme_color_override("font_color", Color("f5f8ff"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.62, 0.66, 0.74, 0.72))
	var size: Array = spec.get("size", [])
	if size.size() >= 2:
		button.custom_minimum_size.y = float(size[1])
		# Preserve exact source width on normal desktop layouts; compact mode may shrink horizontally.
		if get_viewport().get_visible_rect().size.x >= 1180.0:
			button.custom_minimum_size.x = float(size[0])

func _apply_runtime_window_icon() -> void:
	if not ResourceLoader.exists(APP_ICON_PATH):
		return
	var texture := load(APP_ICON_PATH) as Texture2D
	if texture != null:
		DisplayServer.set_icon(texture.get_image())

func status() -> Dictionary:
	return {
		"premium_ready": _premium_ready,
		"asset_root": ASSET_ROOT,
		"mapped_button_groups": int((_map.get("buttons", {}) as Dictionary).size()) if not _map.is_empty() else 0
	}
