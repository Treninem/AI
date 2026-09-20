class_name AuroraEvolutionExperienceBridge
extends RefCounted

const SOURCE := "aurorafox_evolution_engine"
const KIND := "evolution_experience"

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
		"metrics": _compact_metrics(result.get("metrics", {})),
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
		"experiment_id": payload["experiment_id"]
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
