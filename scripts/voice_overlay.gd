extends Node

const UI_ATLAS: Texture2D = preload("res://assets/ui_atlas.webp")
const REGION_BUTTON_PURPLE := Rect2(17, 456, 135, 38)
const REGION_BUTTON_PURPLE_ALT := Rect2(167, 456, 135, 38)
const REGION_BUTTON_CYAN := Rect2(326, 456, 142, 38)
const REGION_BUTTON_CYAN_ALT := Rect2(482, 456, 131, 38)

var mic_player: AudioStreamPlayer
var record_effect: AudioEffectRecord
var recording := false
var mic_button: Button
var speak_button: Button
var settings_popup: PopupPanel
var avatar_view: AuroraFoxAvatarView
var status_label: Label
var mic_device_option: OptionButton

func _ready() -> void:
	await get_tree().process_frame
	_build_overlay()
	_setup_microphone()
	AuroraVoice.bind_avatar(avatar_view)
	AuroraVoice.transcript_ready.connect(_submit_transcript)
	AuroraVoice.backend_status.connect(_on_backend_status)
	AuroraVoice.listening_started.connect(func(): status_label.text = "Слушаю…")
	AuroraVoice.listening_finished.connect(func(): status_label.text = "")
	AuroraVoice.speech_started.connect(func(): status_label.text = "Говорю…")
	AuroraVoice.speech_finished.connect(func(): status_label.text = "")
	_refresh_buttons()
	if AuroraVoice.backend_is_ready: _refresh_devices()

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

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)

	avatar_view = AuroraFoxAvatarView.new()
	avatar_view.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	avatar_view.position = Vector2(-196, 70)
	layer.add_child(avatar_view)

	status_label = Label.new()
	status_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	status_label.position = Vector2(-190, 205)
	status_label.size = Vector2(180, 26)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color("8993aa"))
	layer.add_child(status_label)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.position = Vector2(-345, -86)
	row.custom_minimum_size = Vector2(330, 52)
	row.add_theme_constant_override("separation", 7)
	layer.add_child(row)

	mic_button = Button.new()
	mic_button.custom_minimum_size = Vector2(112, 48)
	mic_button.pressed.connect(_mic_pressed)
	_apply_button(mic_button, true)
	row.add_child(mic_button)

	speak_button = Button.new()
	speak_button.custom_minimum_size = Vector2(112, 48)
	speak_button.pressed.connect(_toggle_speech)
	_apply_button(speak_button, false)
	row.add_child(speak_button)

	var settings_button := Button.new()
	settings_button.text = "⚙"
	settings_button.tooltip_text = "Настройки голоса"
	settings_button.custom_minimum_size = Vector2(54, 48)
	settings_button.pressed.connect(_open_settings)
	_apply_button(settings_button, true)
	row.add_child(settings_button)

	settings_popup = PopupPanel.new()
	settings_popup.size = Vector2i(560, 720)
	layer.add_child(settings_popup)
	_build_settings(settings_popup)

func _build_settings(popup: PopupPanel) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	popup.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "Голос AuroraFox"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	box.add_child(_check("Голос AuroraFox", "enabled"))
	box.add_child(_check("Озвучивать ответы", "auto_speak"))
	box.add_child(_option("Движок", "backend", ["auto", "silero", "xtts"], ["Автоматически", "Silero", "XTTS / Advanced"]))
	box.add_child(_option("Качество", "quality", ["fast", "balanced", "quality"], ["Быстро", "Сбалансировано", "Качество"]))
	box.add_child(_slider("Громкость", "volume", 0.0, 1.0, 0.01))
	box.add_child(_slider("Скорость", "speed", 0.85, 1.18, 0.01))
	box.add_child(_slider("Высота голоса", "pitch", 0.94, 1.08, 0.005))
	box.add_child(_slider("Механический оттенок", "mechanical_amount", 0.0, 0.10, 0.005))
	box.add_child(_slider("Эмоциональность", "emotionality", 0.0, 1.0, 0.01))
	box.add_child(_check("Системные звуки", "system_sounds"))
	box.add_child(_check("Приветствие при запуске", "startup_greeting"))
	box.add_child(_check("Останавливать речь, когда говорю я", "barge_in"))

	var mic_title := Label.new()
	mic_title.text = "Микрофон"
	mic_title.add_theme_font_size_override("font_size", 19)
	box.add_child(mic_title)
	mic_device_option = OptionButton.new()
	mic_device_option.add_item("Системный микрофон")
	mic_device_option.set_item_metadata(0, -1)
	mic_device_option.item_selected.connect(func(i): AuroraVoice.update_setting("mic_device", int(mic_device_option.get_item_metadata(i))))
	box.add_child(mic_device_option)
	var refresh := Button.new()
	refresh.text = "Обновить список микрофонов"
	refresh.pressed.connect(_refresh_devices)
	_apply_button(refresh, true)
	box.add_child(refresh)
	box.add_child(_option("Режим", "mic_mode", ["off", "wake_word", "continuous", "push_to_talk"], ["Выкл.", "Fox / Лиса", "Постоянный диалог", "Push-to-talk"]))
	box.add_child(_slider("Чувствительность", "mic_sensitivity", 0.0, 1.0, 0.01))
	box.add_child(_check("Подавление фонового шума", "noise_suppression"))

	var clear := Button.new()
	clear.text = "Очистить голосовой кэш"
	_apply_button(clear, false)
	clear.pressed.connect(_clear_cache)
	box.add_child(clear)
	var note := Label.new()
	note.text = "Wake word, VAD, STT и TTS обрабатываются локально. XTTS включается только при настроенном собственном speaker_wav."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

func _check(text: String, key: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = bool(AuroraVoice.settings.get(key, false))
	c.toggled.connect(func(v): AuroraVoice.update_setting(key, v); _refresh_buttons())
	return c

func _option(label_text: String, key: String, values: Array, labels: Array) -> VBoxContainer:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	box.add_child(l)
	var o := OptionButton.new()
	for i in range(values.size()):
		o.add_item(str(labels[i]))
		o.set_item_metadata(i, values[i])
	for i in range(values.size()):
		if str(values[i]) == str(AuroraVoice.settings.get(key, values[0])): o.select(i)
	o.item_selected.connect(func(i): AuroraVoice.update_setting(key, o.get_item_metadata(i)); _refresh_buttons())
	box.add_child(o)
	return box

func _slider(label_text: String, key: String, min_v: float, max_v: float, step_v: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	var l := Label.new()
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	s.value = float(AuroraVoice.settings.get(key, min_v))
	box.add_child(s)
	var update_label := func(v): l.text = "%s: %.2f" % [label_text, v]
	update_label.call(s.value)
	s.value_changed.connect(func(v): update_label.call(v); AuroraVoice.update_setting(key, v))
	return box

func _setup_microphone() -> void:
	var bus_name := "AuroraFoxRecord"
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, bus_name)
	AudioServer.set_bus_mute(bus_idx, true)
	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		var effect := AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectRecord: record_effect = effect
	if record_effect == null:
		record_effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(bus_idx, record_effect)
	mic_player = AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = bus_name
	add_child(mic_player)

func _mic_pressed() -> void:
	var mode := str(AuroraVoice.settings.get("mic_mode", "wake_word"))
	if mode == "push_to_talk":
		if recording: await _stop_ptt()
		else: _start_ptt()
	elif mode == "off":
		AuroraVoice.set_mic_mode("wake_word")
	else:
		AuroraVoice.start_listening()
	_refresh_buttons()

func _start_ptt() -> void:
	if record_effect == null: return
	record_effect.set_recording_active(true)
	mic_player.play()
	recording = true
	mic_button.text = "■ Говорите…"
	AuroraVoice.stop()

func _stop_ptt() -> void:
	record_effect.set_recording_active(false)
	mic_player.stop()
	recording = false
	mic_button.text = "…"
	var rec := record_effect.get_recording()
	if rec == null:
		_refresh_buttons()
		return
	var path := "user://aurorafox_voice_input.wav"
	if rec.save_to_wav("user://aurorafox_voice_input") != OK:
		_refresh_buttons()
		return
	var result := await AuroraVoice.bridge.transcribe_file(path)
	if result.get("ok", false): _submit_transcript(str(result.get("text", "")))
	_refresh_buttons()

func _submit_transcript(text: String) -> void:
	if text.strip_edges().is_empty(): return
	var main := get_parent()
	if main != null and main.has_method("submit_voice_text"):
		main.call("submit_voice_text", text.strip_edges())

func _toggle_speech() -> void:
	AuroraVoice.set_auto_speak(not bool(AuroraVoice.settings.get("auto_speak", true)))
	_refresh_buttons()

func _open_settings() -> void:
	settings_popup.popup_centered()
	_refresh_devices()

func _clear_cache() -> void:
	var result := await AuroraVoice.clear_cache()
	status_label.text = "Кэш очищен" if result.get("ok", false) else "Ошибка кэша"

func _refresh_devices() -> void:
	if mic_device_option == null: return
	var result := await AuroraVoice.bridge.devices()
	if not result.get("ok", false): return
	var selected_id := int(AuroraVoice.settings.get("mic_device", -1))
	mic_device_option.clear()
	mic_device_option.add_item("Системный микрофон")
	mic_device_option.set_item_metadata(0, -1)
	var selected_index := 0
	for device in result.get("devices", []):
		var idx := mic_device_option.item_count
		mic_device_option.add_item(str(device.get("name", "Микрофон")))
		mic_device_option.set_item_metadata(idx, int(device.get("id", -1)))
		if int(device.get("id", -1)) == selected_id: selected_index = idx
	mic_device_option.select(selected_index)

func _on_backend_status(ready: bool, _info: Dictionary) -> void:
	status_label.text = "Голос готов" if ready else "Голос недоступен"
	if ready: _refresh_devices()

func _refresh_buttons() -> void:
	if mic_button == null: return
	var mode := str(AuroraVoice.settings.get("mic_mode", "wake_word"))
	mic_button.text = {"off":"🎙 Выкл.", "wake_word":"🎙 Fox / Лиса", "continuous":"🎙 Диалог", "push_to_talk":"🎙 Нажми"}.get(mode, "🎙")
	speak_button.text = "🔊" if bool(AuroraVoice.settings.get("auto_speak", true)) else "🔇"
