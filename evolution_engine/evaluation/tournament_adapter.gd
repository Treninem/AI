class_name AuroraEvolutionTournamentAdapter
extends RefCounted

var improver
var policy := AuroraEvolutionPolicy.new()

func bind(value) -> void:
	improver = value

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
	var result = await improver.run_mutation_tournament(goal, requested_count)
	if result is Dictionary:
		return result
	return {"ok": false, "stage": "tournament", "error": "SelfImprover returned an invalid tournament result"}

func preview_proposal(goal: String) -> Dictionary:
	if improver == null or not improver.has_method("propose_improvement"):
		return {"ok": false, "stage": "setup", "error": "existing SelfImprover proposal API is unavailable"}
	var result = await improver.propose_improvement(goal, 0, "balanced", [])
	if result is Dictionary:
		return result
	return {"ok": false, "stage": "proposal", "error": "SelfImprover returned an invalid proposal result"}
