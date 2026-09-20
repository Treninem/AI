class_name AuroraEvolutionExperienceBridge
extends RefCounted

const SOURCE := "aurorafox_evolution_engine"
const KIND := "evolution_experience"
const MAX_CANDIDATES := 10

var memory

func bind(memory_value) -> void:
	memory = memory_value

func available() -> bool:
	return memory != null and memory.has_method("remember")

func record(event: String, goal: String, result: Dictionary, experiment: Dictionary = {}) -> Dictionary:
	if not available():
		return {"ok": false, "error": "MemoryStore.remember is unavailable"}
	var category := _category(event, result)
	var payload := {
		"event": event.substr(0, 120),
		"category": category,
		"experiment_id": str(experiment.get("id", result.get("experiment_id", ""))).substr(0, 160),
		"experiment_kind": str(experiment.get("kind", "")).substr(0, 120),
		"goal": goal.substr(0, 2000),
		"ok": bool(result.get("ok", false)),
		"stage": str(result.get("stage", "")).substr(0, 200),
		"population_size": int(result.get("population_size", 0)),
		"verified_count": int(result.get("verified_count", 0)),
		"winner": _compact_winner(result.get("winner", {})),
		"candidates": _compact_candidates(result.get("candidate_ledger", [])),
		"metrics": _compact_metrics(result.get("metrics", {})),
		"decision": _compact_decision(result.get("decision", {})),
		"cycle_context": _compact_cycle_context(result.get("cycle_context", {})),
		"error": str(result.get("error", "")).substr(0, 1200),
		"recorded_at": Time.get_datetime_string_from_system(true)
	}
	var importance := 0.76 if category in ["accepted", "rollback"] else 0.66
	var confidence := 0.94 if category == "accepted" else 0.88
	memory.remember(KIND, JSON.stringify(payload), SOURCE, importance, confidence)
	return {
		"ok": true,
		"stored": true,
		"kind": KIND,
		"source": SOURCE,
		"category": category,
		"experiment_id": payload["experiment_id"],
		"candidate_count": payload["candidates"].size()
	}

func _category(event: String, result: Dictionary) -> String:
	var lower := event.to_lower()
	if lower.contains("rollback"):
		return "rollback"
	if lower.contains("blocked") or str(result.get("stage", "")) in ["permission", "master_stop", "update_guard", "exclusive_guard", "busy"]:
		return "blocked"
	if bool(result.get("ok", false)):
		return "accepted"
	return "rejected"

func _compact_winner(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var winner: Dictionary = value
	return {
		"mutation_tag": str(winner.get("mutation_tag", "")).substr(0, 80),
		"strategy": str(winner.get("strategy", "")).substr(0, 120),
		"path": str(winner.get("path", "")).substr(0, 500),
		"sha256": str(winner.get("sha256", "")).substr(0, 64),
		"score": float(winner.get("score", 0.0)),
		"delta": float(winner.get("delta", 0.0)),
		"verified": bool(winner.get("verified", false))
	}

func _compact_candidates(value: Variant) -> Array:
	var out: Array = []
	if not value is Array:
		return out
	for row in value:
		if out.size() >= MAX_CANDIDATES:
			break
		if not row is Dictionary:
			continue
		out.append({
			"candidate_id": str(row.get("candidate_id", "")).substr(0, 180),
			"strategy": str(row.get("strategy", "")).substr(0, 180),
			"sha256": str(row.get("sha256", "")).substr(0, 64),
			"reason": str(row.get("reason", "")).substr(0, 500),
			"verified": bool(row.get("verified", false)),
			"score": float(row.get("score", 0.0)),
			"delta": float(row.get("delta", 0.0)),
			"outcome": str(row.get("outcome", "")).substr(0, 40),
			"failure_stage": str(row.get("failure_stage", "")).substr(0, 120),
			"failure_error": str(row.get("failure_error", "")).substr(0, 500)
		})
	return out

func _compact_metrics(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var metrics: Dictionary = value
	return {
		"verification_ratio": float(metrics.get("verification_ratio", 0.0)),
		"quality": metrics.get("quality", {}),
		"stability": metrics.get("stability", {}),
		"speed": metrics.get("speed", {}),
		"memory": metrics.get("memory", {})
	}


func _compact_decision(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var decision: Dictionary = value
	return {
		"outcome": str(decision.get("outcome", "")).substr(0, 80),
		"accepted": bool(decision.get("accepted", false)),
		"reason": str(decision.get("reason", "")).substr(0, 800),
		"stage": str(decision.get("stage", "")).substr(0, 120),
		"winner_sha256": str(decision.get("winner_sha256", "")).substr(0, 64),
		"release_authority_granted": bool(decision.get("release_authority_granted", false)),
		"activation_performed": bool(decision.get("activation_performed", false))
	}

func _compact_cycle_context(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var context: Dictionary = value
	var analysis = context.get("analysis", {})
	var proposal = context.get("proposal", {})
	var learning = context.get("learning_signal", {})
	return {
		"mode": str(context.get("mode", "")).substr(0, 40),
		"original_goal": str(context.get("original_goal", "")).substr(0, 1200),
		"analysis": analysis.duplicate(true) if analysis is Dictionary else {},
		"proposal": _compact_proposal(proposal),
		"learning_signal": _compact_learning_signal(learning)
	}

func _compact_proposal(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var proposal: Dictionary = value
	return {
		"id": str(proposal.get("id", "")).substr(0, 160),
		"mode": str(proposal.get("mode", "")).substr(0, 40),
		"target": str(proposal.get("target", "")).substr(0, 500),
		"requested_count": int(proposal.get("requested_count", 0)),
		"hypothesis": str(proposal.get("hypothesis", "")).substr(0, 700),
		"constraints": proposal.get("constraints", [])
	}

func _compact_learning_signal(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var signal: Dictionary = value
	return {
		"parsed_evolution_experiences": int(signal.get("parsed_evolution_experiences", 0)),
		"successful_strategies": signal.get("successful_strategies", []),
		"rejected_stages": signal.get("rejected_stages", []),
		"rollback_count": int(signal.get("rollback_count", 0)),
		"blocked_count": int(signal.get("blocked_count", 0)),
		"knowledge_refs": signal.get("knowledge_refs", []),
		"raw_knowledge_instructions_used": false
	}
