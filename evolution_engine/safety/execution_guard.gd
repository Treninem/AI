class_name AuroraEvolutionExecutionGuard
extends RefCounted

const DEFAULT_STALE_SECONDS := 14400

var coordinator
var _held := false
var _saved_hot_improvements := false
var _acquired_at := 0

func bind(value) -> void:
	coordinator = value

func acquire() -> Dictionary:
	if _held:
		return {"ok": false, "stage": "exclusive_guard", "error": "Evolution exclusive guard is already held"}
	if coordinator == null:
		return {"ok": false, "stage": "exclusive_guard", "error": "AutonomousCoordinator is unavailable"}
	var cycle_running = coordinator.get("_cycle_running")
	if cycle_running == null:
		return {"ok": false, "stage": "exclusive_guard", "error": "AutonomousCoordinator cycle state is unavailable"}
	if bool(cycle_running):
		return {"ok": false, "stage": "exclusive_guard", "error": "Existing autonomous cycle is already running"}
	var hot = coordinator.get("autonomous_hot_improvements")
	if hot == null:
		return {"ok": false, "stage": "exclusive_guard", "error": "AutonomousCoordinator hot-improvement state is unavailable"}
	_saved_hot_improvements = bool(hot)
	coordinator.set("autonomous_hot_improvements", false)
	_held = true
	_acquired_at = int(Time.get_unix_time_from_system())
	return {"ok": true, "held": true, "saved_hot_improvements": _saved_hot_improvements}

func release() -> Dictionary:
	if not _held:
		return {"ok": true, "released": false}
	return _restore_state()

func emergency_release(reason := "unknown") -> Dictionary:
	if not _held:
		return {"ok": true, "released": false, "reason": reason}
	var result := _restore_state()
	result["reason"] = reason.substr(0, 500)
	result["emergency"] = true
	return result

func stale_status(max_age_seconds := DEFAULT_STALE_SECONDS) -> Dictionary:
	if not _held:
		return {"held": false, "stale": false, "held_seconds": 0}
	var now := int(Time.get_unix_time_from_system())
	var age := maxi(0, now - _acquired_at) if _acquired_at > 0 else max_age_seconds
	return {
		"held": true,
		"stale": age >= max_age_seconds,
		"held_seconds": age,
		"threshold_seconds": max_age_seconds
	}

func _restore_state() -> Dictionary:
	if coordinator != null:
		coordinator.set("autonomous_hot_improvements", _saved_hot_improvements)
	var restored := _saved_hot_improvements
	_held = false
	_acquired_at = 0
	return {"ok": true, "released": true, "restored_hot_improvements": restored}

func status() -> Dictionary:
	var held_seconds := 0
	if _held and _acquired_at > 0:
		held_seconds = maxi(0, int(Time.get_unix_time_from_system()) - _acquired_at)
	return {
		"held": _held,
		"saved_hot_improvements": _saved_hot_improvements,
		"acquired_at": _acquired_at,
		"held_seconds": held_seconds
	}
