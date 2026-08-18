class_name AuroraAndroidMicMonitor
extends Node

signal wake_detected(text: String)
signal transcript_ready(text: String)
signal barge_in(text: String)
signal user_speech_started
signal user_speech_finished
signal microphone_error(message: String)

const TARGET_RATE := 16000
const MIN_SPEECH_SEC := 0.24
const END_SILENCE_SEC := 0.62
const MAX_SEGMENT_SEC := 15.0

var runtime := AndroidLocalRuntime.new()
var player: AudioStreamPlayer
var capture: AudioEffectCapture
var mode := "off"
var sensitivity := 0.5
var noise_suppression := true
var conversation_until := 0.0
var conversation_window := 25.0

var _source_rate := 48000
var _speech := false
var _started_during_tts := false
var _tts_text_at_start := ""
var _speech_time := 0.0
var _silence_time := 0.0
var _noise_floor := 0.004
var _segment := PackedFloat32Array()
var _busy_stt := false

func _ready() -> void:
	if OS.get_name() == "Android":
		OS.request_permission("android.permission.RECORD_AUDIO")
	add_child(runtime)
	_setup_capture()
	set_process(true)

func set_mode(value: String, p_sensitivity := 0.5, p_noise_suppression := true) -> void:
	mode = value
	sensitivity = clampf(p_sensitivity, 0.0, 1.0)
	noise_suppression = p_noise_suppression
	if mode in ["off", "push_to_talk"]:
		_reset_segment()
		if player != null: player.stop()
	elif player != null and not player.playing:
		player.play()

func open_conversation_window(seconds := 25.0) -> void:
	conversation_window = seconds
	conversation_until = Time.get_unix_time_from_system() + seconds

func _setup_capture() -> void:
	var bus_name := "AuroraFoxAndroidMic"
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_mute(idx, true)
	capture = null
	for i in range(AudioServer.get_bus_effect_count(idx)):
		var effect := AudioServer.get_bus_effect(idx, i)
		if effect is AudioEffectCapture:
			capture = effect
			break
	if capture == null:
		capture = AudioEffectCapture.new()
		capture.buffer_length = 2.0
		AudioServer.add_bus_effect(idx, capture)
	_source_rate = int(AudioServer.get_mix_rate())
	player = AudioStreamPlayer.new()
	player.stream = AudioStreamMicrophone.new()
	player.bus = bus_name
	add_child(player)

func _process(_delta: float) -> void:
	if OS.get_name() != "Android" or mode in ["off", "push_to_talk"] or capture == null or _busy_stt:
		return
	var available := capture.get_frames_available()
	if available <= 0: return
	var frames := capture.get_buffer(available)
	if frames.is_empty(): return
	_process_frames(frames)

func _process_frames(frames: PackedVector2Array) -> void:
	var mono := PackedFloat32Array()
	mono.resize(frames.size())
	var energy := 0.0
	for i in range(frames.size()):
		var v := (frames[i].x + frames[i].y) * 0.5
		mono[i] = v
		energy += v * v
	var rms := sqrt(energy / maxf(1.0, float(frames.size())))
	var dt := float(frames.size()) / maxf(1.0, float(_source_rate))
	if not _speech:
		_noise_floor = lerpf(_noise_floor, minf(rms, 0.025), 0.003)
	var threshold := maxf(0.006, _noise_floor * lerpf(3.4, 1.8, sensitivity))
	var voiced := rms >= threshold

	if voiced and not _speech:
		_speech = true
		_started_during_tts = AuroraVoice.speech_queue.is_speaking()
		_tts_text_at_start = str(AuroraVoice.speech_queue.current_item.get("text", "")) if _started_during_tts else ""
		_speech_time = 0.0
		_silence_time = 0.0
		_segment = PackedFloat32Array()
		user_speech_started.emit()

	if _speech:
		_append_samples(mono)
		_speech_time += dt
		if voiced:
			_silence_time = 0.0
		else:
			_silence_time += dt
		if (_speech_time >= MIN_SPEECH_SEC and _silence_time >= END_SILENCE_SEC) or _speech_time >= MAX_SEGMENT_SEC:
			_finish_segment()

func _append_samples(samples: PackedFloat32Array) -> void:
	var old := _segment.size()
	_segment.resize(old + samples.size())
	for i in range(samples.size()):
		var v := samples[i]
		if noise_suppression and absf(v) < _noise_floor * 0.65: v *= 0.25
		_segment[old + i] = v

func _finish_segment() -> void:
	var samples := _segment
	var began_during_tts := _started_during_tts
	var spoken_at_start := _tts_text_at_start
	_reset_segment()
	user_speech_finished.emit()
	if samples.size() < int(_source_rate * MIN_SPEECH_SEC): return
	_busy_stt = true
	var resampled := _resample(samples, _source_rate, TARGET_RATE)
	var path := "user://aurorafox_android_voice_input.wav"
	if not _write_wav16(path, resampled, TARGET_RATE):
		_busy_stt = false
		microphone_error.emit("Не удалось сохранить временный голосовой буфер")
		return
	var result := await runtime.transcribe("", ProjectSettings.globalize_path(path), "ru")
	_busy_stt = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not result.get("ok", false):
		microphone_error.emit(str(result.get("error", "Ошибка распознавания речи")))
		return
	var text := str(result.get("text", "")).strip_edges()
	if text.is_empty(): return
	var now := Time.get_unix_time_from_system()
	if began_during_tts:
		if _similarity(text, spoken_at_start) < 0.62:
			open_conversation_window(conversation_window)
			barge_in.emit(text)
		return
	if mode == "wake_word" and now > conversation_until:
		if _has_wake(text):
			open_conversation_window(conversation_window)
			wake_detected.emit(text)
		return
	if mode == "continuous" or now <= conversation_until:
		open_conversation_window(conversation_window)
		transcript_ready.emit(text)

func _reset_segment() -> void:
	_speech = false
	_started_during_tts = false
	_tts_text_at_start = ""
	_speech_time = 0.0
	_silence_time = 0.0
	_segment = PackedFloat32Array()

func _has_wake(text: String) -> bool:
	var q := _normalize(text)
	for word in ["fox", "фокс", "лиса"]:
		if (" " + q + " ").contains(" " + word + " "): return true
	return q.begins_with("эй фокс") or q.begins_with("эй лиса")

func _similarity(a: String, b: String) -> float:
	var aa := _normalize(a).split(" ", false)
	var bb := _normalize(b).split(" ", false)
	if aa.is_empty() or bb.is_empty(): return 0.0
	var common := 0
	for word in aa:
		if word in bb: common += 1
	return float(common * 2) / float(aa.size() + bb.size())

func _normalize(text: String) -> String:
	var out := ""
	for i in range(text.length()):
		var c := text.substr(i, 1).to_lower()
		var u := c.unicode_at(0)
		var latin_or_digit := (u >= 48 and u <= 57) or (u >= 97 and u <= 122)
		var cyrillic := u >= 0x0400 and u <= 0x052f
		out += c if latin_or_digit or cyrillic else " "
	return " ".join(out.split(" ", false))

func _resample(input: PackedFloat32Array, src_rate: int, dst_rate: int) -> PackedFloat32Array:
	if src_rate == dst_rate: return input
	var count := maxi(1, int(round(float(input.size()) * dst_rate / src_rate)))
	var out := PackedFloat32Array()
	out.resize(count)
	var scale := float(src_rate) / dst_rate
	for i in range(count):
		var pos := float(i) * scale
		var a := mini(int(floor(pos)), input.size() - 1)
		var b := mini(a + 1, input.size() - 1)
		out[i] = lerpf(input[a], input[b], pos - floor(pos))
	return out

func _write_wav16(path: String, samples: PackedFloat32Array, rate: int) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return false
	f.big_endian = false
	var pcm_bytes := samples.size() * 2
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + pcm_bytes)
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(rate)
	f.store_32(rate * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(pcm_bytes)
	for v in samples:
		f.store_16(int(clampf(v, -1.0, 1.0) * 32767.0) & 0xffff)
	f.close()
	return true
