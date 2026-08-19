class_name AuroraWindowsStartupCoordinator
extends Node

func _ready() -> void:
	if OS.get_name() != "Windows":
		return
	call_deferred("_stabilize_startup")

func _stabilize_startup() -> void:
	for _i in range(3):
		await get_tree().process_frame
	var main := get_parent()
	if main == null:
		return

	# Setup wizards remain fully available from Settings, but they no longer
	# compete for the screen during application startup.
	var model_setup := main.get_node_or_null("ModelSetup")
	if model_setup != null:
		model_setup.set("shown", true)
		var popup = model_setup.get("popup")
		if popup is PopupPanel:
			popup.hide()

	var voice_setup := main.get_node_or_null("VoiceSetup")
	if voice_setup != null:
		voice_setup.set("shown", true)
		var popup = voice_setup.get("popup")
		if popup is PopupPanel:
			popup.hide()

	# Keep update UI inside the main header if an older overlay created a
	# floating button before the header was available.
	var header := main.find_child("MainHeaderActions", true, false) as HBoxContainer
	if header != null:
		var update_overlay := main.get_node_or_null("UpdateOverlay")
		if update_overlay != null:
			var button = update_overlay.get("button")
			if button is Button and button.get_parent() != header:
				var old_parent := button.get_parent()
				if old_parent != null:
					old_parent.remove_child(button)
				header.add_child(button)
