class_name AuroraEvolutionProposalRecord
extends RefCounted

var _sequence := 0

func build(goal: String, mode: String, target: String, requested_count: int, learning_signal: Dictionary) -> Dictionary:
	_sequence += 1
	var now := int(Time.get_unix_time_from_system())
	return {
		"id": "%d-p%04d" % [now, _sequence],
		"goal": goal.substr(0, 2000),
		"mode": mode.substr(0, 40),
		"target": target.substr(0, 500),
		"requested_count": requested_count,
		"hypothesis": _hypothesis(mode, target),
		"constraints": [
			"reuse_existing_aurorafox_foundation",
			"population_3_to_10",
			"same_stable_baseline",
			"no_regression_before_quality",
			"independent_winner_verification",
			"no_release_authority"
		],
		"learning_signal": learning_signal.duplicate(true),
		"created_at": Time.get_datetime_string_from_system(true),
		"created_unix": now
	}

func _hypothesis(mode: String, target: String) -> String:
	if mode == "core":
		return "A distinct verified Core candidate can improve the requested target without public-contract or benchmark regression: " + target.substr(0, 300)
	return "A distinct verified hot extension can improve the requested goal without privileged APIs or regression."
