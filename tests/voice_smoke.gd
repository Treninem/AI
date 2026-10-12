extends SceneTree


# Run the actual VoiceManager startup policy without starting its backend,
# accessing the microphone, or modifying user:// voice preferences.
class StartupVoiceProbe:
	extends "res://voice/voice_manager.gd"

	var spoken: Array[String] = []
	var startup_sounds := 0

	func _apply_mic_mode() -> void:
		pass

	func _play_system_sound(kind: String) -> void:
		if kind == "startup":
			startup_sounds += 1

	func _phrase(_category: String) -> String:
		return "Проверочная фраза."

	func say(text: String, emotion := "auto", intensity := -1.0, options: Dictionary = {}) -> void:
		spoken.append(text)

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
		LocalModelManager.new(),
		AndroidFirstRun.new(),
		MobileUIAdapter.new(),
		FileIntelligenceClient.new(),
		AttachmentManager.new(),
		AuroraFileSetupWizard.new(),
		AndroidFileToolBridge.new(),
		ProjectAccessStore.new(),
		ProjectIndexClient.new(),
		ProjectIndexToolBridge.new(),
		TrustedProjectSandboxBridge.new(),
		WindowsTrustedProjectBridge.new(),
		DeveloperRuntimeManager.new(),
		DeveloperRuntimeToolBridge.new(),
		RuntimeExtensionManager.new(),
		SelfImprovementOverlay.new(),
	]
	for node in nodes:
		if node == null:
			push_error("AuroraFox subsystem class failed to instantiate")
			quit(2)
			return
		node.free()
	# AuroraSettingsOverlay intentionally depends on project autoloads AuroraVoice/AuroraUpdate.
	# It is validated by the full Godot project import step, not this standalone --script smoke.
	call_deferred("_verify_startup_greeting")


func _verify_startup_greeting() -> void:
	var silent := StartupVoiceProbe.new()
	silent.settings["startup_greeting"] = false
	await silent._on_backend_ready({})
	await silent._on_backend_ready({})
	if not silent.spoken.is_empty() or silent.startup_sounds != 1:
		push_error("VOICE_STARTUP_OPT_IN_FAIL: disabled greeting spoke, or reconnect retriggered startup")
		quit(3)
		return
	var enabled := StartupVoiceProbe.new()
	enabled.settings["startup_greeting"] = true
	await enabled._on_backend_ready({})
	await enabled._on_backend_ready({})
	if enabled.spoken.size() != 1 or not enabled.spoken[0].contains("Проверочная фраза.") or enabled.startup_sounds != 1:
		push_error("VOICE_STARTUP_OPT_IN_FAIL: enabled greeting missing or repeated")
		quit(4)
		return
	print("VOICE_STARTUP_OPT_IN_PASS")
	print("AURORA_VOICE_GODOT_SMOKE_OK")
	quit(0)
