extends SceneTree

const SHA64 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

func _init() -> void:
	var gate := AuroraEvolutionEvidenceGate.new()
	var valid := _valid_result()
	var accepted := gate.validate_tournament(valid)
	if not bool(accepted.get("ok", false)):
		_fail("Complete tournament evidence was rejected: " + JSON.stringify(accepted), 2)
		return

	var too_small := valid.duplicate(true)
	too_small["population_size"] = 2
	if bool(gate.validate_tournament(too_small).get("ok", false)):
		_fail("Population below three was accepted", 3)
		return

	var unverified := valid.duplicate(true)
	unverified["winner"] = (valid["winner"] as Dictionary).duplicate(true)
	unverified["winner"]["verified"] = false
	if bool(gate.validate_tournament(unverified).get("ok", false)):
		_fail("Unverified winner was accepted", 4)
		return

	var bad_sha := valid.duplicate(true)
	bad_sha["sha256"] = "not-a-sha"
	if bool(gate.validate_tournament(bad_sha).get("ok", false)):
		_fail("Invalid SHA-256 was accepted", 5)
		return

	var bad_path := valid.duplicate(true)
	bad_path["stage_path"] = "res://scripts/main.gd"
	if bool(gate.validate_tournament(bad_path).get("ok", false)):
		_fail("Unsafe staging path was accepted", 6)
		return

	print("AURORA_EVOLUTION_EVIDENCE_SMOKE_OK population=3..10 verified=true staging=true")
	quit(0)

func _valid_result() -> Dictionary:
	return {
		"ok": true,
		"verified": true,
		"staged": true,
		"population_size": 5,
		"verified_count": 5,
		"stage_path": "user://generated/winner.gd",
		"sha256": SHA64,
		"scoreboard": [
			{"index": 0, "verified": true},
			{"index": 1, "verified": true},
			{"index": 2, "verified": true},
			{"index": 3, "verified": true},
			{"index": 4, "verified": true}
		],
		"winner": {"verified": true, "sha256": SHA64},
		"final_verification": {"ok": true}
	}

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
