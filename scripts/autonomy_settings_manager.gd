class_name AutonomySettingsManager
extends Node

signal settings_changed(settings: Dictionary)

const SETTINGS_PATH := "user://autonomy_settings.json"
const DEFAULT_SETTINGS := {
	"master_enabled": true,
	"autonomous_learning": true,
	"autonomous_cycles": true,
	"hot_improvements": true,
	"core_candidates": true,
	"auto_apply_dev_checkout": true
}

var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var coordinator: AuroraAutonomousCoordinator
var core_pipeline: CoreImprovementPipeline
var learning_curator: AuroraLearningCurator
var _binding := false

func _ready() -> void:
	_load()
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	if _binding:
		return
	_binding = true
	for _i in range(180):
		_bind_existing()
		if coordinator != null and core_pipeline != null and learning_curator != null:
			break
		await get_tree().process_frame
	_bind_existing()
	_apply()
	_binding = false

func _bind_existing() -> void:
	var main := get_parent()
	if main == null:
		return
	var node := main.get_node_or_null("AutonomousCoordinator")
	if node is AuroraAutonomousCoordinator:
		coordinator = node
	node = main.get_node_or_null("CoreImprovementPipeline")
	if node is CoreImprovementPipeline:
		core_pipeline = node
	node = main.get_node_or_null("LearningCurator")
	if node is AuroraLearningCurator:
		learning_curator = node

func get_settings() -> Dictionary:
	return settings.duplicate(true)

func set_master_enabled(value: bool) -> void:
	settings["master_enabled"] = value
	_save_apply_emit()

func set_autonomous_learning(value: bool) -> void:
	settings["autonomous_learning"] = value
	_save_apply_emit()

func set_autonomous_cycles(value: bool) -> void:
	settings["autonomous_cycles"] = value
	_save_apply_emit()

func set_hot_improvements(value: bool) -> void:
	settings["hot_improvements"] = value
	_save_apply_emit()

func set_core_candidates(value: bool) -> void:
	settings["core_candidates"] = value
	_save_apply_emit()

func set_auto_apply_dev_checkout(value: bool) -> void:
	settings["auto_apply_dev_checkout"] = value
	_save_apply_emit()

func pause_all() -> void:
	set_master_enabled(false)

func resume_all() -> void:
	set_master_enabled(true)

func status() -> Dictionary:
	var result := get_settings()
	result["coordinator_bound"] = coordinator != null
	result["core_pipeline_bound"] = core_pipeline != null
	result["learning_curator_bound"] = learning_curator != null
	if coordinator != null:
		result["coordinator_running"] = coordinator.running
		result["next_cycle_in_seconds"] = coordinator.time_until_next_cycle()
	if core_pipeline != null:
		result["core_pipeline"] = core_pipeline.status()
	if learning_curator != null:
		result["learning"] = learning_curator.status()
	return result

func _apply() -> void:
	_bind_existing()
	var master := bool(settings.get("master_enabled", true))
	if coordinator != null:
		coordinator.autonomous_enabled = master and bool(settings.get("autonomous_cycles", true))
		coordinator.autonomous_hot_improvements = master and bool(settings.get("hot_improvements", true))
	if core_pipeline != null:
		core_pipeline.autonomous_core_candidates = master and bool(settings.get("core_candidates", true))
		core_pipeline.auto_apply_dev_checkout = master and bool(settings.get("auto_apply_dev_checkout", true))
	if learning_curator != null:
		learning_curator.enabled = master and bool(settings.get("autonomous_learning", true))

func _save_apply_emit() -> void:
	_save()
	_apply()
	settings_changed.emit(get_settings())

func _load() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	for key in DEFAULT_SETTINGS.keys():
		if parsed.has(key):
			settings[key] = bool(parsed.get(key, DEFAULT_SETTINGS[key]))

func _save() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	var data := settings.duplicate(true)
	data["updated_at"] = Time.get_datetime_string_from_system(true)
	file.store_string(JSON.stringify(data, "  "))
	file.close()
