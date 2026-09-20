class_name AuroraEvolutionEngine
extends Node

signal phase_changed(phase: String, details: Dictionary)
signal cycle_completed(report: Dictionary)
signal cycle_rejected(report: Dictionary)

var foundation := AuroraEvolutionFoundationAdapter.new()
var policy := AuroraEvolutionPolicy.new()
var execution_guard := AuroraEvolutionExecutionGuard.new()
var tournament := AuroraEvolutionTournamentAdapter.new()
var core_tournament := AuroraEvolutionCoreTournamentAdapter.new()
var evidence_gate := AuroraEvolutionEvidenceGate.new()
var experience := AuroraEvolutionExperienceBridge.new()
var context := AuroraEvolutionContextBridge.new()

var _cycle_running := false
var _last_report: Dictionary = {}

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
		"update_gate": foundation.update_gate_status(),
		"last_report": _last_report.duplicate(true),
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

func run_experiment(goal: String, requested_count := 5) -> Dictionary:
	var gate := _gate(true, true)
	if not gate.get("ok", false):
		return gate
	if _cycle_running:
		return {"ok": false, "stage": "busy", "error": "Evolution cycle is already running"}
	if not policy.valid_population_size(requested_count):
		return {"ok": false, "stage": "population", "error": "mutation population must be within 3..10"}
	var exclusive := execution_guard.acquire()
	if not bool(exclusive.get("ok", false)):
		return exclusive

	_cycle_running = true
	phase_changed.emit("mutation_tournament", {"goal": goal, "requested": requested_count})
	var raw_result: Dictionary = await tournament.run(goal, requested_count)
	_cycle_running = false
	execution_guard.release()

	var result: Dictionary = raw_result.duplicate(true)
	var evidence := evidence_gate.validate_tournament(raw_result)
	result["evolution_evidence"] = evidence
	if bool(raw_result.get("ok", false)) and not bool(evidence.get("ok", false)):
		result["ok"] = false
		result["stage"] = "evidence_gate"
		result["error"] = "Existing tournament returned incomplete or unsafe promotion evidence: %s" % str(evidence.get("reason", "unknown"))

	var event := "tournament_verified" if bool(result.get("ok", false)) else "tournament_rejected"
	result["activation_performed"] = false
	result["activation_requires_level"] = AuroraEvolutionPolicy.LEVEL_VERIFIED_ACTIVATION
	result["experience"] = experience.record(event, goal, result)
	_last_report = result.duplicate(true)
	if bool(result.get("ok", false)):
		phase_changed.emit("winner_staged", {
			"goal": goal,
			"stage_path": result.get("stage_path", ""),
			"sha256": result.get("sha256", "")
		})
		cycle_completed.emit(_last_report)
	else:
		cycle_rejected.emit(_last_report)
	return result

func run_core_experiment(goal: String, requested_target := "", requested_count := 5) -> Dictionary:
	var gate := _gate(true, true)
	if not gate.get("ok", false):
		return gate
	if _cycle_running:
		return {"ok": false, "stage": "busy", "error": "Evolution cycle is already running"}
	if not policy.valid_population_size(requested_count):
		return {"ok": false, "stage": "population", "error": "Core mutation population must be within 3..10"}
	var exclusive := execution_guard.acquire()
	if not bool(exclusive.get("ok", false)):
		return exclusive

	_cycle_running = true
	phase_changed.emit("core_mutation_tournament", {"goal": goal, "target": requested_target, "requested": requested_count})
	var result: Dictionary = await core_tournament.run(goal, requested_target, requested_count)
	_cycle_running = false
	execution_guard.release()

	result["promotion_prepared"] = false
	result["experience"] = experience.record("core_tournament_verified" if bool(result.get("ok", false)) else "core_tournament_rejected", goal, result)
	_last_report = result.duplicate(true)
	if bool(result.get("ok", false)):
		cycle_completed.emit(_last_report)
	else:
		cycle_rejected.emit(_last_report)
	return result

func prepare_core_promotion(goal: String, tournament_id: String) -> Dictionary:
	var gate := _gate(true, true)
	if not gate.get("ok", false):
		return gate
	if not policy.can_prepare_promotion():
		return {"ok": false, "stage": "permission", "error": "Level 3 is required for Core promotion handoff"}
	var exclusive := execution_guard.acquire()
	if not bool(exclusive.get("ok", false)):
		return exclusive

	phase_changed.emit("core_promotion_handoff", {"goal": goal, "tournament_id": tournament_id})
	var result: Dictionary = await core_tournament.prepare_winner(tournament_id)
	execution_guard.release()

	result["release_authority_granted"] = false
	result["experience"] = experience.record("core_promotion_handoff" if bool(result.get("ok", false)) else "core_promotion_rejected", goal, result)
	_last_report = result.duplicate(true)
	return result

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
	var stage_path := str(evidence.get("stage_path", ""))
	var sha256 := str(evidence.get("sha256", ""))
	if foundation.extensions == null or not foundation.extensions.has_method("activate_staged"):
		return {"ok": false, "stage": "activation", "error": "existing RuntimeExtensionManager is unavailable"}
	phase_changed.emit("activation", {"goal": goal, "stage_path": stage_path})
	var activated = foundation.extensions.activate_staged(stage_path, sha256)
	if not activated is Dictionary:
		return {"ok": false, "stage": "activation", "error": "RuntimeExtensionManager returned invalid result"}
	var result: Dictionary = activated
	result["stage"] = "activation"
	result["evolution_evidence"] = evidence
	result["experience"] = experience.record("winner_activation", goal, result)
	_last_report = result.duplicate(true)
	return result

func rollback_hot_extension(extension_id: String, reason := "manual safety rollback") -> Dictionary:
	var clean_id := extension_id.strip_edges()
	if clean_id.is_empty():
		return {"ok": false, "stage": "rollback", "error": "extension id is required"}
	if foundation.extensions == null or not foundation.extensions.has_method("deactivate"):
		return {"ok": false, "stage": "rollback", "error": "existing RuntimeExtensionManager rollback API is unavailable"}
	phase_changed.emit("rollback", {"extension_id": clean_id, "reason": reason})
	var rolled_back = foundation.extensions.deactivate(clean_id)
	if not rolled_back is Dictionary:
		return {"ok": false, "stage": "rollback", "error": "RuntimeExtensionManager returned invalid rollback result"}
	var result: Dictionary = rolled_back
	result["stage"] = "rollback"
	result["reason"] = reason.substr(0, 1000)
	if experience.available():
		result["experience"] = experience.record("winner_rollback", reason, result)
	_last_report = result.duplicate(true)
	return result

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
