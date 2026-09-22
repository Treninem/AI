extends Node

const InstalledProductionKnowledgePackSmokeScript = preload("res://scripts/installed_production_knowledge_pack_smoke.gd")
const PACK_ROOT := "user://android-production-pack"
const REPORT_PATH := "user://android-production-knowledge.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var report_path := ProjectSettings.globalize_path(REPORT_PATH)
	var pack_root := ProjectSettings.globalize_path(PACK_ROOT)
	var result: Dictionary = InstalledProductionKnowledgePackSmokeScript.new().run(report_path, pack_root)
	if not bool(result.get("ok", false)):
		push_error(str(result.get("error", "Android production Knowledge Pack acceptance failed")))
	get_tree().quit(int(result.get("exit_code", 1)))
