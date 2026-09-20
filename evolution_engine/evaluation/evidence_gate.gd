class_name AuroraEvolutionEvidenceGate
extends RefCounted

const MIN_MUTATIONS := 3
const MAX_MUTATIONS := 10
const HEX := "0123456789abcdef"

func validate_tournament(result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)):
		return {"ok": false, "reason": "tournament_not_accepted"}
	var population := int(result.get("population_size", 0))
	var verified := int(result.get("verified_count", 0))
	if population < MIN_MUTATIONS or population > MAX_MUTATIONS:
		return {"ok": false, "reason": "population_out_of_bounds", "population_size": population}
	if verified < MIN_MUTATIONS or verified > population:
		return {"ok": false, "reason": "verified_population_invalid", "verified_count": verified, "population_size": population}

	var scoreboard = result.get("scoreboard", [])
	if not scoreboard is Array or scoreboard.size() != verified:
		return {"ok": false, "reason": "scoreboard_count_mismatch", "scoreboard_size": scoreboard.size() if scoreboard is Array else 0, "verified_count": verified}

	var seen: Dictionary = {}
	var ordered_hashes: Array[String] = []
	for row in scoreboard:
		if not row is Dictionary:
			return {"ok": false, "reason": "scoreboard_row_invalid"}
		if not bool(row.get("verified", false)):
			return {"ok": false, "reason": "scoreboard_contains_unverified_candidate"}
		var row_sha := str(row.get("sha256", "")).to_lower()
		if not _is_sha256(row_sha):
			return {"ok": false, "reason": "scoreboard_candidate_sha_invalid"}
		if seen.has(row_sha):
			return {"ok": false, "reason": "scoreboard_duplicate_candidate", "sha256": row_sha}
		seen[row_sha] = true
		ordered_hashes.append(row_sha)

	var winner = result.get("winner", {})
	if not winner is Dictionary or not bool(winner.get("verified", false)):
		return {"ok": false, "reason": "winner_not_verified"}
	var winner_sha := str(winner.get("sha256", "")).to_lower()
	if not _is_sha256(winner_sha):
		return {"ok": false, "reason": "winner_sha_invalid"}
	if not seen.has(winner_sha):
		return {"ok": false, "reason": "winner_missing_from_scoreboard"}
	if ordered_hashes.is_empty() or ordered_hashes[0] != winner_sha:
		return {"ok": false, "reason": "winner_is_not_scoreboard_leader"}

	if not bool(result.get("verified", false)) or not bool(result.get("staged", false)):
		return {"ok": false, "reason": "final_stage_not_verified"}
	var stage_path := str(result.get("stage_path", ""))
	if not _allowed_stage_path(stage_path):
		return {"ok": false, "reason": "unsafe_stage_path", "stage_path": stage_path}
	var sha256 := str(result.get("sha256", "")).to_lower()
	if not _is_sha256(sha256):
		return {"ok": false, "reason": "invalid_stage_sha256"}
	if sha256 != winner_sha:
		return {"ok": false, "reason": "winner_stage_sha_mismatch"}

	var final_verification = result.get("final_verification", {})
	if not final_verification is Dictionary or final_verification.is_empty():
		return {"ok": false, "reason": "final_verification_missing"}
	if not bool(final_verification.get("ok", false)):
		return {"ok": false, "reason": "final_verification_not_ok"}

	return {
		"ok": true,
		"population_size": population,
		"verified_count": verified,
		"stage_path": stage_path,
		"sha256": sha256,
		"winner_sha256": winner_sha
	}

func _allowed_stage_path(path: String) -> bool:
	return path.begins_with("user://generated/") or path.begins_with("res://generated/")

func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for i in range(value.length()):
		if HEX.find(value.substr(i, 1)) < 0:
			return false
	return true
