extends Node

const ICON_MIC: Texture2D = preload("res://assets/ui/icon_mic.svg")

var mic_player: AudioStreamPlayer
var record_effect: AudioEffectRecord
var recording := false
var mic_button: Button
var status_label: Label

func _voice() -> Node:
	return get_node_or_null("/root/AuroraVoice")

func _voice_settings() -> Dictionary:
	var voice := _voice()
	if voice == null:
		return {}
	var raw = voice.get("settings")
	return raw if raw is Dictionary else {}

func _ready() -> void:
	await get_tree().process_frame
	_build_overlay()
	_setup_microphone()
	_bind_voice_runtime()
	_refresh_buttons()

func _bind_voice_runtime() -> void:
	var voice := _voice()
	if voice == null:
		if mic_button != null:
			mic_button.disabled = true
			mic_button.tooltip_text = "Голосовой модуль сейчас не подключён"
		if status_label != null:
			status_label.text = ""
		return
	if voice.has_method("bind_avatar"):
		voice.call("bind_avatar", null)
	if voice.has_signal("transcript_ready"):
		voice.connect("transcript_ready", Callable(self, "_submit_transcript"))
	if voice.has_signal("backend_status"):
		voice.connect("backend_status", Callable(self, "_on_backend_status"))
	if voice.has_signal("listening_started"):
		voice.connect("listening_started", func(): if status_label != null: status_label.text = "Слушаю")
	if voice.has_signal("listening_finished"):
		voice.connect("listening_finished", func(): if status_label != null: status_label.text = "")
	if voice.has_signal("speech_started"):
		voice.connect("speech_started", func(): if status_label != null: status_label.text = "Говорю")
	if voice.has_signal("speech_finished"):
		voice.connect("speech_finished", func(): if status_label != null: status_label.text = "")

func _style(fill: Color, border: Color, radius := 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _apply_button(button: Button, accent: bool) -> void:
	var border := Color(0.30, 0.34, 0.46, 0.62)
	if accent:
		border = Color(0.27, 0.83, 1.0, 0.82)
	button.add_theme_stylebox_override("normal", _style(Color(0.055, 0.066, 0.10, 0.98), border))
	button.add_theme_stylebox_override("hover", _style(Color(0.10, 0.12, 0.18, 1.0), Color(0.38, 0.83, 1.0, 0.90)))
	button.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.11, 0.22, 1.0), Color(0.66, 0.54, 1.0, 0.92)))
	button.add_theme_stylebox_override("focus", _style(Color(0.10, 0.12, 0.18, 1.0), Color(0.38, 0.83, 1.0, 0.90)))
	button.add_theme_color_override("font_color", Color("eef5ff"))
	button.expand_icon = false
	button.clip_text = true

func _build_overlay() -> void:
	var main := get_parent()
	if main == null:
		return
	var voice_dock := main.find_child("VoiceDock", true, false) as HBoxContainer
	if voice_dock == null:
		voice_dock = HBoxContainer.new()
		voice_dock.name = "VoiceDock"
		main.add_child(voice_dock)
	for child in voice_dock.get_children():
		child.queue_free()

	mic_button = Button.new()
	mic_button.name = "VoiceMicButton"
	mic_button.icon = ICON_MIC
	mic_button.tooltip_text = "Микрофон AuroraFox"
	mic_button.custom_minimum_size = Vector2(46, 46)
	mic_button.pressed.connect(_mic_pressed)
	_apply_button(mic_button, true)
	voice_dock.add_child(mic_button)

	status_label = Label.new()
	status_label.name = "VoiceStatus"
	status_label.custom_minimum_size.x = 0
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", Color("8993aa"))
	voice_dock.add_child(status_label)

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
	var voice := _voice()
	if voice == null:
		_refresh_buttons()
		return
	var mode := str(_voice_settings().get("mic_mode", "wake_word"))
	if mode == "push_to_talk":
		if recording:
			await _stop_ptt()
		else:
			_start_ptt()
	elif mode == "off":
		if voice.has_method("set_mic_mode"):
			voice.call("set_mic_mode", "wake_word")
	else:
		if voice.has_method("start_listening"):
			voice.call("start_listening")
	_refresh_buttons()

func _start_ptt() -> void:
	var voice := _voice()
	if record_effect == null or voice == null:
		return
	record_effect.set_recording_active(true)
	mic_player.play()
	recording = true
	status_label.text = "Говорите"
	if voice.has_method("stop"):
		voice.call("stop")

func _stop_ptt() -> void:
	var voice := _voice()
	if voice == null:
		return
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
	var bridge = voice.get("bridge")
	if bridge == null or not bridge.has_method("transcribe_file"):
		_refresh_buttons()
		return
	var result = await bridge.call("transcribe_file", path)
	if result is Dictionary and result.get("ok", false):
		_submit_transcript(str(result.get("text", "")))
	_refresh_buttons()

func _submit_transcript(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	var main := get_parent()
	if main != null and main.has_method("submit_voice_text"):
		main.call("submit_voice_text", text.strip_edges())

func _on_backend_status(ready: bool, _info: Dictionary) -> void:
	if status_label != null:
		status_label.text = "Голос готов" if ready else ""
	if mic_button != null:
		mic_button.disabled = not ready
	_refresh_buttons()

func _refresh_buttons() -> void:
	if mic_button == null:
		return
	var voice := _voice()
	if voice == null:
		mic_button.disabled = true
		mic_button.tooltip_text = "Голосовой модуль сейчас не подключён"
		_apply_button(mic_button, false)
		return
	var mode := str(_voice_settings().get("mic_mode", "wake_word"))
	mic_button.tooltip_text = {
		"off": "Микрофон выключен — нажмите, чтобы включить",
		"wake_word": "Микрофон: Fox / Фокс / Лиса",
		"continuous": "Микрофон: постоянный диалог",
		"push_to_talk": "Микрофон: нажать и говорить"
	}.get(mode, "Микрофон AuroraFox")
	_apply_button(mic_button, mode != "off")
