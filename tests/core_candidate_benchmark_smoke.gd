extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _run() -> void:
	var gate := CoreCandidateBenchmark.new()
	var original := "class_name DemoCore\nextends RefCounted\nsignal changed(value)\nfunc run(value):\n\treturn value\nfunc status():\n\treturn {\"ok\": true}\nfunc _internal():\n\treturn 1\n"
	var good := "class_name DemoCore\nextends RefCounted\nsignal changed(value)\nfunc run(value):\n\treturn value\nfunc status():\n\treturn {\"ok\": true}\nfunc _internal():\n\treturn 2\n"
	var contract := gate.source_contract(original, good, "scripts/agent_core.gd")
	if not bool(contract.get("ok", false)):
		_fail("Safe compatible candidate was rejected: " + JSON.stringify(contract), 2)
		return

	var missing_public := "class_name DemoCore\nextends RefCounted\nsignal changed(value)\nfunc run(value):\n\treturn value\nfunc _internal():\n\treturn 2\n"
	var missing_result := gate.source_contract(original, missing_public, "scripts/agent_core.gd")
	if bool(missing_result.get("ok", true)) or "status" not in missing_result.get("missing_public_functions", []):
		_fail("Benchmark did not reject removed public function", 3)
		return

	var missing_signal := good.replace("signal changed(value)\n", "")
	var signal_result := gate.source_contract(original, missing_signal, "scripts/agent_core.gd")
	if bool(signal_result.get("ok", true)) or "changed" not in signal_result.get("missing_signals", []):
		_fail("Benchmark did not reject removed signal", 4)
		return

	var risky := good.replace("func _internal():\n\treturn 2", "func _internal():\n\tvar req = HTTPRequest.new()\n\treturn req")
	var risky_result := gate.source_contract(original, risky, "scripts/agent_core.gd")
	if bool(risky_result.get("ok", true)) or (risky_result.get("risky_primitive_increases", {}) as Dictionary).is_empty():
		_fail("Benchmark allowed a new network primitive", 5)
		return

	for target in ["scripts/memory_store.gd", "scripts/agent_core.gd", "scripts/cognition_layer.gd", "agent/goals.gd"]:
		if gate.commands_for_target(target).is_empty():
			_fail("No deterministic runtime benchmark registered for " + target, 6)
			return

	var baseline := gate.summarize_runs([
		{"ok": true, "command": ["godot", "test-a"]},
		{"ok": true, "command": ["godot", "test-b"]}
	])
	var candidate_ok := gate.summarize_runs([
		{"ok": true, "command": ["godot", "test-a"]},
		{"ok": true, "command": ["godot", "test-b"]}
	])
	if not bool(gate.compare_runtime(baseline, candidate_ok).get("ok", false)):
		_fail("Equal passing candidate suite was treated as a regression", 7)
		return
	var candidate_bad := gate.summarize_runs([
		{"ok": true, "command": ["godot", "test-a"]},
		{"ok": false, "command": ["godot", "test-b"], "code": 1}
	])
	if bool(gate.compare_runtime(baseline, candidate_bad).get("ok", true)):
		_fail("Runtime regression was accepted", 8)
		return

	var pipeline := CoreImprovementPipeline.new()
	if pipeline.MIN_REVIEW_IMPROVEMENT <= 0.0:
		_fail("Comparative review does not require positive improvement", 9)
		return
	if pipeline.MIN_TOURNAMENT_CANDIDATES != 3 or pipeline.MAX_TOURNAMENT_CANDIDATES != 10 or pipeline.DEFAULT_TOURNAMENT_CANDIDATES != 5:
		_fail("Mutation tournament bounds/default changed", 10)
		return
	if pipeline.auto_apply_dev_checkout:
		_fail("Autonomous Core tournament must not rewrite a dev checkout by default", 11)
		return
	if not pipeline._target_allowed("scripts/agent_core.gd"):
		_fail("Expected core target disappeared from allowlist", 12)
		return
	for protected in ["update/update_manager.gd", "scripts/core_improvement_pipeline.gd", "project.godot"]:
		if pipeline._target_allowed(protected):
			_fail("Protected path entered autonomous rewrite allowlist: " + protected, 13)
			return

	var tournament := pipeline._select_tournament_winner([
		{"candidate_sha256":"bbb", "hard_gates_passed":true, "eligible":true, "review":{"baseline_score":70.0, "candidate_score":75.0}},
		{"candidate_sha256":"aaa", "hard_gates_passed":true, "eligible":true, "review":{"baseline_score":70.0, "candidate_score":72.0}},
		{"candidate_sha256":"unsafe", "hard_gates_passed":false, "eligible":true, "review":{"baseline_score":70.0, "candidate_score":99.0}}
	])
	if not bool(tournament.get("ok", false)) or str(tournament.get("winner", {}).get("candidate_sha256", "")) != "bbb":
		_fail("Tournament did not choose the best hard-gate-passing mutation", 14)
		return
	if float(tournament.get("incumbent", {}).get("score", -1.0)) != 70.0:
		_fail("Incumbent did not participate in tournament scoring", 15)
		return

	var no_winner := pipeline._select_tournament_winner([
		{"candidate_sha256":"tie", "hard_gates_passed":true, "eligible":true, "review":{"baseline_score":80.0, "candidate_score":80.5}},
		{"candidate_sha256":"failed", "hard_gates_passed":false, "eligible":true, "review":{"baseline_score":80.0, "candidate_score":99.0}}
	])
	if bool(no_winner.get("ok", true)):
		_fail("Tournament promoted a tied/inconclusive or hard-gate-failed mutation", 16)
		return

	pipeline.free()
	print("AURORA_CORE_CANDIDATE_BENCHMARK_SMOKE_OK contracts=true baseline=true candidate=true tournament=3-10 incumbent=true winner=true no_promotion=true")
	quit(0)
