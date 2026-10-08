extends SceneTree

class PlanningAI extends AIClient:
	var captured: Array = []
	var response := '{"objective":"probe","steps":["check"],"success_checks":["verified"]}'
	func chat(messages: Array, _temperature: float = 0.2) -> Dictionary:
		captured = messages
		return {"ok": true, "content": response}

class PayloadProbe extends DesktopLocalRuntime:
	var captured_payload: Dictionary = {}
	func ensure_server(_model_absolute_path: String) -> Dictionary:
		return {"ok": true}
	func _request_progress_json(payload: Dictionary, _stall_seconds: float, _total_seconds: float, _byte_budget: int, _port: int = 8766) -> Dictionary:
		captured_payload = payload.duplicate(true)
		return {"ok": true, "data": {"choices": [{"message": {"content": "{}"}}]}}

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
	assert(not planner.last_plan_diagnostic.has("synthetic_response_excerpt"))
	planner.capture_synthetic_plan_response = true
	model.response = "x".repeat(1200)
	await planner.make_plan("probe", [], [])
	assert(planner.last_plan_diagnostic.synthetic_response_excerpt == "x".repeat(1024))
	planner.capture_synthetic_plan_response = false
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
	var probe_path := ProjectSettings.globalize_path("user://core_payload_probe.gguf")
	var probe_file := FileAccess.open(probe_path, FileAccess.WRITE)
	assert(probe_file != null)
	probe_file.store_string("fixture")
	probe_file.close()
	var payload_probe := PayloadProbe.new()
	var structured := await payload_probe.chat(probe_path, model.captured, {})
	assert(structured.ok)
	assert(payload_probe.captured_payload.get("response_format", {}) == {"type": "json_object"})
	assert(payload_probe.captured_payload.get("reasoning_effort", "") == "none")
	assert(not structured.terse_request)
	assert(structured.max_tokens == OwnerResourcePolicy.value("chat_max_tokens"))
	assert(payload_probe.captured_payload.max_tokens == OwnerResourcePolicy.value("chat_max_tokens"))
	var ordinary := await payload_probe.chat(probe_path, [{"role": "user", "content": "Explain planning in prose"}], {})
	assert(ordinary.ok)
	assert(not payload_probe.captured_payload.has("response_format"))
	DirAccess.remove_absolute(probe_path)
	payload_probe.free()
	model.core_runtime.android_runtime.free()
	model.core_runtime.desktop_runtime.free()
	model.core_runtime.free()
	model.free()
	planner.free()
	desktop.free()
	print("AURORA_CORE_BENCHMARK_DIAGNOSTICS_OK bounded=true transport=true private_fields_excluded=true")
	quit(0)
