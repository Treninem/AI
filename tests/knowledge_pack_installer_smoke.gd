extends SceneTree

const InstalledSmokeScript = preload("res://scripts/installed_knowledge_pack_smoke.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var result_path := OS.get_environment("AURORAFOX_KNOWLEDGE_SMOKE_RESULT").strip_edges()
	var result: Dictionary = InstalledSmokeScript.new().run(result_path)
	if not bool(result.get("ok", false)):
		push_error(str(result.get("error", "installed knowledge smoke failed")))
	quit(int(result.get("exit_code", 1)))
