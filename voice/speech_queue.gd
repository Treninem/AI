class_name AuroraSpeechQueue
extends Node

signal speech_started(item: Dictionary)
signal speech_finished(item: Dictionary)
signal speech_amplitude(value: float)
signal queue_empty

var bridge: AuroraVoiceBridge
var player := AudioStreamPlayer.new()
var items: Array = []
var running := false
var paused := false
var generation := 0
var current_item: Dictionary = {}
var _amplitude: Array = []
var _amp_index := 0
var _amp_timer := 0.0
var _next_id := 1
var volume := 0.86

func _ready() -> void:
	add_child(player)
	player.finished.connect(_on_player_finished)
	set_process(true)

func setup(p_bridge: AuroraVoiceBridge) -> void:
	bridge = p_bridge

func enqueue(text: String, emotion := "neutral", intensity := 0.5, options: Dictionary = {}) -> void:
	for chunk in _split_sentences(text):
		items.append({
			"id": _next_id,
			"text": chunk,
			"emotion": emotion,
			"intensity": intensity,
			"options": options.duplicate(true),
			"prepared": false,
			"preparing": false,
			"result": {}
		})
		_next_id += 1
	if not running: _pump()

func play() -> void:
	paused = false
	player.stream_paused = false
	if not running and not items.is_empty(): _pump()

func pause() -> void:
	paused = true
	player.stream_paused = true

func resume() -> void:
	play()

func stop() -> void:
	generation += 1
	items.clear()
	player.stop()
	player.pitch_scale = 1.0
	running = false
	current_item = {}
	bridge.set_tts_state(false)
	speech_amplitude.emit(0.0)

func clear() -> void:
	items.clear()

func interrupt() -> void:
	stop()

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	player.volume_db = linear_to_db(maxf(volume, 0.001))

func is_speaking() -> bool:
	return running and player.playing

func _pump() -> void:
	if paused or items.is_empty():
		if items.is_empty(): queue_empty.emit()
		return
	running = true
	var my_generation := generation
	current_item = items.pop_front()

	# If the prefetch coroutine is still running, wait for that exact result instead of
	# launching a second synthesis request for the same sentence.
	while bool(current_item.get("preparing", false)) and my_generation == generation:
		await get_tree().process_frame
	if my_generation != generation: return

	var result: Dictionary = current_item.get("result", {})
	if not bool(current_item.get("prepared", false)):
		result = await bridge.synthesize(str(current_item.text), str(current_item.emotion), float(current_item.intensity), current_item.options)
	if my_generation != generation: return
	if not result.get("ok", false):
		running = false
		current_item = {}
		_pump()
		return
	var path := str(result.get("path", ""))
	var stream := AudioStreamWAV.load_from_file(path)
	if stream == null:
		running = false
		current_item = {}
		_pump()
		return
	current_item["meta"] = result
	_amplitude = result.get("amplitude", [])
	_amp_index = 0
	_amp_timer = 0.0
	player.stream = stream
	player.pitch_scale = _playback_pitch(result, current_item.get("options", {}))
	set_volume(volume)
	bridge.set_tts_state(true, str(current_item.get("text", "")))
	player.play()
	speech_started.emit(current_item)
	_prefetch_next(my_generation)

func _playback_pitch(result: Dictionary, options: Dictionary) -> float:
	var engine := str(result.get("engine", ""))
	if OS.get_name() == "Android" and engine.begins_with("sherpa-onnx-piper"):
		# Android's license-safe Russian fallback is intentionally brightened a little.
		# Keep the shift subtle so intelligibility and timing remain natural.
		var requested := 1.0 + float(options.get("pitch", 0.0))
		return clampf(requested * 1.055, 1.0, 1.14)
	return 1.0

func _prefetch_next(my_generation: int) -> void:
	if items.is_empty() or my_generation != generation: return
	var next: Dictionary = items[0]
	if bool(next.get("prepared", false)) or bool(next.get("preparing", false)): return
	next["preparing"] = true
	var result := await bridge.synthesize(str(next.text), str(next.emotion), float(next.intensity), next.options)
	if my_generation != generation: return
	next["result"] = result
	next["prepared"] = result.get("ok", false)
	next["preparing"] = false

func _on_player_finished() -> void:
	var finished := current_item
	bridge.set_tts_state(false, str(finished.get("text", "")))
	speech_amplitude.emit(0.0)
	player.pitch_scale = 1.0
	current_item = {}
	running = false
	speech_finished.emit(finished)
	_pump()

func _process(delta: float) -> void:
	if not is_speaking() or _amplitude.is_empty(): return
	_amp_timer += delta
	var duration := float(current_item.get("meta", {}).get("duration", 1.0))
	var step := duration / maxf(float(_amplitude.size()), 1.0)
	while _amp_timer >= step and _amp_index < _amplitude.size():
		_amp_timer -= step
		speech_amplitude.emit(float(_amplitude[_amp_index]))
		_amp_index += 1

func _split_sentences(text: String) -> Array:
	var clean := text.strip_edges()
	if clean.is_empty(): return []
	var out: Array = []
	var buf := ""
	var in_code := false
	var i := 0
	while i < clean.length():
		if i + 2 < clean.length() and clean.substr(i, 3) == "```":
			in_code = not in_code
			buf += "```"
			i += 3
			continue
		var c := clean[i]
		buf += c
		if not in_code and c in [".", "!", "?", "…"] and buf.length() >= 18:
			out.append(buf.strip_edges())
			buf = ""
		elif buf.length() >= 260 and not in_code:
			out.append(buf.strip_edges())
			buf = ""
		i += 1
	if not buf.strip_edges().is_empty(): out.append(buf.strip_edges())
	return out
