class_name AuroraEvolutionPolicy
extends RefCounted

const LEVEL_ANALYSIS := 0
const LEVEL_PROPOSAL := 1
const LEVEL_SANDBOX_EXPERIMENT := 2
const LEVEL_PROMOTION_HANDOFF := 3
const LEVEL_VERIFIED_ACTIVATION := 4

const MIN_MUTATIONS := 3
const MAX_MUTATIONS := 10

var permission_level := LEVEL_ANALYSIS

func set_permission_level(value: int) -> int:
	permission_level = clampi(value, LEVEL_ANALYSIS, LEVEL_VERIFIED_ACTIVATION)
	return permission_level

func can_analyze() -> bool:
	return true

func can_propose() -> bool:
	return permission_level >= LEVEL_PROPOSAL

func can_experiment() -> bool:
	return permission_level >= LEVEL_SANDBOX_EXPERIMENT

func can_prepare_promotion() -> bool:
	return permission_level >= LEVEL_PROMOTION_HANDOFF

func can_activate_verified_extension() -> bool:
	return permission_level >= LEVEL_VERIFIED_ACTIVATION

func valid_population_size(value: int) -> bool:
	return value >= MIN_MUTATIONS and value <= MAX_MUTATIONS

func clamp_population_size(value: int) -> int:
	return clampi(value, MIN_MUTATIONS, MAX_MUTATIONS)

func master_enabled(settings: Dictionary) -> bool:
	return bool(settings.get("master_enabled", true))

func status() -> Dictionary:
	return {
		"permission_level": permission_level,
		"can_analyze": can_analyze(),
		"can_propose": can_propose(),
		"can_experiment": can_experiment(),
		"can_prepare_promotion": can_prepare_promotion(),
		"can_activate_verified_extension": can_activate_verified_extension(),
		"mutation_min": MIN_MUTATIONS,
		"mutation_max": MAX_MUTATIONS
	}
