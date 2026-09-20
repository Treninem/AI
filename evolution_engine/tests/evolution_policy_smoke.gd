extends SceneTree

func _init() -> void:
	var policy := AuroraEvolutionPolicy.new()
	if policy.permission_level != AuroraEvolutionPolicy.LEVEL_ANALYSIS:
		_fail("Default permission level must be analysis-only", 2)
		return
	if policy.can_propose() or policy.can_experiment() or policy.can_activate_verified_extension():
		_fail("Analysis-only level exposed mutation/activation capability", 3)
		return
	policy.set_permission_level(AuroraEvolutionPolicy.LEVEL_SANDBOX_EXPERIMENT)
	if not policy.can_propose() or not policy.can_experiment() or policy.can_activate_verified_extension():
		_fail("Level 2 permission contract is invalid", 4)
		return
	for value in [3, 5, 10]:
		if not policy.valid_population_size(value):
			_fail("Valid mutation population was rejected: " + str(value), 5)
			return
	for value in [0, 1, 2, 11, 20]:
		if policy.valid_population_size(value):
			_fail("Invalid mutation population was accepted: " + str(value), 6)
			return
	if policy.master_enabled({"master_enabled": false}):
		_fail("Master stop was ignored", 7)
		return
	policy.set_permission_level(AuroraEvolutionPolicy.LEVEL_VERIFIED_ACTIVATION)
	if not policy.can_activate_verified_extension():
		_fail("Level 4 did not unlock verified activation", 8)
		return
	print("AURORA_EVOLUTION_POLICY_SMOKE_OK levels=0..4 tournament=3..10")
	quit(0)

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
