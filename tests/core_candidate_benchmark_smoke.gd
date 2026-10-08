extends SceneTree

# Only the platform/dependency seams are replaced; production guards and entry
# locking execute unchanged. This does not claim Windows source verification.
class ControlRoot extends Node:
	var controls := {"master_enabled": true}
	func get_settings() -> Dictionary: return controls

class ControlPipeline extends CoreImprovementPipeline:
	func _candidate_platform_supported() -> bool: return true
	func _bind_existing() -> void: pass
	func _save_state() -> void: pass
	func _signed_update_busy() -> bool: return false

class DelayedAI extends AIClient:
	signal released
	var availability_calls := 0
	var chat_calls := 0
	var stop_after := 1
	var stop_owner: ControlRoot
	func is_available() -> bool:
		availability_calls += 1
		await released
		return true
	func chat(_messages: Array, _temperature: float = 0.2) -> Dictionary:
		chat_calls += 1
		if chat_calls >= stop_after: stop_owner.controls.master_enabled = false
		return {"ok": true, "content": "{}"}

class RunProbe extends RefCounted:
	var done := false
	var result := {}
	func start(pipeline: CoreImprovementPipeline) -> void:
		result = await pipeline.run_candidate("guard probe")
		done = true

func _control_boundaries() -> bool:
	var owner := ControlRoot.new()
	var candidate := ControlPipeline.new()
	owner.add_child(candidate)
	var model := DelayedAI.new()
	model.stop_owner = owner
	candidate.ai = model
	var registry := ToolRegistry.new()
	candidate.tools = registry
	var probe := RunProbe.new()
	probe.start(candidate)
	if model.availability_calls != 1 or not candidate._running:
		_fail("Candidate entry did not lock before availability await", 20)
		return false
	var overlap := await candidate.run_candidate("overlap")
	if overlap.get("ok", true) or model.availability_calls != 1:
		_fail("Overlapping candidate entered availability", 21)
		return false
	owner.controls.master_enabled = false
	model.released.emit()
	if not probe.done or probe.result.get("error") != "candidate_execution_stopped" or candidate._running or model.chat_calls != 0:
		_fail("Stop during availability did not release entry without model work", 22)
		return false
	owner.controls.master_enabled = true
	var model_result := await candidate._candidate_chat([], 0.2)
	if model_result.get("ok", true) or model.chat_calls != 1:
		_fail("Model success survived stop during await", 23)
		return false
	await candidate._candidate_chat([], 0.2)
	if model.chat_calls != 1:
		_fail("Model ran after Master Stop", 24)
		return false
	owner.controls.master_enabled = true
	var calls := [0]
	registry.register_tool("workspace_exec", "probe", {}, func(_args: Dictionary) -> Dictionary:
		calls[0] += 1
		owner.controls.master_enabled = false
		return {"ok": true})
	var tool_result: Dictionary = await candidate._candidate_tool("workspace_exec", {})
	await candidate._candidate_tool("workspace_exec", {})
	if calls[0] != 1 or tool_result.get("ok", true) or not tool_result.get("effects_may_have_occurred", false):
		_fail("Tool stop concealed started effects or ran next operation", 25)
		return false
	owner.controls.master_enabled = true
	candidate._guard_required = true
	candidate._caller_guard = func(_stage, _args): return {"allowed": "yes"}
	if candidate._candidate_allowed("probe"):
		_fail("Malformed caller permission accepted", 26)
		return false
	candidate._caller_guard = func(stage, _args): return stage == "candidate_control"
	registry.register_tool("aurora_core_candidate", "probe", {}, func(_args, guard): return {"ok": guard.call("candidate_control", {})})
	var forwarded: Dictionary = await registry.call_tool("aurora_core_candidate", {}, candidate._caller_guard)
	if not forwarded.get("ok", false):
		_fail("ToolRegistry lost caller guard", 27)
		return false
	candidate._caller_guard = Callable()
	if candidate._candidate_allowed("probe"):
		_fail("Required expired guard accepted", 28)
		return false
	candidate._guard_required = false
	candidate._automatic_run = true
	candidate.autonomous_core_candidates = false
	if candidate._candidate_allowed("probe"):
		_fail("Disabled automatic candidates accepted", 29)
		return false
	candidate._automatic_run = false
	if not candidate._candidate_allowed("probe"):
		_fail("Manual candidate inherited automatic-only restriction", 30)
		return false
	var original_limits := OwnerResourcePolicy._cached.duplicate()
	OwnerResourcePolicy._cached = OwnerResourcePolicy.DEFAULTS.duplicate()
	var observed := []
	registry.register_tool("workspace_exec", "budget probe", {}, func(args):
		observed.append(args.timeout)
		return {"ok": true})
	for limit in [2, 300, 0]:
		OwnerResourcePolicy._cached.candidate_benchmark_seconds = limit
		var results := await candidate._run_benchmark_commands([["probe"]])
		if results.size() != 1 or not results[0].get("ok", false) or observed.back() != limit:
			_fail("Owner benchmark budget not forwarded", 31)
			return false
	OwnerResourcePolicy._cached.candidate_proposal_attempt_multiplier = 0
	model.chat_calls = 0
	model.stop_after = 3
	var unlimited_probe := RunProbe.new()
	unlimited_probe.start(candidate)
	model.released.emit()
	if not unlimited_probe.done or model.chat_calls != 3 or unlimited_probe.result.get("error") != "candidate_execution_stopped" or candidate._running:
		_fail("Unlimited proposal attempts did not preserve per-step stop", 32)
		return false
	OwnerResourcePolicy._cached = original_limits
	model.core_runtime.android_runtime.free()
	model.core_runtime.desktop_runtime.free()
	model.core_runtime.free()
	model.free()
	registry.free()
	owner.free()
	return true

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
	if not await _control_boundaries(): return
	print("AURORA_CORE_CANDIDATE_BENCHMARK_SMOKE_OK contracts=true baseline=true candidate=true tournament=3-10 incumbent=true winner=true no_promotion=true")
	quit(0)
