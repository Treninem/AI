class_name AuroraEvolutionFoundationAdapter
extends RefCounted

var coordinator
var improver
var extensions
var memory
var knowledge
var core_pipeline
var autonomy_settings
var sandbox

func bind(
	coordinator_value,
	improver_value,
	extensions_value,
	memory_value,
	knowledge_value,
	core_pipeline_value = null,
	autonomy_settings_value = null,
	sandbox_value = null
) -> void:
	coordinator = coordinator_value
	improver = improver_value
	extensions = extensions_value
	memory = memory_value
	knowledge = knowledge_value
	core_pipeline = core_pipeline_value
	autonomy_settings = autonomy_settings_value
	sandbox = sandbox_value

func inspect() -> Dictionary:
	var missing: Array[String] = []
	_require_method(missing, "coordinator", coordinator, "synchronize_all")
	_require_method(missing, "improver", improver, "propose_improvement")
	_require_method(missing, "improver", improver, "run_mutation_tournament")
	_require_method(missing, "extensions", extensions, "activate_staged")
	_require_method(missing, "memory", memory, "remember")
	_require_method(missing, "knowledge", knowledge, "search")
	if core_pipeline != null:
		_require_method(missing, "core_pipeline", core_pipeline, "status")
	if autonomy_settings != null:
		_require_method(missing, "autonomy_settings", autonomy_settings, "get_settings")
	if sandbox != null:
		_require_method(missing, "sandbox", sandbox, "snapshot")
		_require_method(missing, "sandbox", sandbox, "rollback")
	return {
		"ok": missing.is_empty(),
		"missing": missing,
		"core_pipeline_bound": core_pipeline != null,
		"autonomy_settings_bound": autonomy_settings != null,
		"sandbox_bound": sandbox != null
	}

func current_autonomy_settings() -> Dictionary:
	if autonomy_settings != null and autonomy_settings.has_method("get_settings"):
		var value = autonomy_settings.get_settings()
		if value is Dictionary:
			return value
	return {"master_enabled": true}

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
