extends SceneTree

class ContractTestAdapter:
	extends AuroraEvolutionCoreTournamentAdapter

	func _platform_supported() -> bool:
		return true

	func _platform_name() -> String:
		return "contract-test"

class FakeCorePipeline:
	extends RefCounted

	var ai := RefCounted.new()
	var tools := RefCounted.new()
	var _running := false
	var propose_calls := 0
	var verify_calls := 0
	var review_calls := 0
	var store_calls := 0
	var busy := false
	var baseline := "class_name DemoCore\nextends RefCounted\nfunc value():\n\treturn 1\n"

	func _bind_existing() -> void:
		pass

	func _signed_update_busy() -> bool:
		return busy

	func _select_target(_goal: String, requested: String) -> String:
		return requested if not requested.is_empty() else "scripts/agent_core.gd"

	func _read_res_source(_target: String) -> Dictionary:
		return {"ok": true, "content": baseline}

	func _propose(goal: String, target: String, _original: String) -> Dictionary:
		propose_calls += 1
		return {
			"ok": true,
			"proposal": {
				"path": target,
				"content": baseline + "\n# mutation_%d\n" % propose_calls,
				"reason": goal,
				"verification": "fake deterministic verification"
			}
		}

	func _validate_candidate(_target: String, original: String, proposal: Dictionary) -> Dictionary:
		var content := str(proposal.get("content", ""))
		return {
			"ok": not content.is_empty() and content != original,
			"source_contract": {"ok": true, "fake": true}
		}

	func _verify_in_workspace(_goal: String, _target: String, content: String) -> Dictionary:
		verify_calls += 1
		return {
			"ok": not content.is_empty(),
			"verification_mode": "fake_windows_workspace",
			"sandbox_path": "project/scripts/agent_core.gd",
			"benchmark": {"ok": true, "passed": 2, "failed": 0}
		}

	func _comparative_review(_goal: String, _target: String, _original: String, candidate: String, _verification: Dictionary, _proposal: Dictionary) -> Dictionary:
		review_calls += 1
		var bonus := float(candidate.length() % 10)
		return {
			"ok": true,
			"baseline_score": 70.0,
			"candidate_score": 80.0 + bonus,
			"delta": 10.0 + bonus,
			"minimum_delta": 1.0,
			"reasons": ["fake deterministic improvement"],
			"risks": []
		}

	func _store_candidate(_goal: String, target: String, _original: String, proposal: Dictionary, _verification: Dictionary) -> Dictionary:
		store_calls += 1
		return {
			"ok": true,
			"candidate_id": "fake_%d" % store_calls,
			"candidate_path": "user://core_candidates/fake/%s" % target,
			"manifest_path": "user://core_candidates/fake/candidate.json",
			"content": proposal.get("content", "")
		}

	func status() -> Dictionary:
		return {"running": _running}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var pipeline := FakeCorePipeline.new()
	var native_windows := OS.get_name() == "Windows"
	var adapter = AuroraEvolutionCoreTournamentAdapter.new() if native_windows else ContractTestAdapter.new()
	adapter.bind(pipeline)

	var contract := adapter.contract_status()
	if not bool(contract.get("ok", false)):
		_fail("Fake existing pipeline contract was rejected: " + JSON.stringify(contract), 2)
		return

	var tournament: Dictionary = await adapter.run("improve deterministic reliability", "scripts/agent_core.gd", 5)
	if not bool(tournament.get("ok", false)):
		_fail("Core tournament failed: " + JSON.stringify(tournament), 3)
		return
	if int(tournament.get("population_size", 0)) != 5 or int(tournament.get("verified_count", 0)) != 5:
		_fail("Core tournament did not evaluate five distinct verified candidates", 4)
		return
	if pipeline.propose_calls != 5:
		_fail("Core tournament did not generate exactly five candidates", 5)
		return
	if pipeline.store_calls != 0:
		_fail("Level 2 tournament stored/promoted a winner before handoff", 6)
		return
	if pipeline._running:
		_fail("Core pipeline lock was not released after tournament", 7)
		return
	if pipeline.verify_calls < 6 or pipeline.review_calls < 6:
		_fail("Winner did not receive an independent second verification/review", 8)
		return

	var tournament_id := str(tournament.get("tournament_id", ""))
	if tournament_id.is_empty():
		_fail("Core tournament did not return a handoff token", 9)
		return

	var handoff: Dictionary = await adapter.prepare_winner(tournament_id)
	if not bool(handoff.get("ok", false)):
		_fail("Core promotion handoff failed: " + JSON.stringify(handoff), 10)
		return
	if pipeline.store_calls != 1:
		_fail("Promotion handoff did not store exactly one winner", 11)
		return
	if pipeline._running:
		_fail("Core pipeline lock was not released after handoff", 12)
		return
	if bool(handoff.get("applied_to_dev_checkout", true)):
		_fail("Core promotion handoff applied code directly to dev checkout", 13)
		return
	if str(handoff.get("promotion", "")) != "signed_update":
		_fail("Core promotion handoff bypassed signed-update authority", 14)
		return
	if pipeline.verify_calls < 7 or pipeline.review_calls < 7:
		_fail("Level 3 handoff did not cleanly reverify the winner", 15)
		return

	var replay: Dictionary = await adapter.prepare_winner(tournament_id)
	if bool(replay.get("ok", false)):
		_fail("Consumed Core tournament winner could be replayed", 16)
		return

	pipeline.busy = true
	var update_blocked: Dictionary = await adapter.run("blocked during update", "scripts/agent_core.gd", 5)
	if bool(update_blocked.get("ok", false)) or str(update_blocked.get("stage", "")) != "update_guard":
		_fail("Signed update activity did not block Core tournament", 17)
		return

	print("AURORA_CORE_TOURNAMENT_SMOKE_OK population=5 handoff=1 second_verify=true signed_update=true lock=true native_windows=%s" % str(native_windows).to_lower())
	quit(0)

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
