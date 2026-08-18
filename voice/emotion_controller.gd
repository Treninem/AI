class_name AuroraEmotionController
extends Node

signal emotion_changed(emotion: String, intensity: float, profile: Dictionary)

const CONFIG_PATH := "res://voice/config/emotions.json"
var profiles: Dictionary = {}
var current_emotion := "neutral"
var current_intensity := 0.45
var _return_timer := 0.0

func _ready() -> void:
	profiles = _load_json(CONFIG_PATH)
	set_process(true)

func _process(delta: float) -> void:
	if current_emotion != "neutral":
		_return_timer -= delta
		if _return_timer <= 0.0:
			set_emotion("neutral", 0.4, 0.0)

func analyze(text: String) -> Dictionary:
	var q := text.to_lower()
	var emotion := "neutral"
	var intensity := 0.45
	if _has_any(q, ["внимание", "предупреж", "опасн", "⚠"]):
		emotion = "warning"; intensity = 0.78
	elif _has_any(q, ["ошибк", "не удалось", "сломал", "не работает", "failed"]):
		emotion = "error"; intensity = 0.72
	elif _has_any(q, ["готово", "успеш", "исправил", "всё работает", "запускается"]):
		emotion = "success"; intensity = 0.76
	elif _has_any(q, ["хм", "проверя", "разбер", "🤔"]):
		emotion = "thinking"; intensity = 0.58
	elif _has_any(q, ["не хватает контекст", "уточни", "не до конца"]):
		emotion = "confused"; intensity = 0.58
	elif _has_any(q, ["😔", "сожале", "груст"]):
		emotion = "sad"; intensity = 0.6
	elif _has_any(q, ["😄", "супер!", "отлично!", "вау"]):
		emotion = "excited"; intensity = 0.75
	elif _has_any(q, ["🦊", "хвост", "лисий"]):
		emotion = "playful"; intensity = 0.62
	elif _has_any(q, ["😊", "❤️", "рад", "приятн"]):
		emotion = "happy"; intensity = 0.62
	return {"emotion": emotion, "intensity": intensity, "profile": get_profile(emotion)}

func set_emotion(emotion: String, intensity := 0.5, hold_seconds := 5.0) -> void:
	if not profiles.has(emotion): emotion = "neutral"
	current_emotion = emotion
	current_intensity = clampf(intensity, 0.0, 1.0)
	_return_timer = hold_seconds
	emotion_changed.emit(current_emotion, current_intensity, get_profile(current_emotion))

func get_profile(emotion: String) -> Dictionary:
	return profiles.get(emotion, profiles.get("neutral", {})).duplicate(true)

func _has_any(text: String, markers: Array) -> bool:
	for marker in markers:
		if text.contains(str(marker)): return true
	return false

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var value = JSON.parse_string(f.get_as_text())
	return value if value is Dictionary else {}
