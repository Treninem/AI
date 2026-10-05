extends SceneTree

func _init() -> void:
	var formatter = preload("res://benchmarks/core/failure_diagnostics.gd")
	var diagnostic: Dictionary = formatter.describe({"ok": false, "runtime": "aurora_core", "error": "x".repeat(900), "raw": "private raw", "attempted_models": [{"runtime": "aurora_core_desktop", "error": "transport failure", "http": 0, "transport_result": 13, "model_failure": false, "retryable": true, "failure_scope": "request", "model_path": "private model path"}]})
	assert(not diagnostic.ok and diagnostic.error.length() == 600)
	assert(diagnostic.attempts.size() == 1)
	assert(diagnostic.attempts[0].transport_result == 13 and diagnostic.attempts[0].http == 0)
	assert(diagnostic.attempts[0].retryable and not diagnostic.attempts[0].model_failure)
	assert(not JSON.stringify(diagnostic).contains("private"))
	assert(formatter.describe({"ok": true}).ok)
	print("AURORA_CORE_BENCHMARK_DIAGNOSTICS_OK bounded=true transport=true private_fields_excluded=true")
	quit(0)
