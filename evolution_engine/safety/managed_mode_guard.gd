class_name AuroraEvolutionManagedModeGuard
extends RefCounted

var coordinator
var _active := false
var _saved_hot_improvements := false
var _fail_closed := false
var _entered_at := 0

func bind(value) -> void:
	coordinator = value

func enter() -> Dictionary:
	if _active:
		if coordinator == null:
			return {"ok": false, "stage": "managed_mode", "error": "AutonomousCoordinator is unavailable"}
		coordinator.set("autonomous_hot_improvements", false)
		_fail_closed = not permits_evolution()
		return {
			"ok": true,
			"active": true,
			"already_active": true,
			"legacy_hot_improvements": false,
			"saved_hot_improvements": _saved_hot_improvements
		}
	if coordinator == null:
		return {"ok": false, "stage": "managed_mode", "error": "AutonomousCoordinator is unavailable"}
	var cycle_running = coordinator.get("_cycle_running")
	if cycle_running == null:
		return {"ok": false, "stage": "managed_mode", "error": "AutonomousCoordinator cycle state is unavailable"}
	if bool(cycle_running):
		return {"ok": false, "stage": "managed_mode", "error": "Cannot enter Evolution managed mode while legacy autonomous cycle is running"}
	var hot = coordinator.get("autonomous_hot_improvements")
	if hot == null:
		return {"ok": false, "stage": "managed_mode", "error": "Legacy hot-improvement state is unavailable"}
	_saved_hot_improvements = bool(hot)
	coordinator.set("autonomous_hot_improvements", false)
	_active = true
	_fail_closed = false
	_entered_at = int(Time.get_unix_time_from_system())
	return {
		"ok": true,
		"active": true,
		"saved_hot_improvements": _saved_hot_improvements,
		"legacy_hot_improvements": false
	}

func leave() -> Dictionary:
	if not _active:
		return {"ok": true, "active": false, "restored": false}
	if coordinator == null:
		return {"ok": false, "stage": "managed_mode", "error": "AutonomousCoordinator is unavailable"}
	var cycle_running = coordinator.get("_cycle_running")
	if cycle_running != null and bool(cycle_running):
		return {"ok": false, "stage": "managed_mode", "error": "Cannot leave Evolution managed mode while autonomous cycle is running"}
	coordinator.set("autonomous_hot_improvements", _saved_hot_improvements)
	var restored := _saved_hot_improvements
	_active = false
	_fail_closed = false
	_entered_at = 0
	return {"ok": true, "active": false, "restored": true, "restored_hot_improvements": restored}

func fail_closed(reason := "Evolution controller unavailable") -> Dictionary:
	if not _active:
		return {
			"ok": true,
			"active": false,
			"fail_closed": false,
			"changed": false,
			"reason": reason.substr(0, 500)
		}
	if coordinator != null:
		coordinator.set("autonomous_hot_improvements", false)
	_fail_closed = true
	return {
		"ok": true,
		"active": true,
		"fail_closed": true,
		"changed": true,
		"legacy_hot_improvements": false,
		"reason": reason.substr(0, 500)
	}

func permits_evolution() -> bool:
	if not _active or coordinator == null:
		return false
	var hot = coordinator.get("autonomous_hot_improvements")
	return hot != null and not bool(hot)

func status() -> Dictionary:
	var legacy_hot = null
	if coordinator != null:
		legacy_hot = coordinator.get("autonomous_hot_improvements")
	return {
		"active": _active,
		"permits_evolution": permits_evolution(),
		"legacy_hot_improvements": legacy_hot,
		"saved_hot_improvements": _saved_hot_improvements,
		"fail_closed": _fail_closed,
		"entered_at": _entered_at
	}
