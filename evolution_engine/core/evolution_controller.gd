class_name AuroraEvolutionEngine
extends Node

signal phase_changed(phase: String, details: Dictionary)
signal cycle_completed(report: Dictionary)
signal cycle_rejected(report: Dictionary)

const STALE_GUARD_SECONDS := 14400

var foundation := AuroraEvolutionFoundationAdapter.new()
var policy := AuroraEvolutionPolicy.new()
var execution_guard := AuroraEvolutionExecutionGuard.new()
var experiments := AuroraEvolutionExperimentRegistry.new()
var candidates := AuroraEvolutionCandidateLedger.new()
var metrics := AuroraEvolutionMetricsAdapter.new()
var decisions := AuroraEvolutionDecisionRecord.new()
var tournament := AuroraEvolutionTournamentAdapter.new()
var core_tournament := AuroraEvolutionCoreTournamentAdapter.new()
var evidence_gate := AuroraEvolutionEvidenceGate.new()
var experience := AuroraEvolutionExperienceBridge.new()
var context := AuroraEvolutionContextBridge.new()

var _cycle_running := false
var _cycle_epoch := 0
var _active_cycle_token := 0
var _active_experiment_id := ""
var _last_report: Dictionary = {}

func _exit_tree() -> void:
	if bool(execution_guard.status().get("held", false)):
		execution_guard.emergency_release("Evolution controller left scene tree")
	core_tournament.emergency_release_owned_lock("Evolution controller left scene tree")
	_cycle_running = false
	_active_cycle_token = 0
	_active_experiment_id = ""

func bind_foundation(
	coordinator,
	improver,
	extensions,
	memory,
	knowledge,
	core_pipeline = null,
	autonomy_settings = null,
	update_guard = null,
	sandbox = null
) -> Dictionary:
	foundation.bind(
		coordinator,
		improver,
		extensions,
		memory,
		knowledge,
		core_pipeline,
		autonomy_settings,
		update_guard,
		sandbox
	)
	execution_guard.bind(coordinator)
	tournament.bind(improver)
	core_tournament.bind(core_pipeline)
	experience.bind(memory)
	context.bind(memory, knowledge)
	return foundation.inspect()

func set_permission_level(value: int) -> int:
	return policy.set_permission_level(value)

func status() -> Dictionary:
	var foundation_status := foundation.inspect()
	var core_contract := core_tournament.contract_status()
	return {
		"ok": bool(foundation_status.get("ok", false)),
		"running": _cycle_running,
		"policy": policy.status(),
		"foundation": foundation_status,
		"exclusive_guard": execution_guard.status(),
		"stale_guard": execution_guard.stale_status(STALE_GUARD_SECONDS),
		"active_experiment_id": _active_experiment_id,
		"active_cycle_token": _active_cycle_token,
		"update_gate": foundation.update_gate_status(),
		"last_report": _last_report.duplicate(true),
		"recent_experiments": experiments.recent(10),
		"core_tournament": core_contract,
		"core_release_authority": false,
		"core_release_authority_reason": "Evolution may prepare a verified signed-update candidate but cannot sign, publish or bypass the existing promotion authority"
	}

func analyze(goal: String) -> Dictionary:
	var gate := _gate(false, false)
	if not gate.get("ok", false):
		return gate
	if foundation.coordinator == null or not foundation.coordinator.has_method("synchronize_all"):
		return {"ok": false, "stage": "analysis", "error": "existing autonomous coordinator is unavailable"}
	phase_changed.emit("analysis", {"goal": goal})
	var result = await foundation.coordinator.synchronize_all()
	if result is Dictionary:
		return {
			"ok": bool(result.get("compatible", result.get("ok", false))),
			"stage": "analysis",
			"goal": goal,
			"sync": result,
			"experience_context": context.build(goal)
		}
	return {"ok": false, "stage": "analysis", "error": "coordinator returned invalid synchronization report"}

func propose(goal: String) -> Dictionary:
	var gate := _gate(true, false)
	if not gate.get("ok", false):
		return gate
	phase_changed.emit("proposal", {"goal": goal})
	return await tournament.preview_proposal(goal)

func run_experiment(goal: String, requested_count := 5, cycle_context: Dictionary = {}) -> Dictionary:
	var gate := _gate(true, true)
	if not gate.get("ok", false):
		return gate
	if not policy.valid_population_size(requested_count):
		return {"ok": false, "stage": "population", "error": "mutation population must be within 3..10"}
	var begin := _begin_exclusive_cycle("hot_mutation_tournament", goal, requested_count, {"requested": requested_count})
	if not bool(begin.get("ok", false)):
		return begin
	var experiment_id := str(begin.get("experiment_id", ""))
	experiments.advance(experiment_id, "mutation_tournament", {"requested": requested_count})
	phase_changed.emit("mutation_tournament", {"goal": goal, "requested": requested_count, "experiment_id": experiment_id})

	var raw_result: Dictionary = await tournament.run(goal, requested_count)
	var cycle_token := int(begin.get("cycle_token", 0))
	if not _cycle_is_current(cycle_token, experiment_id):
		return _superseded_result(experiment_id, cycle_token)
	var result: Dictionary = raw_result.duplicate(true)
	var evidence := evidence_gate.validate_tournament(raw_result)
	result["evolution_evidence"] = evidence
	if bool(raw_result.get("ok", false)) and not bool(evidence.get("ok", false)):
		result["ok"] = false
		result["stage"] = "evidence_gate"
		result["error"] = "Existing tournament returned incomplete or unsafe promotion evidence: %s" % str(evidence.get("reason", "unknown"))
	result["activation_performed"] = false
	result["activation_requires_level"] = AuroraEvolutionPolicy.LEVEL_VERIFIED_ACTIVATION
	result["cycle_context"] = cycle_context
	result = _finish_exclusive_cycle(experiment_id, "hot_mutation_tournament", goal, result, "tournament_verified" if bool(result.get("ok", false)) else "tournament_rejected")

	if bool(result.get("ok", false)):
		phase_changed.emit("winner_staged", {
			"goal": goal,
			"experiment_id": experiment_id,
			"stage_path": result.get("stage_path", ""),
			"sha256": result.get("sha256", "")
		})
		cycle_completed.emit(_last_report)
	else:
		cycle_rejected.emit(_last_report)
	return result

func run_core_experiment(goal: String, requested_target := "", requested_count := 5, cycle_context: Dictionary = {}) -> Dictionary:
	var gate := _gate(true, true)
	if not gate.get("ok", false):
		return gate
	if not policy.valid_population_size(requested_count):
		return {"ok": false, "stage": "population", "error": "Core mutation population must be within 3..10"}
	var begin := _begin_exclusive_cycle("core_mutation_tournament", goal, requested_count, {
		"requested": requested_count,
		"target": requested_target
	})
	if not bool(begin.get("ok", false)):
		return begin
	var experiment_id := str(begin.get("experiment_id", ""))
	experiments.advance(experiment_id, "core_mutation_tournament", {"target": requested_target, "requested": requested_count})
	phase_changed.emit("core_mutation_tournament", {
		"goal": goal,
		"target": requested_target,
		"requested": requested_count,
		"experiment_id": experiment_id,
		"recovered_cycle_token": recovered_token
	})

	var result: Dictionary = await core_tournament.run(goal, requested_target, requested_count)
	var cycle_token := int(begin.get("cycle_token", 0))
	if not _cycle_is_current(cycle_token, experiment_id):
		return _superseded_result(experiment_id, cycle_token)
	result["promotion_prepared"] = false
	result["cycle_context"] = cycle_context
	result = _finish_exclusive_cycle(experiment_id, "core_mutation_tournament", goal, result, "core_tournament_verified" if bool(result.get("ok", false)) else "core_tournament_rejected")
	if bool(result.get("ok", false)):
		cycle_completed.emit(_last_report)
	else:
		cycle_rejected.emit(_last_report)
	return result

func run_evolution_cycle(goal: String, mode := "hot", requested_target := "", requested_count := 5) -> Dictionary:
	var clean_mode := mode.strip_edges().to_lower()
	if clean_mode not in ["hot", "core"]:
		return {"ok": false, "stage": "cycle_mode", "error": "Evolution cycle mode must be hot or core"}
	phase_changed.emit("cycle_analysis", {"goal": goal, "mode": clean_mode})
	var analysis: Dictionary = await analyze(goal)
	var analysis_summary := _compact_analysis(analysis)
	if not bool(analysis.get("ok", false)):
		return {
			"ok": false,
			"stage": "analysis",
			"error": str(analysis.get("error", "Evolution analysis failed")),
			"cycle_mode": clean_mode,
			"analysis": analysis_summary
		}
	phase_changed.emit("cycle_experiment", {"goal": goal, "mode": clean_mode})
	var cycle_context := {"analysis": analysis_summary, "mode": clean_mode}
	var result: Dictionary
	if clean_mode == "core":
		result = await run_core_experiment(goal, requested_target, requested_count, cycle_context)
	else:
		result = await run_experiment(goal, requested_count, cycle_context)
	result["cycle_mode"] = clean_mode
	result["analysis"] = analysis_summary
	result["cycle_complete"] = true
	return result

func prepare_core_promotion(goal: String, tournament_id: String) -> Dictionary:
	var gate := _gate(true, true)
	if not gate.get("ok", false):
		return gate
	if not policy.can_prepare_promotion():
		return {"ok": false, "stage": "permission", "error": "Level 3 is required for Core promotion handoff"}
	var begin := _begin_exclusive_cycle("core_promotion_handoff", goal, 0, {"source": tournament_id})
	if not bool(begin.get("ok", false)):
		return begin
	var experiment_id := str(begin.get("experiment_id", ""))
	experiments.advance(experiment_id, "core_promotion_handoff", {"source": tournament_id})
	phase_changed.emit("core_promotion_handoff", {
		"goal": goal,
		"tournament_id": tournament_id,
		"experiment_id": experiment_id
	})

	var result: Dictionary = await core_tournament.prepare_winner(tournament_id)
	var cycle_token := int(begin.get("cycle_token", 0))
	if not _cycle_is_current(cycle_token, experiment_id):
		return _superseded_result(experiment_id, cycle_token)
	result["release_authority_granted"] = false
	return _finish_exclusive_cycle(experiment_id, "core_promotion_handoff", goal, result, "core_promotion_handoff" if bool(result.get("ok", false)) else "core_promotion_rejected")

func activate_verified_winner(goal: String, tournament_result: Dictionary) -> Dictionary:
	var gate := _gate(true, true, true)
	if not gate.get("ok", false):
		return gate
	var evidence := evidence_gate.validate_tournament(tournament_result)
	if not bool(evidence.get("ok", false)):
		return {
			"ok": false,
			"stage": "activation_evidence",
			"error": "Tournament evidence is insufficient for activation",
			"details": evidence
		}
	var record := experiments.begin("hot_extension_activation", goal, 0, {"source": str(tournament_result.get("experiment_id", ""))})
	var experiment_id := str(record.get("id", ""))
	experiments.advance(experiment_id, "activation")
	var stage_path := str(evidence.get("stage_path", ""))
	var sha256 := str(evidence.get("sha256", ""))
	if foundation.extensions == null or not foundation.extensions.has_method("activate_staged"):
		var unavailable := {"ok": false, "stage": "activation", "error": "existing RuntimeExtensionManager is unavailable"}
		return _finish_action(experiment_id, "hot_extension_activation", goal, unavailable, "winner_activation_rejected")
	phase_changed.emit("activation", {"goal": goal, "stage_path": stage_path, "experiment_id": experiment_id})
	var activated = foundation.extensions.activate_staged(stage_path, sha256)
	if not activated is Dictionary:
		var invalid := {"ok": false, "stage": "activation", "error": "RuntimeExtensionManager returned invalid result"}
		return _finish_action(experiment_id, "hot_extension_activation", goal, invalid, "winner_activation_rejected")
	var result: Dictionary = activated
	result["stage"] = "activation"
	result["evolution_evidence"] = evidence
	return _finish_action(experiment_id, "hot_extension_activation", goal, result, "winner_activation" if bool(result.get("ok", false)) else "winner_activation_rejected")

func rollback_hot_extension(extension_id: String, reason := "manual safety rollback") -> Dictionary:
	var clean_id := extension_id.strip_edges()
	if clean_id.is_empty():
		return {"ok": false, "stage": "rollback", "error": "extension id is required"}
	var record := experiments.begin("hot_extension_rollback", reason, 0, {"source": clean_id, "reason": reason})
	var experiment_id := str(record.get("id", ""))
	experiments.advance(experiment_id, "rollback", {"source": clean_id})
	if foundation.extensions == null or not foundation.extensions.has_method("deactivate"):
		var unavailable := {"ok": false, "stage": "rollback", "error": "existing RuntimeExtensionManager rollback API is unavailable"}
		return _finish_action(experiment_id, "hot_extension_rollback", reason, unavailable, "winner_rollback_rejected")
	phase_changed.emit("rollback", {"extension_id": clean_id, "reason": reason, "experiment_id": experiment_id})
	var rolled_back = foundation.extensions.deactivate(clean_id)
	if not rolled_back is Dictionary:
		var invalid := {"ok": false, "stage": "rollback", "error": "RuntimeExtensionManager returned invalid rollback result"}
		return _finish_action(experiment_id, "hot_extension_rollback", reason, invalid, "winner_rollback_rejected")
	var result: Dictionary = rolled_back
	result["stage"] = "rollback"
	result["reason"] = reason.substr(0, 1000)
	return _finish_action(experiment_id, "hot_extension_rollback", reason, result, "winner_rollback")

func core_promotion_status() -> Dictionary:
	var gate := _gate(true, false)
	if not gate.get("ok", false):
		return gate
	if not policy.can_prepare_promotion():
		return {"ok": false, "stage": "permission", "error": "Level 3 is required for promotion handoff inspection"}
	return {
		"ok": true,
		"stage": "promotion_handoff",
		"core_pipeline": foundation.core_status(),
		"core_tournament": core_tournament.contract_status(),
		"release_authority_granted": false
	}

func _begin_exclusive_cycle(kind: String, goal: String, requested_count: int, metadata: Dictionary) -> Dictionary:
	if _cycle_running:
		return {"ok": false, "stage": "busy", "error": "Evolution cycle is already running", "active_experiment_id": _active_experiment_id}
	var exclusive := execution_guard.acquire()
	if not bool(exclusive.get("ok", false)):
		return exclusive
	var record := experiments.begin(kind, goal, requested_count, metadata)
	_cycle_epoch += 1
	_active_cycle_token = _cycle_epoch
	_active_experiment_id = str(record.get("id", ""))
	_cycle_running = true
	return {
		"ok": true,
		"experiment_id": _active_experiment_id,
		"cycle_token": _active_cycle_token,
		"experiment": record,
		"exclusive": exclusive
	}

func _finish_exclusive_cycle(experiment_id: String, kind: String, goal: String, result: Dictionary, event: String) -> Dictionary:
	_cycle_running = false
	_active_cycle_token = 0
	_active_experiment_id = ""
	var release := execution_guard.release()
	result["guard_release"] = release
	return _finalize_result(experiment_id, kind, goal, result, event)

func _finish_action(experiment_id: String, kind: String, goal: String, result: Dictionary, event: String) -> Dictionary:
	return _finalize_result(experiment_id, kind, goal, result, event)

func _finalize_result(experiment_id: String, kind: String, goal: String, result: Dictionary, event: String) -> Dictionary:
	result["experiment_id"] = experiment_id
	result["candidate_ledger"] = candidates.build(experiment_id, result)
	result["metrics"] = metrics.summarize(kind, result)
	result["decision"] = decisions.build(experiment_id, kind, result)
	var record := experiments.complete(experiment_id, result)
	result["experiment"] = record
	result["experience"] = experience.record(event, goal, result, record)
	_last_report = result.duplicate(true)
	return result

func recover_stuck_cycle(reason := "manual safety recovery") -> Dictionary:
	var guard_status := execution_guard.status()
	var core_lock := core_tournament.lock_status()
	if not _cycle_running and not bool(guard_status.get("held", false)) and not bool(core_lock.get("owned", false)):
		return {"ok": true, "recovered": false, "reason": "no stuck Evolution state"}
	var experiment_id := _active_experiment_id
	var recovered_token := _active_cycle_token
	_cycle_epoch += 1
	_active_cycle_token = 0
	var guard_release := execution_guard.emergency_release(reason)
	var core_release := core_tournament.emergency_release_owned_lock(reason)
	_cycle_running = false
	_active_experiment_id = ""
	var result := {
		"ok": false,
		"stage": "stuck_cycle_recovery",
		"error": reason.substr(0, 1200),
		"recovered": true,
		"guard_release": guard_release,
		"core_lock_release": core_release,
		"experiment_id": experiment_id
	}
	if not experiment_id.is_empty():
		result["metrics"] = metrics.summarize("stuck_cycle_recovery", result)
		var record := experiments.fail(experiment_id, "stuck_cycle_recovery", reason)
		result["experiment"] = record
		result["experience"] = experience.record("stuck_cycle_recovery", reason, result, record)
	_last_report = result.duplicate(true)
	return result

func _cycle_is_current(cycle_token: int, experiment_id: String) -> bool:
	return (
		_cycle_running
		and cycle_token > 0
		and cycle_token == _active_cycle_token
		and experiment_id == _active_experiment_id
	)

func _superseded_result(experiment_id: String, cycle_token: int) -> Dictionary:
	return {
		"ok": false,
		"stage": "cycle_superseded",
		"error": "Evolution cycle was recovered or superseded before the asynchronous operation returned",
		"experiment_id": experiment_id,
		"cycle_token": cycle_token,
		"active_experiment_id": _active_experiment_id,
		"active_cycle_token": _active_cycle_token
	}

func _compact_analysis(analysis: Dictionary) -> Dictionary:
	var sync = analysis.get("sync", {})
	var experience_context = analysis.get("experience_context", {})
	return {
		"ok": bool(analysis.get("ok", false)),
		"compatible": bool(sync.get("compatible", sync.get("ok", false))) if sync is Dictionary else false,
		"memory_count": int(experience_context.get("memory_count", 0)) if experience_context is Dictionary else 0,
		"knowledge_count": int(experience_context.get("knowledge_count", 0)) if experience_context is Dictionary else 0
	}

func _gate(require_proposal: bool, require_experiment: bool, require_activation := false) -> Dictionary:
	var foundation_status := foundation.inspect()
	if not bool(foundation_status.get("ok", false)):
		return {"ok": false, "stage": "foundation", "error": "Evolution foundation is incomplete", "details": foundation_status}
	var settings := foundation.current_autonomy_settings()
	if not policy.master_enabled(settings):
		return {"ok": false, "stage": "master_stop", "error": "AuroraFox autonomy master stop is active or unavailable"}
	if require_experiment or require_activation:
		var update_gate := foundation.update_gate_status()
		if not bool(update_gate.get("ok", false)):
			return {"ok": false, "stage": "update_guard", "error": str(update_gate.get("reason", "Update safety gate blocked Evolution")), "details": update_gate}
	if require_activation and not policy.can_activate_verified_extension():
		return {"ok": false, "stage": "permission", "error": "Level 4 is required for verified staged activation"}
	if require_experiment and not policy.can_experiment():
		return {"ok": false, "stage": "permission", "error": "Level 2 is required for sandbox experiments"}
	if require_proposal and not policy.can_propose():
		return {"ok": false, "stage": "permission", "error": "Level 1 is required for proposals"}
	return {"ok": true}
