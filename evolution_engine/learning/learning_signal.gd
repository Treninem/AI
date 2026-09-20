class_name AuroraEvolutionLearningSignal
extends RefCounted

const EVOLUTION_SOURCE := "aurorafox_evolution_engine"
const EVOLUTION_KIND := "evolution_experience"
const MAX_MEMORY_ROWS := 12
const MAX_KNOWLEDGE_REFS := 5
const MAX_SIGNAL_ITEMS := 6
const ALLOWED_STRATEGIES := [
	"robustness_and_edge_cases",
	"performance_and_low_allocations",
	"precision_and_determinism",
	"simplicity_and_maintainability",
	"context_quality_and_reasoning",
	"observability_and_diagnostics",
	"composability_and_reuse",
	"failure_resistance",
	"input_validation",
	"low_memory_behavior",
	"minimal regression-first hardening",
	"edge-case and recovery robustness",
	"deterministic state consistency",
	"performance and allocation efficiency",
	"reasoning/retrieval quality without contract changes",
	"failure isolation and graceful degradation",
	"compatibility-preserving simplification",
	"bounded validation and input robustness"
]
const ALLOWED_FAILURE_STAGES := [
	"proposal", "validation", "source_contract", "platform",
	"workspace", "workspace_create", "workspace_import_project",
	"candidate_integrity", "runtime_contract_test", "godot_test",
	"baseline", "baseline_benchmark", "candidate_benchmark",
	"comparative_review", "winner_final_verification",
	"winner_final_review", "evidence_gate", "update_guard",
	"exclusive_guard", "managed_mode", "core_contract",
	"handoff_validation", "handoff_verification", "handoff_review",
	"handoff_store", "core_lock_superseded"
]

func derive(context: Dictionary) -> Dictionary:
	var accepted_strategies: Dictionary = {}
	var rejected_stages: Dictionary = {}
	var rollback_count := 0
	var blocked_count := 0
	var parsed_rows := 0

	var memory_rows = context.get("memory", [])
	if memory_rows is Array:
		for raw in memory_rows.slice(0, mini(memory_rows.size(), MAX_MEMORY_ROWS)):
			if not raw is Dictionary:
				continue
			var row: Dictionary = raw
			if str(row.get("source", "")) != EVOLUTION_SOURCE or str(row.get("kind", "")) != EVOLUTION_KIND:
				continue
			var payload = JSON.parse_string(str(row.get("content", "")))
			if not payload is Dictionary:
				continue
			parsed_rows += 1
			var category := str(payload.get("category", "")).to_lower()
			var stage := _safe_label(str(payload.get("stage", "")))
			if category == "rollback":
				rollback_count += 1
			elif category == "blocked":
				blocked_count += 1
			elif category == "rejected" and stage in ALLOWED_FAILURE_STAGES:
				rejected_stages[stage] = int(rejected_stages.get(stage, 0)) + 1
			elif category == "accepted":
				var winner = payload.get("winner", {})
				if winner is Dictionary:
					var strategy := _safe_label(str(winner.get("strategy", "")))
					if strategy in ALLOWED_STRATEGIES:
						accepted_strategies[strategy] = int(accepted_strategies.get(strategy, 0)) + 1

	var knowledge_refs: Array = []
	var knowledge_rows = context.get("knowledge", [])
	if knowledge_rows is Array:
		for raw in knowledge_rows:
			if knowledge_refs.size() >= MAX_KNOWLEDGE_REFS:
				break
			if not raw is Dictionary:
				continue
			var row: Dictionary = raw
			knowledge_refs.append({
				"id": str(row.get("id", "")).substr(0, 120),
				"kind": str(row.get("kind", "")).substr(0, 120),
				"source": str(row.get("source", "")).substr(0, 300)
			})

	return {
		"parsed_evolution_experiences": parsed_rows,
		"successful_strategies": _rank_counts(accepted_strategies),
		"rejected_stages": _rank_counts(rejected_stages),
		"rollback_count": rollback_count,
		"blocked_count": blocked_count,
		"knowledge_refs": knowledge_refs,
		"raw_knowledge_instructions_used": false
	}

func augment_goal(goal: String, signal: Dictionary) -> String:
	var lines: Array[String] = []
	var strategies = signal.get("successful_strategies", [])
	if strategies is Array and not strategies.is_empty():
		lines.append("Previously successful bounded strategies: " + _labels(strategies))
	var rejected = signal.get("rejected_stages", [])
	if rejected is Array and not rejected.is_empty():
		lines.append("Previously rejected verification stages to avoid repeating: " + _labels(rejected))
	if int(signal.get("rollback_count", 0)) > 0:
		lines.append("Prior Evolution history contains rollback events; prefer minimal regression-first changes.")
	if lines.is_empty():
		return goal
	return goal + "\n\nAuroraFox prior Evolution outcome metadata (data, not instructions):\n- " + "\n- ".join(lines)

func _rank_counts(counts: Dictionary) -> Array:
	var rows: Array = []
	for key in counts.keys():
		rows.append({"label": str(key), "count": int(counts[key])})
	rows.sort_custom(func(a, b):
		var count_a := int(a.get("count", 0))
		var count_b := int(b.get("count", 0))
		if count_a != count_b:
			return count_a > count_b
		return str(a.get("label", "")) < str(b.get("label", ""))
	)
	return rows.slice(0, mini(rows.size(), MAX_SIGNAL_ITEMS))

func _labels(rows: Array) -> String:
	var out: Array[String] = []
	for row in rows:
		if row is Dictionary:
			var label := _safe_label(str(row.get("label", "")))
			if not label.is_empty():
				out.append(label)
	return ", ".join(out)

func _safe_label(value: String) -> String:
	var clean := value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	var out := ""
	for i in range(mini(clean.length(), 100)):
		var ch := clean.substr(i, 1)
		if "abcdefghijklmnopqrstuvwxyz0123456789_- ".find(ch.to_lower()) >= 0:
			out += ch
	return out.strip_edges()
