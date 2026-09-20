class_name AuroraEvolutionExecutionGuard
extends RefCounted

var coordinator
var _held := false
var _saved_hot_improvements := false

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
	return {"ok": true, "held": true, "saved_hot_improvements": _saved_hot_improvements}

func release() -> Dictionary:
	if not _held:
		return {"ok": true, "released": false}
	if coordinator != null:
		coordinator.set("autonomous_hot_improvements", _saved_hot_improvements)
	_held = false
	return {"ok": true, "released": true, "restored_hot_improvements": _saved_hot_improvements}

func status() -> Dictionary:
	return {
		"held": _held,
		"saved_hot_improvements": _saved_hot_improvements
	}
