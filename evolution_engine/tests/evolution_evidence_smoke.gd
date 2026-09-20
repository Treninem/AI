extends SceneTree

const SHA1 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const SHA2 := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const SHA3 := "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
const SHA4 := "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
const SHA5 := "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

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

	var duplicate := valid.duplicate(true)
	duplicate["scoreboard"] = (valid["scoreboard"] as Array).duplicate(true)
	duplicate["scoreboard"][1] = (duplicate["scoreboard"][1] as Dictionary).duplicate(true)
	duplicate["scoreboard"][1]["sha256"] = SHA1
	if bool(gate.validate_tournament(duplicate).get("ok", false)):
		_fail("Duplicate candidate SHA was accepted", 4)
		return

	var unverified := valid.duplicate(true)
	unverified["winner"] = (valid["winner"] as Dictionary).duplicate(true)
	unverified["winner"]["verified"] = false
	if bool(gate.validate_tournament(unverified).get("ok", false)):
		_fail("Unverified winner was accepted", 5)
		return

	var bad_sha := valid.duplicate(true)
	bad_sha["sha256"] = "not-a-sha"
	if bool(gate.validate_tournament(bad_sha).get("ok", false)):
		_fail("Invalid SHA-256 was accepted", 6)
		return

	var mismatched_sha := valid.duplicate(true)
	mismatched_sha["sha256"] = SHA2
	if bool(gate.validate_tournament(mismatched_sha).get("ok", false)):
		_fail("Staged SHA different from winner was accepted", 7)
		return

	var bad_path := valid.duplicate(true)
	bad_path["stage_path"] = "res://scripts/main.gd"
	if bool(gate.validate_tournament(bad_path).get("ok", false)):
		_fail("Unsafe staging path was accepted", 8)
		return

	print("AURORA_EVOLUTION_EVIDENCE_SMOKE_OK population=3..10 distinct=true leader=true staging=true")
	quit(0)

func _valid_result() -> Dictionary:
	return {
		"ok": true,
		"verified": true,
		"staged": true,
		"population_size": 5,
		"verified_count": 5,
		"stage_path": "user://generated/winner.gd",
		"path": "res://generated/winner.gd",
		"sha256": SHA1,
		"scoreboard": [
			{"index": 0, "verified": true, "score": 95.0, "sha256": SHA1},
			{"index": 1, "verified": true, "score": 90.0, "sha256": SHA2},
			{"index": 2, "verified": true, "score": 85.0, "sha256": SHA3},
			{"index": 3, "verified": true, "score": 80.0, "sha256": SHA4},
			{"index": 4, "verified": true, "score": 75.0, "sha256": SHA5}
		],
		"winner": {"verified": true, "sha256": SHA1, "path": "res://generated/winner.gd"},
		"final_verification": {"ok": true}
	}

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
