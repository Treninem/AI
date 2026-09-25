class_name AuroraEvolutionDecisionRecord
extends RefCounted

func build(experiment_id: String, kind: String, result: Dictionary) -> Dictionary:
	var accepted := bool(result.get("ok", false))
	var outcome := "accepted" if accepted else "rejected"
	if kind.contains("rollback"):
		outcome = "rollback_completed" if accepted else "rollback_failed"
	elif kind.contains("promotion_handoff"):
		outcome = "handoff_prepared" if accepted else "handoff_rejected"
	elif kind.contains("activation"):
		outcome = "activated" if accepted else "activation_rejected"

	var winner = result.get("winner", {})
	var reason := str(result.get("error", "")).substr(0, 1200)
	if accepted and winner is Dictionary:
		reason = str(winner.get("reason", "")).substr(0, 1200)
	if accepted and reason.is_empty():
		reason = "accepted by existing verification/evaluation gates"

	var metrics = result.get("metrics", {})
	var quality: Dictionary = {}
	if metrics is Dictionary and metrics.get("quality", {}) is Dictionary:
		quality = (metrics.get("quality", {}) as Dictionary).duplicate(true)

	return {
		"experiment_id": experiment_id.substr(0, 160),
		"kind": kind.substr(0, 120),
		"outcome": outcome,
		"accepted": accepted,
		"reason": reason,
		"stage": str(result.get("stage", "")).substr(0, 120),
		"population_size": int(result.get("population_size", 0)),
		"verified_count": int(result.get("verified_count", 0)),
		"quality": quality,
		"winner_sha256": _winner_sha(result),
		"release_authority_granted": bool(result.get("release_authority_granted", false)),
		"activation_performed": bool(result.get("activation_performed", false))
	}

func _winner_sha(result: Dictionary) -> String:
	var winner = result.get("winner", {})
	if winner is Dictionary:
		return str(winner.get("sha256", "")).substr(0, 64)
	return str(result.get("candidate_sha256", result.get("sha256", ""))).substr(0, 64)
