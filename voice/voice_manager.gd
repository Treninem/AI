class_name AuroraVoiceManager
extends Node

signal speech_started
signal speech_finished
signal speech_amplitude(value: float)
signal emotion_changed(emotion: String, intensity: float)
signal listening_started
signal listening_finished
signal thinking_started
signal thinking_finished
signal wake_word_detected
signal transcript_ready(text: String)
signal backend_status(ready: bool, info: Dictionary)
signal settings_changed(settings: Dictionary)

const SETTINGS_PATH := "user://aurora_voice_settings.json"
const PERSONALITY_PATH := "res://voice/config/personality.json"
const VERSION_PATH := "res://project/version.json"
const DEFAULTS := {
	"enabled": true,
	"auto_speak": true,
	"volume": 0.86,
	"speed": 1.04,
	"pitch": 1.02,
	"mechanical_amount": 0.035,
	"emotionality": 0.78,
	"system_sounds": true,
	"startup_greeting": false,
	"barge_in": true,
	"quality": "balanced",
	"backend": "auto",
	"mic_mode": "wake_word",
	"mic_device": -1,
	"mic_sensitivity": 0.5,
	"noise_suppression": true
}

var bridge := AuroraVoiceBridge.new()
var speech_queue := AuroraSpeechQueue.new()
var emotions := AuroraEmotionController.new()
var avatar := AuroraAvatarVoiceController.new()
var wake := AuroraWakeWordController.new()
var settings: Dictionary = DEFAULTS.duplicate(true)
var backend_is_ready := false
var _startup_done := false
var _personality: Dictionary = {}
var _last_local_phrase := ""
var _last_event_sound_ms := -10000

func _ready() -> void:
	_load_settings()
	_personality = _load_json(PERSONALITY_PATH)
	add_child(bridge)
	add_child(speech_queue)
	add_child(emotions)
	add_child(avatar)
	add_child(wake)
	speech_queue.setup(bridge)
	wake.setup(bridge)
	speech_queue.set_volume(float(settings.get("volume", 0.86)))
	bridge.backend_ready.connect(_on_backend_ready)
	bridge.backend_lost.connect(func(): backend_is_ready = false; backend_status.emit(false, {}))
	bridge.transcript_ready.connect(_on_transcript)
	bridge.barge_in.connect(_on_barge_in)
	bridge.user_speech_started.connect(_on_user_speech_started)
	bridge.user_speech_finished.connect(_on_user_speech_finished)
	wake.awakened.connect(_on_awakened)
	wake.listening_window_opened.connect(_on_window_opened)
	wake.listening_window_closed.connect(_on_window_closed)
	emotions.emotion_changed.connect(_on_emotion_changed)
	speech_queue.speech_started.connect(_on_speech_started)
	speech_queue.speech_finished.connect(_on_speech_finished)
	speech_queue.speech_amplitude.connect(_on_amplitude)
	_apply_mic_mode()

func bind_avatar(view: AuroraFoxAvatarView) -> void:
	avatar.bind(view)
	avatar.set_emotion(emotions.current_emotion, emotions.current_intensity, emotions.get_profile(emotions.current_emotion))

func say(text: String, emotion := "auto", intensity := -1.0, options: Dictionary = {}) -> void:
	if not bool(settings.get("enabled", true)) or not bool(settings.get("auto_speak", true)) or text.strip_edges().is_empty(): return
	var analysis := emotions.analyze(text) if emotion == "auto" else {"emotion": emotion, "intensity": 0.5 if intensity < 0.0 else intensity}
	var selected := str(analysis.get("emotion", "neutral"))
	var raw_power := float(analysis.get("intensity", 0.5) if intensity < 0.0 else intensity)
	var power := clampf(raw_power * float(settings.get("emotionality", 0.78)), 0.0, 1.0)
	var profile := emotions.get_profile(selected)
	emotions.set_emotion(selected, power, 7.0)

	# User sliders are the base voice. Emotion contributes only a bounded deviation from it.
	var profile_speed := float(profile.get("speed", 1.0))
	var profile_pitch := float(profile.get("pitch", 1.0))
	var profile_mech := float(profile.get("mechanical", settings.get("mechanical_amount", 0.035)))
	var speech_speed := float(settings.get("speed", 1.04)) * (1.0 + (profile_speed - 1.0) * power)
	var pitch_factor := float(settings.get("pitch", 1.02)) * (1.0 + (profile_pitch - 1.0) * power)
	var mechanical := lerpf(float(settings.get("mechanical_amount", 0.035)), profile_mech, power)

	var opts := options.duplicate(true)
	opts.merge({
		"backend": str(settings.get("backend", "auto")),
		"speed": clampf(speech_speed, 0.82, 1.20),
		"pitch": clampf(pitch_factor - 1.0, -0.08, 0.10),
		"mechanical_amount": clampf(mechanical, 0.0, 0.10)
	}, false)
	speech_queue.enqueue(text, selected, power, opts)

func stop() -> void:
	speech_queue.stop()

func pause() -> void:
	speech_queue.pause()

func resume() -> void:
	speech_queue.resume()

func start_listening() -> void:
	if not bool(settings.get("enabled", true)): return
	bridge.set_mode("continuous", _device_value(), _mic_options())
	wake.open_window()

func stop_listening() -> void:
	wake.close_window()
	_apply_mic_mode()

func set_enabled(value: bool) -> void:
	settings["enabled"] = value
	if not value:
		stop()
		bridge.set_mode("off")
	else:
		_apply_mic_mode()
	_save_settings()

func set_auto_speak(value: bool) -> void:
	settings["auto_speak"] = value
	if not value: stop()
	_save_settings()

func set_volume(value: float) -> void:
	settings["volume"] = clampf(value, 0.0, 1.0)
	speech_queue.set_volume(float(settings["volume"]))
	_save_settings()

func set_mic_mode(value: String) -> void:
	if value not in ["off", "wake_word", "continuous", "push_to_talk"]: return
	settings["mic_mode"] = value
	wake.mode = value
	_apply_mic_mode()
	_save_settings()

func update_setting(key: String, value: Variant) -> void:
	if not settings.has(key): return
	settings[key] = value
	if key == "volume": speech_queue.set_volume(float(value))
	if key in ["mic_mode", "mic_device", "mic_sensitivity", "noise_suppression"]:
		if key == "mic_mode": wake.mode = str(value)
		_apply_mic_mode()
	_save_settings()

func clear_cache() -> Dictionary:
	return await bridge.clear_cache()

func set_ai_working(active: bool, state := "AI_WORKING") -> void:
	if active:
		thinking_started.emit()
		avatar.set_thinking(true)
		avatar.set_state(state)
		emotions.set_emotion("focused", 0.55, 20.0)
	else:
		thinking_finished.emit()
		avatar.set_thinking(false)

func _on_backend_ready(info: Dictionary) -> void:
	backend_is_ready = true
	backend_status.emit(true, info)
	_apply_mic_mode()
	if not _startup_done:
		_startup_done = true
		_play_system_sound("startup")
		var phrase := "Загружаюсь. Версия %s. Я стала другой." % _current_version()
		if bool(settings.get("startup_greeting", false)):
			var extra := await _phrase("startup")
			if not extra.is_empty():
				phrase += " " + extra
		say(phrase, "happy", 0.42)

func _current_version() -> String:
	if FileAccess.file_exists(VERSION_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(VERSION_PATH))
		if data is Dictionary:
			var value := str(data.get("numeric", "")).strip_edges()
			if not value.is_empty():
				return value
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0.0"))

func _on_awakened() -> void:
	wake_word_detected.emit()
	emotions.set_emotion("focused", 0.55, 8.0)
	_play_system_sound("wake")
	var phrase := await _phrase("wake_response")
	if not phrase.is_empty(): say(phrase, "focused", 0.42)

func _on_window_opened() -> void:
	avatar.set_listening(true)
	listening_started.emit()

func _on_window_closed() -> void:
	avatar.set_listening(false)
	listening_finished.emit()

func _on_transcript(text: String) -> void:
	if text.strip_edges().is_empty(): return
	transcript_ready.emit(text.strip_edges())

func _on_barge_in() -> void:
	if not bool(settings.get("barge_in", true)): return
	speech_queue.interrupt()
	wake.open_window()

func _on_user_speech_started() -> void:
	if wake.is_window_open() or str(settings.get("mic_mode", "wake_word")) == "continuous":
		avatar.set_listening(true)

func _on_user_speech_finished() -> void:
	if not wake.is_window_open(): avatar.set_listening(false)

func _on_emotion_changed(emotion: String, intensity: float, profile: Dictionary) -> void:
	avatar.set_emotion(emotion, intensity, profile)
	emotion_changed.emit(emotion, intensity)
	if emotion in ["success", "error", "warning"] and intensity >= 0.45:
		var now := Time.get_ticks_msec()
		if now - _last_event_sound_ms >= 5500:
			_last_event_sound_ms = now
			_play_system_sound(emotion)

func _on_speech_started(_item: Dictionary) -> void:
	avatar.set_state("AI_SPEAKING")
	speech_started.emit()

func _on_speech_finished(_item: Dictionary) -> void:
	avatar.set_state("AI_LISTENING" if wake.is_window_open() else "AI_IDLE")
	speech_finished.emit()

func _on_amplitude(value: float) -> void:
	avatar.set_amplitude(value)
	speech_amplitude.emit(value)

func _apply_mic_mode() -> void:
	if not bool(settings.get("enabled", true)):
		bridge.set_mode("off")
		return
	bridge.set_mode(str(settings.get("mic_mode", "wake_word")), _device_value(), _mic_options())

func _mic_options() -> Dictionary:
	return {
		"sensitivity": float(settings.get("mic_sensitivity", 0.5)),
		"noise_suppression": bool(settings.get("noise_suppression", true))
	}

func _device_value() -> Variant:
	var value := int(settings.get("mic_device", -1))
	return null if value < 0 else value

func _phrase(category: String) -> String:
	var remote := await bridge.get_phrase(category)
	if not remote.is_empty(): return remote
	var source: Array = _personality.get(category, [])
	if source.is_empty(): return ""
	var candidates: Array = []
	for item in source:
		var text := str(item.get("text", "")) if item is Dictionary else str(item)
		if not text.is_empty() and text != _last_local_phrase: candidates.append(text)
	if candidates.is_empty():
		for item in source:
			candidates.append(str(item.get("text", "")) if item is Dictionary else str(item))
	var chosen := str(candidates[randi() % candidates.size()])
	_last_local_phrase = chosen
	return chosen

func _play_system_sound(kind: String) -> void:
	if not bool(settings.get("system_sounds", true)): return
	var rate := 24000
	var duration := 0.08
	var freq := 760.0
	var second_freq := 1180.0
	var gain := 0.075
	match kind:
		"startup": duration = 0.13; freq = 520.0; second_freq = 860.0; gain = 0.08
		"wake": duration = 0.07; freq = 920.0; second_freq = 1380.0; gain = 0.065
		"success": duration = 0.075; freq = 880.0; second_freq = 1320.0; gain = 0.055
		"warning": duration = 0.09; freq = 610.0; second_freq = 915.0; gain = 0.052
		"error": duration = 0.09; freq = 430.0; second_freq = 690.0; gain = 0.05
	var frames := int(rate * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / rate
		var env := exp(-t * 26.0)
		var tone := sin(TAU * freq * t) * 0.78 + sin(TAU * second_freq * t) * 0.22
		var sample := int(clampf(tone * env * gain, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	var p := AudioStreamPlayer.new()
	add_child(p)
	p.stream = wav
	p.finished.connect(p.queue_free)
	p.play()

func _load_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null: return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for key in DEFAULTS.keys():
			if parsed.has(key): settings[key] = parsed[key]

func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(settings, "  "))
	settings_changed.emit(settings.duplicate(true))

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
