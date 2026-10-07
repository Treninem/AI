extends SceneTree

class PlanningAI extends AIClient:
	var captured: Array = []
	var response := '{"objective":"probe","steps":["check"],"success_checks":["verified"]}'
	func chat(messages: Array, _temperature: float = 0.2) -> Dictionary:
		captured = messages
		return {"ok": true, "content": response}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var formatter = preload("res://benchmarks/core/failure_diagnostics.gd")
	var diagnostic: Dictionary = formatter.describe({"ok": false, "runtime": "aurora_core", "error": "x".repeat(900), "raw": "private raw", "attempted_models": [{"runtime": "aurora_core_desktop", "error": "transport failure", "http": 0, "transport_result": 13, "model_failure": false, "retryable": true, "failure_scope": "request", "model_path": "private model path"}]})
	assert(not diagnostic.ok and diagnostic.error.length() == 600)
	assert(diagnostic.attempts.size() == 1)
	assert(diagnostic.attempts[0].transport_result == 13 and diagnostic.attempts[0].http == 0)
	assert(diagnostic.attempts[0].retryable and not diagnostic.attempts[0].model_failure)
	assert(not JSON.stringify(diagnostic).contains("private"))
	assert(formatter.describe({"ok": true}).ok)
	var planner := CognitionLayer.new()
	var model := PlanningAI.new()
	planner.setup(model)
	var plan := await planner.make_plan("probe", [], [])
	var desktop := DesktopLocalRuntime.new()
	assert(plan.steps == ["check"])
	assert(desktop._is_strict_structured_request(model.captured))
	assert(not desktop._is_strict_structured_request([{"role": "user", "content": "Explain how planning works in ordinary prose"}]))
	model.response = 'План ниже:\n```json\n{"objective":"tea {safe}","steps":["fill {kettle}","boil water"],"success_checks":["off"]}\n```\nГотово.'
	var wrapped := await planner.make_plan("probe", [], [])
	assert(wrapped.steps == ["fill {kettle}", "boil water"])
	assert(planner.last_plan_diagnostic.status == "valid_plan")
	model.response = 'План: {"objective":"probe","steps":[1],"success_checks":["verified"]}'
	var wrong_shape := await planner.make_plan("probe", [], [])
	assert(wrong_shape.steps.is_empty())
	assert(planner.last_plan_diagnostic.status == "invalid_step_contract")
	model.response = "План словами без JSON."
	var prose := await planner.make_plan("probe", [], [])
	assert(prose.steps.is_empty())
	assert(planner.last_plan_diagnostic.status == "invalid_json_or_plan_contract")
	model.core_runtime.android_runtime.free()
	model.core_runtime.desktop_runtime.free()
	model.core_runtime.free()
	model.free()
	planner.free()
	desktop.free()
	print("AURORA_CORE_BENCHMARK_DIAGNOSTICS_OK bounded=true transport=true private_fields_excluded=true")
	quit(0)
