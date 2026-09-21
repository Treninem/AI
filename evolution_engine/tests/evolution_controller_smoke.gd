extends SceneTree

const SHA1 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const SHA2 := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const SHA3 := "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
const SHA4 := "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
const SHA5 := "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

class FakeCoordinator:
	extends RefCounted
	var sync_calls := 0
	var _cycle_running := false
	var autonomous_hot_improvements := true

	func synchronize_all() -> Dictionary:
		sync_calls += 1
		return {"ok": true, "compatible": true, "observations": {}}

class FakeImprover:
	extends RefCounted
	var tournament_calls := 0

	func propose_improvement(goal: String, mutation_index := 0, strategy := "balanced", previous_signatures: Array = []) -> Dictionary:
		return {
			"ok": true,
			"proposal": {
				"path": "res://generated/preview.gd",
				"content": "extends RefCounted",
				"reason": goal,
				"mutation_index": mutation_index,
				"strategy": strategy,
				"previous_count": previous_signatures.size()
			}
		}

	func run_mutation_tournament(goal: String, requested_count := 5) -> Dictionary:
		tournament_calls += 1
		var hashes := [SHA1, SHA2, SHA3, SHA4, SHA5]
		var scoreboard: Array = []
		for i in range(requested_count):
			scoreboard.append({
				"index": i,
				"verified": true,
				"score": 90.0 - float(i),
				"sha256": hashes[i],
				"path": "res://generated/fake.gd"
			})
		return {
			"ok": true,
			"verified": true,
			"staged": true,
			"goal": goal,
			"population_size": requested_count,
			"verified_count": requested_count,
			"stage_path": "user://generated/fake.gd",
			"path": "res://generated/fake.gd",
			"sha256": SHA1,
			"scoreboard": scoreboard,
			"final_verification": {"ok": true, "mode": "fake"},
			"winner": {
				"mutation_tag": "m01",
				"strategy": "balanced",
				"path": "res://generated/fake.gd",
				"sha256": SHA1,
				"score": 90.0,
				"verified": true
			}
		}

class FakeExtensions:
	extends RefCounted
	var activations := 0
	var deactivations := 0

	func activate_staged(stage_path: String, expected_sha256 := "") -> Dictionary:
		activations += 1
		return {"ok": not stage_path.is_empty() and expected_sha256 == SHA1, "id": "fake", "tools": []}

	func deactivate(id: String) -> Dictionary:
		deactivations += 1
		return {"ok": not id.is_empty(), "id": id}

class FakeMemory:
	extends RefCounted
	var records := 0

	func remember(_kind: String, _content: String, _source := "", _importance := 0.55, _confidence := 0.85) -> void:
		records += 1

	func retrieve(_query: String, _limit := 8, _include_memory := true, _include_knowledge := true) -> Array:
		return [{"id": "memory-1", "kind": "evolution_experience", "content": "prior safe result", "source": "test"}]

class FakeKnowledge:
	extends RefCounted
	func search(_query: String, _limit := 6) -> Array:
		return [{"id": "knowledge-1", "kind": "knowledge", "text": "existing AuroraFox knowledge", "source": "test"}]

class FakeCorePipeline:
	extends RefCounted
	func status() -> Dictionary:
		return {"ok": true}

class FakeAutonomySettings:
	extends RefCounted
	var master := true
	func get_settings() -> Dictionary:
		return {"master_enabled": master}

class FakeUpdateGuard:
	extends RefCounted
	var paused := false
	var updater_bound := true
	func status() -> Dictionary:
		return {
			"paused_hot_improvements": paused,
			"paused_core_candidates": paused,
			"reason": "test update" if paused else "",
			"updater_bound": updater_bound
		}

class FakeSandbox:
	extends RefCounted
	func snapshot(_label := "checkpoint") -> Dictionary:
		return {"ok": true, "snapshot": "fake"}
	func rollback(_snapshot_ref: String) -> Dictionary:
		return {"ok": true}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var coordinator := FakeCoordinator.new()
	var improver := FakeImprover.new()
	var extensions := FakeExtensions.new()
	var memory := FakeMemory.new()
	var knowledge := FakeKnowledge.new()
	var core := FakeCorePipeline.new()
	var settings := FakeAutonomySettings.new()
	var update_guard := FakeUpdateGuard.new()
	var sandbox := FakeSandbox.new()
	var engine := AuroraEvolutionEngine.new()

	var bound := engine.bind_foundation(
		coordinator, improver, extensions, memory, knowledge,
		core, settings, update_guard, sandbox
	)
	if not bool(bound.get("ok", false)):
		_fail("Existing foundation did not bind: " + JSON.stringify(bound), 2)
		return

	var denied_proposal: Dictionary = await engine.propose("improve safely")
	if bool(denied_proposal.get("ok", false)) or str(denied_proposal.get("stage", "")) != "permission":
		_fail("Level 0 unexpectedly allowed proposal generation", 3)
		return

	engine.set_permission_level(AuroraEvolutionPolicy.LEVEL_SANDBOX_EXPERIMENT)
	var unmanaged: Dictionary = await engine.run_experiment("must require managed mode", 5)
	if bool(unmanaged.get("ok", false)) or str(unmanaged.get("stage", "")) != "managed_mode":
		_fail("Level 2 experiment bypassed managed mode", 4)
		return

	var managed := engine.enter_managed_mode()
	if not bool(managed.get("ok", false)) or coordinator.autonomous_hot_improvements:
		_fail("Managed mode did not disable legacy hot auto-activation", 5)
		return

	var analysis: Dictionary = await engine.analyze("improve safely")
	if not bool(analysis.get("ok", false)):
		_fail("Analysis failed: " + JSON.stringify(analysis), 6)
		return
	var experience_context = analysis.get("experience_context", {})
	if not experience_context is Dictionary or not bool(experience_context.get("ok", false)):
		_fail("Existing Memory/Knowledge context was not reused", 7)
		return

	var tournament_result: Dictionary = await engine.run_experiment("improve safely", 5)
	if not bool(tournament_result.get("ok", false)):
		_fail("Level 2 tournament failed: " + JSON.stringify(tournament_result), 8)
		return
	if not bool(tournament_result.get("evolution_evidence", {}).get("ok", false)):
		_fail("Tournament evidence gate did not accept complete existing evidence", 9)
		return
	if bool(tournament_result.get("activation_performed", true)) or extensions.activations != 0:
		_fail("Experiment auto-activated a staged winner", 10)
		return
	if coordinator.autonomous_hot_improvements:
		_fail("Exclusive guard incorrectly restored legacy hot auto-activation while managed mode is active", 11)
		return

	coordinator._cycle_running = true
	var concurrent_blocked: Dictionary = await engine.run_experiment("must not overlap", 5)
	if bool(concurrent_blocked.get("ok", false)) or str(concurrent_blocked.get("stage", "")) != "exclusive_guard":
		_fail("Existing autonomous cycle did not block Evolution tournament", 12)
		return
	coordinator._cycle_running = false

	var denied_activation: Dictionary = engine.activate_verified_winner("improve safely", tournament_result)
	if bool(denied_activation.get("ok", false)):
		_fail("Level 2 unexpectedly allowed activation", 13)
		return

	update_guard.paused = true
	var update_blocked: Dictionary = await engine.run_experiment("blocked by update", 5)
	if bool(update_blocked.get("ok", false)) or str(update_blocked.get("stage", "")) != "update_guard":
		_fail("UpdateAutonomyGuard did not block Evolution experiment", 14)
		return
	update_guard.paused = false

	engine.set_permission_level(AuroraEvolutionPolicy.LEVEL_VERIFIED_ACTIVATION)
	var forged := tournament_result.duplicate(true)
	forged["sha256"] = "bad"
	var forged_activation: Dictionary = engine.activate_verified_winner("forged", forged)
	if bool(forged_activation.get("ok", false)) or str(forged_activation.get("stage", "")) != "activation_lineage" or extensions.activations != 0:
		_fail("Forged tournament evidence reached activation", 16)
		return

	var activated: Dictionary = engine.activate_verified_winner("improve safely", tournament_result)
	if not bool(activated.get("ok", false)) or extensions.activations != 1:
		_fail("Verified Level 4 activation did not delegate to RuntimeExtensionManager", 15)
		return

	var replay_activation: Dictionary = engine.activate_verified_winner("replay", tournament_result)
	if bool(replay_activation.get("ok", false)) or str(replay_activation.get("stage", "")) != "activation_lineage" or extensions.activations != 1:
		_fail("Consumed tournament winner was activated more than once", 21)
		return

	settings.master = false
	var rolled_back: Dictionary = engine.rollback_hot_extension("fake", "emergency smoke rollback")
	if not bool(rolled_back.get("ok", false)) or extensions.deactivations != 1:
		_fail("Emergency rollback was blocked or did not use RuntimeExtensionManager.deactivate", 17)
		return
	var master_blocked: Dictionary = await engine.analyze("must stop")
	if bool(master_blocked.get("ok", false)) or str(master_blocked.get("stage", "")) != "master_stop":
		_fail("Master stop did not fail closed", 18)
		return

	settings.master = true
	update_guard.updater_bound = false
	var unbound_update_guard: Dictionary = await engine.run_experiment("must stop", 5)
	if bool(unbound_update_guard.get("ok", false)) or str(unbound_update_guard.get("stage", "")) != "update_guard":
		_fail("Unbound updater did not fail closed", 19)
		return
	update_guard.updater_bound = true

	var left := engine.leave_managed_mode()
	if not bool(left.get("ok", false)) or not coordinator.autonomous_hot_improvements:
		_fail("Leaving managed mode did not restore legacy hot-improvement setting", 20)
		return

	engine.queue_free()
	print("AURORA_EVOLUTION_CONTROLLER_SMOKE_OK managed=true context=true evidence=true exclusive=true rollback=true master_stop=true update_guard=true staged_activation=true replay_blocked=true")
	quit(0)

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
