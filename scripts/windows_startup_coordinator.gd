class_name AuroraWindowsStartupCoordinator
extends Node

func _ready() -> void:
	if OS.get_name() != "Windows":
		return
	call_deferred("_stabilize_startup")

func _stabilize_startup() -> void:
	for _i in range(3):
		await get_tree().process_frame
	var main: Node = get_parent()
	if main == null:
		return

	# Normal users never see model/provider setup. AuroraFox ships a complete
	# Core and starts warming it as soon as the main window is available.
	var model_setup: Node = main.get_node_or_null("ModelSetup")
	if model_setup != null:
		model_setup.set("shown_once", true)
		var model_popup: Variant = model_setup.get("popup")
		if model_popup is PopupPanel:
			(model_popup as PopupPanel).hide()

	var voice_setup: Node = main.get_node_or_null("VoiceSetup")
	if voice_setup != null:
		voice_setup.set("shown", true)
		var voice_popup: Variant = voice_setup.get("popup")
		if voice_popup is PopupPanel:
			(voice_popup as PopupPanel).hide()

	var ai_value = main.get("ai")
	if ai_value is AIClient:
		call_deferred("_warm_core", ai_value)

	# Keep update UI inside the main header if an older overlay created a
	# floating button before the header was available.
	var header := main.find_child("MainHeaderActions", true, false) as HBoxContainer
	if header != null:
		var update_overlay: Node = main.get_node_or_null("UpdateOverlay")
		if update_overlay != null:
			var button_value: Variant = update_overlay.get("button")
			if button_value is Button:
				var button := button_value as Button
				if button.get_parent() != header:
					var old_parent: Node = button.get_parent()
					if old_parent != null:
						old_parent.remove_child(button)
					header.add_child(button)

func _warm_core(ai: AIClient) -> void:
	var result: Dictionary = await ai.warmup()
	if not bool(result.get("ok", false)):
		# Do not interrupt startup with setup/error dialogs. The installed-package
		# CI guarantees the Core assets; a damaged local install can still be
		# repaired from Settings or by reinstalling the current release.
		push_warning("AuroraFox Core warmup deferred: %s" % str(result.get("error", "runtime not ready")))
		return
	var main: Node = get_parent()
	if main != null:
		var status := main.get_node_or_null("CoreStatusCoordinator")
		if status != null and status.has_method("refresh_now"):
			status.call_deferred("refresh_now")
