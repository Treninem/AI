extends Node

const ICON_MIC: Texture2D = preload("res://assets/ui/icon_mic.svg")
const ICON_SPEAKER: Texture2D = preload("res://assets/ui/icon_speaker.svg")
const ICON_SETTINGS: Texture2D = preload("res://assets/ui/icon_settings.svg")

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
	AuroraVoice.listening_started.connect(func(): status_label.text = "Слушаю")
	AuroraVoice.listening_finished.connect(func(): status_label.text = "")
	AuroraVoice.speech_started.connect(func(): status_label.text = "Говорю")
	AuroraVoice.speech_finished.connect(func(): status_label.text = "")
	_refresh_buttons()
	if AuroraVoice.backend_is_ready:
		_refresh_devices()

func _style(fill: Color, border: Color, radius := 11) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _apply_button(button: Button, accent: bool) -> void:
	var border := Color(0.30, 0.34, 0.46, 0.6)
	if accent:
		border = Color(0.27, 0.83, 1.0, 0.68)
	button.add_theme_stylebox_override("normal", _style(Color(0.055, 0.066, 0.10, 0.96), border))
	button.add_theme_stylebox_override("hover", _style(Color(0.10, 0.12, 0.18, 1.0), border))
	button.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.11, 0.22, 1.0), Color(0.66, 0.54, 1.0, 0.85)))
	button.add_theme_stylebox_override("focus", _style(Color(0.10, 0.12, 0.18, 1.0), Color(0.66, 0.54, 1.0, 0.85)))
	button.add_theme_color_override("font_color", Color("eef5ff"))
	button.expand_icon = true
	button.icon_max_width = 19

func _build_overlay() -> void:
	var main := get_parent()
	if main == null:
		return

	var avatar_slot := main.find_child("AvatarSlot", true, false) as Control
	if avatar_slot != null:
		avatar_view = AuroraFoxAvatarView.new()
		avatar_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		avatar_slot.add_child(avatar_view)
	else:
		avatar_view = AuroraFoxAvatarView.new()
		avatar_view.visible = false
		main.add_child(avatar_view)

	var voice_dock := main.find_child("VoiceDock", true, false) as HBoxContainer
	if voice_dock == null:
		voice_dock = HBoxContainer.new()
		voice_dock.visible = false
		main.add_child(voice_dock)

	mic_button = Button.new()
	mic_button.name = "VoiceMicButton"
	mic_button.icon = ICON_MIC
	mic_button.tooltip_text = "Микрофон AuroraFox"
	mic_button.custom_minimum_size = Vector2(42, 42)
	mic_button.pressed.connect(_mic_pressed)
	voice_dock.add_child(mic_button)

	speak_button = Button.new()
	speak_button.name = "VoiceSpeakButton"
	speak_button.icon = ICON_SPEAKER
	speak_button.tooltip_text = "Озвучивание ответов"
	speak_button.custom_minimum_size = Vector2(42, 42)
	speak_button.pressed.connect(_toggle_speech)
	voice_dock.add_child(speak_button)

	var settings_button := Button.new()
	settings_button.name = "VoiceSettingsButton"
	settings_button.icon = ICON_SETTINGS
	settings_button.tooltip_text = "Настройки голоса"
	settings_button.custom_minimum_size = Vector2(42, 42)
	settings_button.pressed.connect(_open_settings)
	_apply_button(settings_button, false)
	voice_dock.add_child(settings_button)

	status_label = Label.new()
	status_label.name = "VoiceStatus"
	status_label.custom_minimum_size.x = 56
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", Color("8993aa"))
	voice_dock.add_child(status_label)

	settings_popup = PopupPanel.new()
	settings_popup.size = Vector2i(560, 720)
	main.add_child(settings_popup)
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
	box.add_child(_option("Режим", "mic_mode", ["off", "wake_word", "continuous", "push_to_talk"], ["Выкл.", "Fox / Фокс / Лиса", "Постоянный диалог", "Push-to-talk"]))
	box.add_child(_slider("Чувствительность", "mic_sensitivity", 0.0, 1.0, 0.01))
	box.add_child(_check("Подавление фонового шума", "noise_suppression"))

	var clear := Button.new()
	clear.text = "Очистить голосовой кэш"
	_apply_button(clear, false)
	clear.pressed.connect(_clear_cache)
	box.add_child(clear)
	var note := Label.new()
	note.text = "Wake word, VAD, STT и TTS обрабатываются локально. XTTS включается при настроенном разрешённом speaker reference."
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
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	var option := OptionButton.new()
	for i in range(values.size()):
		option.add_item(str(labels[i]))
		option.set_item_metadata(i, values[i])
	for i in range(values.size()):
		if str(values[i]) == str(AuroraVoice.settings.get(key, values[0])):
			option.select(i)
	option.item_selected.connect(func(i): AuroraVoice.update_setting(key, option.get_item_metadata(i)); _refresh_buttons())
	box.add_child(option)
	return box

func _slider(label_text: String, key: String, min_v: float, max_v: float, step_v: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = float(AuroraVoice.settings.get(key, min_v))
	box.add_child(slider)
	var update_label := func(v): label.text = "%s: %.2f" % [label_text, v]
	update_label.call(slider.value)
	slider.value_changed.connect(func(v): update_label.call(v); AuroraVoice.update_setting(key, v))
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
		if effect is AudioEffectRecord:
			record_effect = effect
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
		if recording:
			await _stop_ptt()
		else:
			_start_ptt()
	elif mode == "off":
		AuroraVoice.set_mic_mode("wake_word")
	else:
		AuroraVoice.start_listening()
	_refresh_buttons()

func _start_ptt() -> void:
	if record_effect == null:
		return
	record_effect.set_recording_active(true)
	mic_player.play()
	recording = true
	status_label.text = "Говорите"
	AuroraVoice.stop()

func _stop_ptt() -> void:
	record_effect.set_recording_active(false)
	mic_player.stop()
	recording = false
	status_label.text = ""
	var rec := record_effect.get_recording()
	if rec == null:
		_refresh_buttons()
		return
	var path := "user://aurorafox_voice_input.wav"
	if rec.save_to_wav("user://aurorafox_voice_input") != OK:
		_refresh_buttons()
		return
	var result := await AuroraVoice.bridge.transcribe_file(path)
	if result.get("ok", false):
		_submit_transcript(str(result.get("text", "")))
	_refresh_buttons()

func _submit_transcript(text: String) -> void:
	if text.strip_edges().is_empty():
		return
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
	if mic_device_option == null:
		return
	var result := await AuroraVoice.bridge.devices()
	if not result.get("ok", false):
		return
	var selected_id := int(AuroraVoice.settings.get("mic_device", -1))
	mic_device_option.clear()
	mic_device_option.add_item("Системный микрофон")
	mic_device_option.set_item_metadata(0, -1)
	var selected_index := 0
	for device in result.get("devices", []):
		var idx := mic_device_option.item_count
		mic_device_option.add_item(str(device.get("name", "Микрофон")))
		mic_device_option.set_item_metadata(idx, int(device.get("id", -1)))
		if int(device.get("id", -1)) == selected_id:
			selected_index = idx
	mic_device_option.select(selected_index)

func _on_backend_status(ready: bool, _info: Dictionary) -> void:
	status_label.text = "Голос готов" if ready else "Голос недоступен"
	if ready:
		_refresh_devices()

func _refresh_buttons() -> void:
	if mic_button == null:
		return
	var mode := str(AuroraVoice.settings.get("mic_mode", "wake_word"))
	mic_button.tooltip_text = {
		"off": "Микрофон выключен",
		"wake_word": "Wake word: Fox / Фокс / Лиса",
		"continuous": "Постоянный диалог",
		"push_to_talk": "Push-to-talk"
	}.get(mode, "Микрофон")
	_apply_button(mic_button, mode != "off")
	var auto_speak := bool(AuroraVoice.settings.get("auto_speak", true))
	speak_button.tooltip_text = "Озвучивание ответов включено" if auto_speak else "Озвучивание ответов выключено"
	_apply_button(speak_button, auto_speak)
