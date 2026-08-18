extends Node

const UI_ATLAS: Texture2D = preload("res://assets/ui_atlas.webp")
const REGION_BUTTON_PURPLE := Rect2(17, 456, 135, 38)
const REGION_BUTTON_PURPLE_ALT := Rect2(167, 456, 135, 38)
const REGION_BUTTON_CYAN := Rect2(326, 456, 142, 38)
const REGION_BUTTON_CYAN_ALT := Rect2(482, 456, 131, 38)

var voice := VoiceClient.new()
var mic_player: AudioStreamPlayer
var record_effect: AudioEffectRecord
var mic_button: Button
var speak_button: Button
var recording := false
var voice_ready := false
var last_spoken_text := ""
var scan_accumulator := 0.0

func _ready() -> void:
	add_child(voice)
	await get_tree().process_frame
	_build_voice_controls()
	_setup_microphone()
	_seed_last_spoken_message()
	voice_ready = await voice.is_available()
	_update_button_state()

func _process(delta: float) -> void:
	scan_accumulator += delta
	if scan_accumulator < 0.65:
		return
	scan_accumulator = 0.0
	if voice_ready and voice.auto_speak:
		_check_for_new_assistant_message()

func _atlas_texture(region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = UI_ATLAS
	texture.region = region
	return texture

func _style(region: Rect2) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _atlas_texture(region)
	style.texture_margin_left = 11
	style.texture_margin_right = 11
	style.texture_margin_top = 11
	style.texture_margin_bottom = 11
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _apply_button(button: Button, cyan: bool) -> void:
	var normal := REGION_BUTTON_CYAN if cyan else REGION_BUTTON_PURPLE
	var hover := REGION_BUTTON_CYAN_ALT if cyan else REGION_BUTTON_PURPLE_ALT
	button.add_theme_stylebox_override("normal", _style(normal))
	button.add_theme_stylebox_override("hover", _style(hover))
	button.add_theme_stylebox_override("pressed", _style(hover))
	button.add_theme_stylebox_override("focus", _style(hover))
	button.add_theme_color_override("font_color", Color("eef5ff"))

func _build_voice_controls() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.position = Vector2(-270, -86)
	row.custom_minimum_size = Vector2(250, 52)
	row.add_theme_constant_override("separation", 8)
	layer.add_child(row)

	mic_button = Button.new()
	mic_button.text = "🎙 Голос"
	mic_button.tooltip_text = "Нажмите, скажите фразу и нажмите ещё раз"
	mic_button.custom_minimum_size = Vector2(122, 48)
	mic_button.pressed.connect(_toggle_recording)
	_apply_button(mic_button, true)
	row.add_child(mic_button)

	speak_button = Button.new()
	speak_button.text = "🔊 Ответы"
	speak_button.tooltip_text = "Автоматически читать ответы AuroraFox"
	speak_button.custom_minimum_size = Vector2(122, 48)
	speak_button.pressed.connect(_toggle_auto_speak)
	_apply_button(speak_button, false)
	row.add_child(speak_button)

func _setup_microphone() -> void:
	var bus_name := "AuroraFoxRecord"
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, bus_name)
	AudioServer.set_bus_mute(bus_idx, true)

	record_effect = null
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var effect := AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectRecord:
			record_effect = effect
			break
	if record_effect == null:
		record_effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(bus_idx, record_effect)

	mic_player = AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = bus_name
	add_child(mic_player)

func _toggle_recording() -> void:
	if not voice_ready:
		mic_button.text = "⚠ Установите голос"
		return
	if recording:
		await _stop_recording_and_transcribe()
	else:
		_start_recording()

func _start_recording() -> void:
	if record_effect == null:
		return
	record_effect.set_recording_active(true)
	mic_player.play()
	recording = true
	mic_button.text = "■ Говорите…"

func _stop_recording_and_transcribe() -> void:
	record_effect.set_recording_active(false)
	mic_player.stop()
	recording = false
	mic_button.text = "… Распознаю"
	var recording_data := record_effect.get_recording()
	if recording_data == null:
		mic_button.text = "🎙 Голос"
		return
	var save_error := recording_data.save_to_wav("user://aurorafox_voice_input")
	if save_error != OK:
		mic_button.text = "⚠ Ошибка записи"
		return
	var result := await voice.transcribe("user://aurorafox_voice_input.wav")
	if not result.get("ok", false):
		mic_button.text = "⚠ Ошибка речи"
		return
	var text := str(result.get("text", "")).strip_edges()
	var editor := _find_text_edit(get_tree().current_scene)
	if editor != null and not text.is_empty():
		editor.text = text
		editor.grab_focus()
	mic_button.text = "🎙 Голос"

func _toggle_auto_speak() -> void:
	voice.auto_speak = not voice.auto_speak
	_update_button_state()

func _update_button_state() -> void:
	if mic_button == null or speak_button == null:
		return
	if voice_ready:
		mic_button.text = "🎙 Голос"
	else:
		mic_button.text = "⚠ Голос не установлен"
	speak_button.text = "🔊 Ответы: ВКЛ" if voice.auto_speak else "🔇 Ответы: ВЫКЛ"

func _find_text_edit(node: Node) -> TextEdit:
	if node is TextEdit:
		return node
	for child in node.get_children():
		var found := _find_text_edit(child)
		if found != null:
			return found
	return null

func _find_chat_store() -> ChatStore:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for child in scene.get_children():
		if child is ChatStore:
			return child
	return null

func _latest_assistant_text() -> String:
	var store := _find_chat_store()
	if store == null:
		return ""
	var chat: Dictionary = store.get_active_chat()
	var messages: Array = chat.get("messages", [])
	for index in range(messages.size() - 1, -1, -1):
		var message: Dictionary = messages[index]
		if str(message.get("role", "")) == "assistant":
			return str(message.get("content", "")).strip_edges()
	return ""

func _seed_last_spoken_message() -> void:
	last_spoken_text = _latest_assistant_text()

func _check_for_new_assistant_message() -> void:
	var text := _latest_assistant_text()
	if text.is_empty() or text == last_spoken_text:
		return
	last_spoken_text = text
	var generated := await voice.speak(text)
	if generated.get("ok", false):
		voice.play_wav(str(generated.get("path", "")), self)
