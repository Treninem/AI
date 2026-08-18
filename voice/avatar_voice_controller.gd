class_name AuroraAvatarVoiceController
extends Node

signal visual_state_changed(state: String)

var view: AuroraFoxAvatarView
var current_state := "AI_IDLE"

func bind(p_view: AuroraFoxAvatarView) -> void:
	view = p_view

func set_emotion(emotion: String, intensity: float, profile: Dictionary) -> void:
	if view != null: view.set_emotion(emotion, intensity, profile)

func set_amplitude(value: float) -> void:
	if view != null: view.set_amplitude(value)

func set_listening(active: bool) -> void:
	if view != null: view.set_listening(active)
	set_state("AI_LISTENING" if active else "AI_IDLE")

func set_thinking(active: bool) -> void:
	if view != null: view.set_thinking(active)
	set_state("AI_WORKING" if active else "AI_IDLE")

func set_state(state: String) -> void:
	if current_state == state: return
	current_state = state
	visual_state_changed.emit(current_state)
