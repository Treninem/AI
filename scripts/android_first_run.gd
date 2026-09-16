class_name AndroidFirstRun
extends Node

var provisioning := false
var last_result: Dictionary = {}

func _ready() -> void:
	if OS.get_name() != "Android":
		return
	# No first-run model wizard. AuroraFox ships its own Core weights and quietly
	# provisions the signed APK asset into private app storage.
	call_deferred("_ensure_bundled_core")

func _ensure_bundled_core() -> void:
	if provisioning:
		return
	provisioning = true
	await get_tree().process_frame
	last_result = AuroraBundledCoreModel.ensure_android_private_copy()
	provisioning = false
	if not bool(last_result.get("ok", false)):
		push_error("AuroraFox bundled Core provisioning failed: %s" % str(last_result.get("error", "unknown error")))
		return
	var main := get_parent()
	if main != null:
		var status := main.get_node_or_null("CoreStatusCoordinator")
		if status != null and status.has_method("refresh_now"):
			status.call_deferred("refresh_now")

func status() -> Dictionary:
	return {
		"provisioning": provisioning,
		"ready": FileAccess.file_exists(AuroraBundledCoreModel.ACTIVE_MODEL),
		"last_result": last_result.duplicate(true)
	}
