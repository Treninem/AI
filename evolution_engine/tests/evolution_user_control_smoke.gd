extends SceneTree

class FakeRuntime:
	extends Node
	var level := 0
	var managed := false
	var authorization_calls := 0
	var managed_calls := 0
	var experiment_calls := 0
	var end_calls := 0
	var last_confirmation := false

	func status() -> Dictionary:
		return {
			"ok": true,
			"bound": true,
			"session_permission_level": level,
			"user_authorized": level > 0,
			"managed_session": managed,
			"release_authority": false
		}

	func authorize_session_level(value: int, user_confirmed: bool) -> Dictionary:
		authorization_calls += 1
		last_confirmation = user_confirmed
		if not user_confirmed:
			return {"ok": false, "stage": "user_confirmation"}
		level = value
		return {"ok": true, "permission_level": level, "persisted": false}

	func begin_managed_session(value: int, user_confirmed: bool) -> Dictionary:
		managed_calls += 1
		last_confirmation = user_confirmed
		if not user_confirmed:
			return {"ok": false, "stage": "user_confirmation"}
		level = value
		managed = true
		return {"ok": true, "permission_level": level, "managed": true}

	func end_managed_session() -> Dictionary:
		end_calls += 1
		level = 0
		managed = false
		return {"ok": true, "permission_level": 0}

	func run_cycle_from_user(goal: String, mode: String, target: String, count: int, user_confirmed: bool) -> Dictionary:
		experiment_calls += 1
		last_confirmation = user_confirmed
		return {
			"ok": user_confirmed,
			"goal": goal,
			"mode": mode,
			"target": target,
			"population_size": count,
			"release_authority": false
		}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var fake := FakeRuntime.new()
	fake.name = "EvolutionRuntime"
	root.add_child(fake)
	var surface := AuroraEvolutionUserControlSurface.new()
	surface.name = "UserControlSurface"
	fake.add_child(surface)
	await process_frame

	var pending := surface.request_session_level(AuroraEvolutionPolicy.LEVEL_SANDBOX_EXPERIMENT)
	if not bool(pending.get("pending_confirmation", false)) or fake.managed_calls != 0:
		_fail("session permission executed before confirmation", 1)
		return
	var cancelled := surface.cancel_pending_action()
	if not bool(cancelled.get("ok", false)) or fake.managed_calls != 0:
		_fail("cancelled session action executed", 2)
		return

	surface.request_session_level(AuroraEvolutionPolicy.LEVEL_PROPOSAL)
	var proposal_level := await surface.confirm_pending_action()
	if not bool(proposal_level.get("ok", false)) or fake.authorization_calls != 1 or not fake.last_confirmation or fake.level != 1 or fake.managed:
		_fail("confirmed Level 1 session was not applied safely", 3)
		return

	surface.request_session_level(AuroraEvolutionPolicy.LEVEL_SANDBOX_EXPERIMENT)
	var managed_level := await surface.confirm_pending_action()
	if not bool(managed_level.get("ok", false)) or fake.managed_calls != 1 or not fake.managed or fake.level != 2:
		_fail("confirmed managed session was not applied", 4)
		return

	var invalid_population := surface.request_experiment("improve safely", "hot", "", 2)
	if str(invalid_population.get("stage", "")) != "population" or fake.experiment_calls != 0:
		_fail("invalid mutation population reached runtime", 5)
		return
	var experiment_pending := surface.request_experiment("improve safely", "hot", "", 5)
	if not bool(experiment_pending.get("pending_confirmation", false)) or fake.experiment_calls != 0:
		_fail("experiment executed before confirmation", 6)
		return
	var experiment := await surface.confirm_pending_action()
	if not bool(experiment.get("ok", false)) or fake.experiment_calls != 1 or int(experiment.get("population_size", 0)) != 5 or not fake.last_confirmation:
		_fail("confirmed experiment did not preserve safety contract", 7)
		return
	var replay := await surface.confirm_pending_action()
	if bool(replay.get("ok", false)) or fake.experiment_calls != 1:
		_fail("confirmation replay executed an action twice", 8)
		return

	var ended := surface.end_session_from_user()
	if not bool(ended.get("ok", false)) or fake.end_calls != 1 or fake.level != 0 or fake.managed:
		_fail("ending user session did not restore Level 0", 9)
		return
	if bool(surface.status().get("pending_confirmation", true)):
		_fail("pending confirmation survived session end", 10)
		return

	print("AURORA_EVOLUTION_USER_CONTROL_SMOKE_OK confirm=true cancel=true population=3..10 replay=false reset=true release_authority=false")
	fake.queue_free()
	await process_frame
	quit(0)

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
