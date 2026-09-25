class_name AuroraEvolutionFoundationAdapter
extends RefCounted

var coordinator
var improver
var extensions
var memory
var knowledge
var core_pipeline
var autonomy_settings
var update_guard
var sandbox

func bind(
	coordinator_value,
	improver_value,
	extensions_value,
	memory_value,
	knowledge_value,
	core_pipeline_value = null,
	autonomy_settings_value = null,
	update_guard_value = null,
	sandbox_value = null
) -> void:
	coordinator = coordinator_value
	improver = improver_value
	extensions = extensions_value
	memory = memory_value
	knowledge = knowledge_value
	core_pipeline = core_pipeline_value
	autonomy_settings = autonomy_settings_value
	update_guard = update_guard_value
	sandbox = sandbox_value

func inspect() -> Dictionary:
	var missing: Array[String] = []
	_require_method(missing, "coordinator", coordinator, "synchronize_all")
	_require_method(missing, "improver", improver, "propose_improvement")
	_require_method(missing, "improver", improver, "run_mutation_tournament")
	_require_method(missing, "extensions", extensions, "activate_staged")
	_require_method(missing, "extensions", extensions, "deactivate")
	_require_method(missing, "memory", memory, "remember")
	_require_method(missing, "memory", memory, "retrieve")
	_require_method(missing, "knowledge", knowledge, "search")
	_require_method(missing, "autonomy_settings", autonomy_settings, "get_settings")
	_require_method(missing, "update_guard", update_guard, "status")
	_require_method(missing, "sandbox", sandbox, "snapshot")
	_require_method(missing, "sandbox", sandbox, "rollback")
	if core_pipeline != null:
		_require_method(missing, "core_pipeline", core_pipeline, "status")
	return {
		"ok": missing.is_empty(),
		"missing": missing,
		"core_pipeline_bound": core_pipeline != null,
		"autonomy_settings_bound": autonomy_settings != null,
		"update_guard_bound": update_guard != null,
		"sandbox_bound": sandbox != null
	}

func current_autonomy_settings() -> Dictionary:
	if autonomy_settings == null or not autonomy_settings.has_method("get_settings"):
		return {"master_enabled": false, "unavailable": true}
	var value = autonomy_settings.get_settings()
	if value is Dictionary:
		return value
	return {"master_enabled": false, "invalid": true}

func update_gate_status() -> Dictionary:
	if update_guard == null or not update_guard.has_method("status"):
		return {"ok": false, "paused": true, "reason": "UpdateAutonomyGuard is unavailable"}
	var value = update_guard.status()
	if not value is Dictionary:
		return {"ok": false, "paused": true, "reason": "UpdateAutonomyGuard returned invalid status"}
	var state: Dictionary = value
	if not bool(state.get("updater_bound", false)):
		return {"ok": false, "paused": true, "reason": "UpdateAutonomyGuard is not bound to updater", "status": state}
	var paused := bool(state.get("paused_hot_improvements", false)) or bool(state.get("paused_core_candidates", false))
	if paused:
		return {
			"ok": false,
			"paused": true,
			"reason": str(state.get("reason", "update activity paused autonomy")),
			"status": state
		}
	return {"ok": true, "paused": false, "status": state}

func core_status() -> Dictionary:
	if core_pipeline == null or not core_pipeline.has_method("status"):
		return {"ok": false, "available": false}
	var value = core_pipeline.status()
	if value is Dictionary:
		var result: Dictionary = value.duplicate(true)
		result["available"] = true
		return result
	return {"ok": false, "available": true, "error": "invalid core pipeline status"}

func _require_method(missing: Array[String], label: String, instance, method: String) -> void:
	if instance == null:
		missing.append("%s:null" % label)
	elif not instance.has_method(method):
		missing.append("%s:%s" % [label, method])
