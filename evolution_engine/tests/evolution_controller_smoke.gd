extends SceneTree

const SHA64 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

class FakeCoordinator:
	extends RefCounted
	var sync_calls := 0
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
		return {
			"ok": true,
			"verified": true,
			"staged": true,
			"goal": goal,
			"population_size": requested_count,
			"verified_count": requested_count,
			"stage_path": "user://generated/fake.gd",
			"sha256": SHA64,
			"winner": {
				"mutation_tag": "m01",
				"strategy": "balanced",
				"path": "res://generated/fake.gd",
				"sha256": SHA64,
				"score": 91.0,
				"verified": true
			}
		}

class FakeExtensions:
	extends RefCounted
	var activations := 0
	func activate_staged(stage_path: String, expected_sha256 := "") -> Dictionary:
		activations += 1
		return {"ok": not stage_path.is_empty() and expected_sha256 == SHA64, "id": "fake", "tools": []}

class FakeMemory:
	extends RefCounted
	var records := 0
	func remember(_kind: String, _content: String, _source := "", _importance := 0.55, _confidence := 0.85) -> void:
		records += 1

class FakeKnowledge:
	extends RefCounted
	func search(_query: String, _limit := 6) -> Array:
		return []

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
		coordinator,
		improver,
		extensions,
		memory,
		knowledge,
		core,
		settings,
		update_guard,
		sandbox
	)
	if not bool(bound.get("ok", false)):
		_fail("Existing foundation did not bind: " + JSON.stringify(bound), 2)
		return

	var denied_proposal: Dictionary = await engine.propose("improve safely")
	if bool(denied_proposal.get("ok", false)) or str(denied_proposal.get("stage", "")) != "permission":
		_fail("Level 0 unexpectedly allowed proposal generation", 3)
		return

	engine.set_permission_level(AuroraEvolutionPolicy.LEVEL_SANDBOX_EXPERIMENT)
	var tournament_result: Dictionary = await engine.run_experiment("improve safely", 5)
	if not bool(tournament_result.get("ok", false)):
		_fail("Level 2 tournament failed: " + JSON.stringify(tournament_result), 4)
		return
	if bool(tournament_result.get("activation_performed", true)):
		_fail("Experiment auto-activated a staged winner", 5)
		return
	if extensions.activations != 0:
		_fail("RuntimeExtensionManager was called before Level 4", 6)
		return
	if improver.tournament_calls != 1 or memory.records != 1:
		_fail("Existing SelfImprover/MemoryStore adapters were not used exactly once", 7)
		return

	var denied_activation: Dictionary = engine.activate_verified_winner("improve safely", tournament_result)
	if bool(denied_activation.get("ok", false)):
		_fail("Level 2 unexpectedly allowed activation", 8)
		return

	update_guard.paused = true
	var update_blocked: Dictionary = await engine.run_experiment("blocked by update", 5)
	if bool(update_blocked.get("ok", false)) or str(update_blocked.get("stage", "")) != "update_guard":
		_fail("UpdateAutonomyGuard did not block Evolution experiment", 9)
		return
	update_guard.paused = false

	engine.set_permission_level(AuroraEvolutionPolicy.LEVEL_VERIFIED_ACTIVATION)
	var activated: Dictionary = engine.activate_verified_winner("improve safely", tournament_result)
	if not bool(activated.get("ok", false)) or extensions.activations != 1:
		_fail("Verified Level 4 activation did not delegate to RuntimeExtensionManager", 10)
		return

	settings.master = false
	var master_blocked: Dictionary = await engine.analyze("must stop")
	if bool(master_blocked.get("ok", false)) or str(master_blocked.get("stage", "")) != "master_stop":
		_fail("Master stop did not fail closed", 11)
		return

	settings.master = true
	update_guard.updater_bound = false
	var unbound_update_guard: Dictionary = await engine.run_experiment("must stop", 5)
	if bool(unbound_update_guard.get("ok", false)) or str(unbound_update_guard.get("stage", "")) != "update_guard":
		_fail("Unbound updater did not fail closed", 12)
		return

	engine.queue_free()
	print("AURORA_EVOLUTION_CONTROLLER_SMOKE_OK reuse=true master_stop=true update_guard=true staged_activation=true")
	quit(0)

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
