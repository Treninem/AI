class_name WindowsStartupCoordinator
extends Node

var _initialized := false

func _ready() -> void:
	if OS.get_name() != "Windows":
		return
	call_deferred("_stabilize_startup")

func _stabilize_startup() -> void:
	if _initialized:
		return
	_initialized = true
	var main := get_parent()
	if main == null:
		return
	# Setup modules stay fully functional, but they no longer fight for focus on startup.
	# The user opens them from Settings or from an explicit recovery action.
	for node_name in ["ModelSetup", "VoiceSetup"]:
		var setup := main.get_node_or_null(node_name)
		if setup != null:
			if _has_property(setup, "shown"):
				setup.set("shown", true)
			var popup = setup.get("popup")
			if popup is PopupPanel and popup.visible:
				popup.hide()

	var update := main.get_node_or_null("UpdateOverlay")
	if update != null:
		var update_popup = update.get("popup")
		if update_popup is PopupPanel and update_popup.visible:
			update_popup.hide()

func _has_property(object: Object, property_name: String) -> bool:
	for info in object.get_property_list():
		if str(info.get("name", "")) == property_name:
			return true
	return false
