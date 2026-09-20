class_name AuroraEvolutionExperimentRegistry
extends RefCounted

const MAX_RECENT := 64
const MAX_PHASE_HISTORY := 24

var _sequence := 0
var _records: Dictionary = {}
var _recent: Array[String] = []

func begin(kind: String, goal: String, requested_count := 0, metadata: Dictionary = {}) -> Dictionary:
	_sequence += 1
	var now := int(Time.get_unix_time_from_system())
	var experiment_id := "%d-%04d" % [now, _sequence]
	var record := {
		"id": experiment_id,
		"kind": kind.substr(0, 120),
		"goal": goal.substr(0, 2000),
		"requested_count": requested_count,
		"status": "running",
		"phase": "created",
		"created_at": Time.get_datetime_string_from_system(true),
		"created_unix": now,
		"updated_unix": now,
		"metadata": _compact_metadata(metadata),
		"phase_history": [{"phase": "created", "unix": now}]
	}
	_records[experiment_id] = record
	_recent.push_front(experiment_id)
	_trim()
	return record.duplicate(true)

func advance(experiment_id: String, phase: String, details: Dictionary = {}) -> Dictionary:
	if not _records.has(experiment_id):
		return {"ok": false, "error": "unknown experiment", "experiment_id": experiment_id}
	var record: Dictionary = _records[experiment_id]
	var now := int(Time.get_unix_time_from_system())
	record["phase"] = phase.substr(0, 120)
	record["updated_unix"] = now
	var history: Array = record.get("phase_history", [])
	history.append({
		"phase": phase.substr(0, 120),
		"unix": now,
		"details": _compact_metadata(details)
	})
	while history.size() > MAX_PHASE_HISTORY:
		history.pop_front()
	record["phase_history"] = history
	_records[experiment_id] = record
	return record.duplicate(true)

func complete(experiment_id: String, result: Dictionary) -> Dictionary:
	if not _records.has(experiment_id):
		return {"ok": false, "error": "unknown experiment", "experiment_id": experiment_id}
	var record: Dictionary = _records[experiment_id]
	var now := int(Time.get_unix_time_from_system())
	record["status"] = "accepted" if bool(result.get("ok", false)) else "rejected"
	record["phase"] = str(result.get("stage", "completed" if bool(result.get("ok", false)) else "rejected")).substr(0, 120)
	record["updated_unix"] = now
	record["completed_at"] = Time.get_datetime_string_from_system(true)
	record["completed_unix"] = now
	record["result"] = _compact_result(result)
	_records[experiment_id] = record
	return record.duplicate(true)

func fail(experiment_id: String, stage: String, error: String) -> Dictionary:
	return complete(experiment_id, {
		"ok": false,
		"stage": stage,
		"error": error
	})

func get_record(experiment_id: String) -> Dictionary:
	if not _records.has(experiment_id):
		return {}
	return (_records[experiment_id] as Dictionary).duplicate(true)

func recent(limit := 10) -> Array:
	var out: Array = []
	var count := clampi(limit, 1, MAX_RECENT)
	for experiment_id in _recent:
		if out.size() >= count:
			break
		if _records.has(experiment_id):
			out.append((_records[experiment_id] as Dictionary).duplicate(true))
	return out

func _compact_result(result: Dictionary) -> Dictionary:
	return {
		"ok": bool(result.get("ok", false)),
		"stage": str(result.get("stage", "")).substr(0, 120),
		"error": str(result.get("error", "")).substr(0, 1200),
		"population_size": int(result.get("population_size", 0)),
		"verified_count": int(result.get("verified_count", 0)),
		"tournament_id": str(result.get("tournament_id", "")).substr(0, 160),
		"candidate_id": str(result.get("candidate_id", "")).substr(0, 160),
		"sha256": str(result.get("sha256", result.get("candidate_sha256", ""))).substr(0, 64),
		"promotion": str(result.get("promotion", "")).substr(0, 120)
	}

func _compact_metadata(metadata: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var allowed := ["target", "requested", "permission_level", "source", "reason", "mode"]
	for key in allowed:
		if metadata.has(key):
			out[key] = str(metadata.get(key, "")).substr(0, 500) if key != "requested" and key != "permission_level" else int(metadata.get(key, 0))
	return out

func _trim() -> void:
	while _recent.size() > MAX_RECENT:
		var old_id := _recent.pop_back()
		_records.erase(old_id)
