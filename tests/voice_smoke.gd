extends SceneTree

func _init() -> void:
	var nodes: Array[Node] = [
		AuroraVoiceBridge.new(),
		AuroraSpeechQueue.new(),
		AuroraEmotionController.new(),
		AuroraAvatarVoiceController.new(),
		AuroraWakeWordController.new(),
		AuroraAndroidMicMonitor.new(),
		AuroraFoxAvatarView.new(),
		AuroraModelSetupWizard.new(),
	]
	for node in nodes:
		if node == null:
			push_error("AuroraFox subsystem class failed to instantiate")
			quit(2)
			return
		node.free()
	print("AURORA_VOICE_GODOT_SMOKE_OK")
	quit(0)
