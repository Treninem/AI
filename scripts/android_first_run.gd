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
	var main := get_parent()
	var ai_value = main.get("ai") if main != null else null
	if ai_value is AIClient:
		# Never copy/hash the 1.28 GiB bundled GGUF on the scene thread.
		# Share AIClient's single worker with first real chat requests so there
		# cannot be two concurrent writers to the same private model file.
		last_result = await ai_value.core_runtime.android_runtime.ensure_bundled_model_ready()
	else:
		last_result = {"ok": false, "error": "Android Core provisioning runtime is not ready"}
	provisioning = false
	if not bool(last_result.get("ok", false)):
		push_error("AuroraFox bundled Core provisioning failed: %s" % str(last_result.get("error", "unknown error")))
		return
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
