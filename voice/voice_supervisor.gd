class_name AuroraVoiceSupervisor
extends Node

var _restart_timer := 3.0

func _ready() -> void:
	await get_tree().process_frame
	AuroraVoice.bridge.user_speech_started.connect(_on_user_speech_started)
	AuroraVoice.bridge.user_speech_finished.connect(_on_user_speech_finished)
	AuroraVoice.bridge.barge_in.connect(_on_barge_in)
	set_process(true)

func _process(delta: float) -> void:
	if OS.get_name() != "Windows" or AuroraVoice.backend_is_ready:
		return
	_restart_timer -= delta
	if _restart_timer > 0.0:
		return
	_restart_timer = 4.0
	var pid := AuroraVoice.bridge.backend_pid
	if pid <= 0 or not OS.is_process_running(pid):
		AuroraVoice.bridge.call("_start_backend_if_installed")

func _on_user_speech_started() -> void:
	if bool(AuroraVoice.settings.get("barge_in", true)) and AuroraVoice.speech_queue.is_speaking():
		AuroraVoice.speech_queue.set_ducked(true)

func _on_user_speech_finished() -> void:
	if AuroraVoice.speech_queue.is_speaking():
		AuroraVoice.speech_queue.set_ducked(false)

func _on_barge_in() -> void:
	# VoiceManager performs the actual interrupt after echo/STT verification.
	AuroraVoice.speech_queue.set_ducked(false)
