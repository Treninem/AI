class_name AuroraEvolutionExperienceBridge
extends RefCounted

const SOURCE := "aurorafox_evolution_engine"
const KIND := "evolution_experience"

var memory

func bind(memory_value) -> void:
	memory = memory_value

func available() -> bool:
	return memory != null and memory.has_method("remember")

func record(event: String, goal: String, result: Dictionary) -> Dictionary:
	if not available():
		return {"ok": false, "error": "MemoryStore.remember is unavailable"}
	var payload := {
		"event": event,
		"goal": goal.substr(0, 2000),
		"ok": bool(result.get("ok", false)),
		"stage": str(result.get("stage", "")).substr(0, 200),
		"population_size": int(result.get("population_size", 0)),
		"verified_count": int(result.get("verified_count", 0)),
		"winner": _compact_winner(result.get("winner", {})),
		"error": str(result.get("error", "")).substr(0, 1200),
		"recorded_at": Time.get_datetime_string_from_system(true)
	}
	memory.remember(KIND, JSON.stringify(payload), SOURCE, 0.70, 0.90)
	return {"ok": true, "stored": true, "kind": KIND, "source": SOURCE}

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
		"verified": bool(winner.get("verified", false))
	}
