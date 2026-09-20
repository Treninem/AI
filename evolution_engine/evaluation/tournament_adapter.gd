class_name AuroraEvolutionTournamentAdapter
extends RefCounted

const MAX_CAPTURED_CANDIDATES := 10

var improver
var policy := AuroraEvolutionPolicy.new()
var _captured_candidates: Array = []

func bind(value) -> void:
	var callback := Callable(self, "_on_mutation_candidate_completed")
	if improver != null and improver.has_signal("mutation_candidate_completed") and improver.is_connected("mutation_candidate_completed", callback):
		improver.disconnect("mutation_candidate_completed", callback)
	improver = value
	_captured_candidates.clear()
	if improver != null and improver.has_signal("mutation_candidate_completed") and not improver.is_connected("mutation_candidate_completed", callback):
		improver.connect("mutation_candidate_completed", callback)

func available() -> bool:
	return improver != null and improver.has_method("run_mutation_tournament")

func run(goal: String, requested_count := 5) -> Dictionary:
	if not available():
		return {"ok": false, "stage": "setup", "error": "existing SelfImprover tournament is unavailable"}
	if not policy.valid_population_size(requested_count):
		return {
			"ok": false,
			"stage": "population",
			"error": "mutation population must be within 3..10",
			"requested": requested_count
		}
	_captured_candidates.clear()
	var raw = await improver.run_mutation_tournament(goal, requested_count)
	if not raw is Dictionary:
		return {"ok": false, "stage": "tournament", "error": "SelfImprover returned an invalid tournament result"}
	var result: Dictionary = raw.duplicate(true)
	if not _captured_candidates.is_empty():
		result["candidates"] = _captured_candidates.duplicate(true)
	result["captured_candidate_count"] = _captured_candidates.size()
	return result

func preview_proposal(goal: String) -> Dictionary:
	if improver == null or not improver.has_method("propose_improvement"):
		return {"ok": false, "stage": "setup", "error": "existing SelfImprover proposal API is unavailable"}
	var result = await improver.propose_improvement(goal, 0, "balanced", [])
	if result is Dictionary:
		return result
	return {"ok": false, "stage": "proposal", "error": "SelfImprover returned an invalid proposal result"}

func captured_candidates() -> Array:
	return _captured_candidates.duplicate(true)

func _on_mutation_candidate_completed(candidate: Dictionary) -> void:
	if _captured_candidates.size() >= MAX_CAPTURED_CANDIDATES:
		return
	_captured_candidates.append(candidate.duplicate(true))
