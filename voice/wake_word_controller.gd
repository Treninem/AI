class_name AuroraWakeWordController
extends Node

signal awakened
signal listening_window_opened
signal listening_window_closed

var bridge: AuroraVoiceBridge
var mode := "wake_word"
var conversation_window := 25.0
var _window_left := 0.0

func setup(p_bridge: AuroraVoiceBridge) -> void:
	bridge = p_bridge
	bridge.wake_detected.connect(_on_wake)
	set_process(true)

func set_mode(value: String) -> void:
	mode = value
	if bridge != null: bridge.set_mode(mode)
	if mode not in ["wake_word", "continuous"]: close_window()

func open_window(seconds := -1.0) -> void:
	_window_left = conversation_window if seconds < 0.0 else seconds
	listening_window_opened.emit()

func close_window() -> void:
	if _window_left <= 0.0: return
	_window_left = 0.0
	listening_window_closed.emit()

func is_window_open() -> bool:
	return _window_left > 0.0 or mode == "continuous"

func _on_wake(_text: String) -> void:
	open_window()
	awakened.emit()

func _process(delta: float) -> void:
	if mode != "wake_word" or _window_left <= 0.0: return
	_window_left -= delta
	if _window_left <= 0.0: close_window()
