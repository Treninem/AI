class_name AuroraEvolutionEngine
extends Node

signal phase_changed(phase: String, details: Dictionary)
signal cycle_completed(report: Dictionary)
signal cycle_rejected(report: Dictionary)

var foundation := AuroraEvolutionFoundationAdapter.new()
var policy := AuroraEvolutionPolicy.new()
var tournament := AuroraEvolutionTournamentAdapter.new()
var experience := AuroraEvolutionExperienceBridge.new()

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
	tournament.bind(improver)
	experience.bind(memory)
	return foundation.inspect()

func set_permission_level(value: int) -> int:
	return policy.set_permission_level(value)

func status() -> Dictionary:
	var foundation_status := foundation.inspect()
	return {
		"ok": bool(foundation_status.get("ok", false)),
		"running": _cycle_running,
		"policy": policy.status(),
		"foundation": foundation_status,
		"update_gate": foundation.update_gate_status(),
		"last_report": _last_report.duplicate(true),
		"core_autonomous_promotion_enabled": false,
		"core_promotion_reason": "CoreImprovementPipeline is single-candidate; 3..10 Core candidate tournament adapter is required first"
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
			"sync": result
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
	_cycle_running = true
	phase_changed.emit("mutation_tournament", {"goal": goal, "requested": requested_count})
	var result: Dictionary = await tournament.run(goal, requested_count)
	_cycle_running = false
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

func activate_verified_winner(goal: String, tournament_result: Dictionary) -> Dictionary:
	var gate := _gate(true, true, true)
	if not gate.get("ok", false):
		return gate
	if not bool(tournament_result.get("ok", false)):
		return {"ok": false, "stage": "activation", "error": "cannot activate a rejected tournament"}
	if not bool(tournament_result.get("verified", false)) or not bool(tournament_result.get("staged", false)):
		return {"ok": false, "stage": "activation", "error": "winner is not verified and staged"}
	var stage_path := str(tournament_result.get("stage_path", ""))
	var sha256 := str(tournament_result.get("sha256", ""))
	if stage_path.is_empty() or sha256.length() != 64:
		return {"ok": false, "stage": "activation", "error": "winner staging evidence is incomplete"}
	if foundation.extensions == null or not foundation.extensions.has_method("activate_staged"):
		return {"ok": false, "stage": "activation", "error": "existing RuntimeExtensionManager is unavailable"}
	phase_changed.emit("activation", {"goal": goal, "stage_path": stage_path})
	var activated = foundation.extensions.activate_staged(stage_path, sha256)
	if not activated is Dictionary:
		return {"ok": false, "stage": "activation", "error": "RuntimeExtensionManager returned invalid result"}
	var result: Dictionary = activated
	result["stage"] = "activation"
	result["experience"] = experience.record("winner_activation", goal, result)
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
		"autonomous_core_promotion_enabled": false,
		"reason": "A 3..10 candidate Core tournament adapter is required before CoreImprovementPipeline may be invoked by Evolution Engine"
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
