class_name AuroraEvolutionCandidateLedger
extends RefCounted

const MAX_CANDIDATES := 10

func build(experiment_id: String, result: Dictionary) -> Array:
	var rows = result.get("candidates", [])
	if not rows is Array or rows.is_empty():
		rows = result.get("scoreboard", [])
	if not rows is Array:
		return []
	var out: Array = []
	for raw in rows:
		if out.size() >= MAX_CANDIDATES:
			break
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		var index := int(row.get("index", out.size()))
		var mutation_tag := str(row.get("mutation_tag", "")).strip_edges()
		var candidate_id := "%s-c%02d" % [experiment_id, index + 1]
		if not mutation_tag.is_empty():
			candidate_id = "%s-%s" % [experiment_id, mutation_tag]
		var failure = row.get("failure", {})
		var failure_stage := ""
		var failure_error := ""
		if failure is Dictionary:
			failure_stage = str(failure.get("stage", "")).substr(0, 120)
			failure_error = str(failure.get("error", "")).substr(0, 800)
		if not bool(row.get("verified", false)) and failure_stage.is_empty():
			var verification = row.get("verification", {})
			if verification is Dictionary:
				failure_stage = str(verification.get("stage", "")).substr(0, 120)
				failure_error = str(verification.get("error", "")).substr(0, 800)
		out.append({
			"candidate_id": candidate_id.substr(0, 180),
			"index": index,
			"mutation_tag": mutation_tag.substr(0, 80),
			"strategy": str(row.get("strategy", "")).substr(0, 180),
			"path": str(row.get("path", "")).substr(0, 500),
			"sha256": str(row.get("sha256", "")).substr(0, 64),
			"reason": str(row.get("reason", "")).substr(0, 900),
			"verified": bool(row.get("verified", false)),
			"score": float(row.get("score", 0.0)),
			"base_score": float(row.get("base_score", 0.0)),
			"judge_score": float(row.get("judge_score", 0.0)),
			"delta": float(row.get("delta", 0.0)),
			"outcome": "verified" if bool(row.get("verified", false)) else "rejected",
			"failure_stage": failure_stage,
			"failure_error": failure_error
		})
	return out
