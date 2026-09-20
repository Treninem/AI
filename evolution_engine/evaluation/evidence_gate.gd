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
	if not scoreboard is Array or scoreboard.size() < MIN_MUTATIONS:
		return {"ok": false, "reason": "scoreboard_incomplete"}
	var winner = result.get("winner", {})
	if not winner is Dictionary or not bool(winner.get("verified", false)):
		return {"ok": false, "reason": "winner_not_verified"}
	if not bool(result.get("verified", false)) or not bool(result.get("staged", false)):
		return {"ok": false, "reason": "final_stage_not_verified"}
	var stage_path := str(result.get("stage_path", ""))
	if not _allowed_stage_path(stage_path):
		return {"ok": false, "reason": "unsafe_stage_path", "stage_path": stage_path}
	var sha256 := str(result.get("sha256", "")).to_lower()
	if not _is_sha256(sha256):
		return {"ok": false, "reason": "invalid_stage_sha256"}
	var final_verification = result.get("final_verification", {})
	if not final_verification is Dictionary or final_verification.is_empty():
		return {"ok": false, "reason": "final_verification_missing"}
	return {
		"ok": true,
		"population_size": population,
		"verified_count": verified,
		"stage_path": stage_path,
		"sha256": sha256
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
