extends SceneTree

const STATE_PATH := "user://agent/autonomy_state.json"
const STATE_TEMP_PATH := STATE_PATH + ".tmp"
const STATE_BACKUP_PATH := STATE_PATH + ".bak"

func _dummy(_args: Dictionary) -> Dictionary:
	return {"ok": true}

func _init() -> void:
	var tools := ToolRegistry.new()
	tools._ready()
	tools.register_tool("workspace_create", "test", {}, Callable(self, "_dummy"))
	tools.register_tool("workspace_test", "test", {}, Callable(self, "_dummy"))

	var agent_core := AgentCore.new()
	var improver := SelfImprover.new()
	var extensions := RuntimeExtensionManager.new()
	var memory := MemoryStore.new()
	var ai := AIClient.new()
	var registry := AuroraComponentRegistry.new()

	var report := registry.build_report(agent_core, improver, extensions, tools, memory, ai, {
		"platform": "Linux",
		"voice": true,
		"update": true,
		"file_intelligence": true,
		"project_index": true
	})
	if not report.get("compatible", false):
		push_error("Old/new AuroraFox compatibility report failed: " + JSON.stringify(report))
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(2)
		return

	if int(report.get("schema_version", 0)) != 1:
		push_error("Compatibility report schema changed unexpectedly")
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(3)
		return

	if str(report.get("hot_extension_contract", "")) != "RefCounted/aurora_ext_*":
		push_error("Hot extension compatibility contract changed unexpectedly")
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(4)
		return

	var goals := AuroraGoals.new()
	var selected := goals.choose_goal(report, [], {})
	if selected.strip_edges().is_empty():
		push_error("Autonomous goal selection returned an empty goal")
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(5)
		return

	var coordinator_script = load("res://agent/autonomous_coordinator.gd")
	if coordinator_script == null or not coordinator_script.can_instantiate():
		push_error("Autonomous coordinator cannot be instantiated")
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(6)
		return

	var coordinator = coordinator_script.new()
	if coordinator == null or not coordinator.has_method("synchronize_all") or not coordinator.has_method("run_autonomous_cycle"):
		push_error("Autonomous coordinator public integration API is incomplete")
		if coordinator != null:
			coordinator.free()
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(7)
		return
	if int(coordinator.mutation_population_size) < 3 or int(coordinator.mutation_population_size) > 10:
		push_error("Default mutation population escaped 3..10")
		coordinator.free()
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(8)
		return
	if not is_equal_approx(float(coordinator.cycle_interval_seconds), 300.0):
		push_error("Autonomous cycle should run every 5 minutes by default")
		coordinator.free()
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(9)
		return
	if not is_equal_approx(float(coordinator.mutation_cooldown_seconds), 900.0):
		push_error("Mutation cooldown should be 15 minutes by default")
		coordinator.free()
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(10)
		return
	if not coordinator.has_method("_run_initial_cycle") or not coordinator.has_method("_population_size_for_cycle"):
		push_error("Automatic initial cycle / adaptive population API is missing")
		coordinator.free()
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(11)
		return

	var durability_error := _test_state_durability(coordinator)
	if not durability_error.is_empty():
		push_error(durability_error)
		coordinator.free()
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(15)
		return
	coordinator.free()

	var source := FileAccess.get_file_as_string("res://agent/autonomous_coordinator.gd")
	if not source.contains("run_mutation_tournament") or not source.contains("extensions.activate_staged"):
		push_error("Coordinator does not run tournament and auto-activate winner")
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(12)
		return
	if not source.contains('call_deferred("_run_initial_cycle")'):
		push_error("Coordinator does not start autonomous evolution after bootstrap")
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(13)
		return
	if not source.contains("STATE_TEMP_PATH") or not source.contains("STATE_BACKUP_PATH") or not source.contains("_repair_interrupted_state_save"):
		push_error("Coordinator durable state replacement/recovery contract is missing")
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(16)
		return

	var main_scene_text := FileAccess.get_file_as_string("res://main.tscn")
	if not main_scene_text.contains("AutonomousCoordinator"):
		push_error("Main scene does not contain AutonomousCoordinator")
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(14)
		return

	_cleanup([tools, agent_core, improver, extensions, memory, ai])
	print("AURORA_AUTONOMOUS_COORDINATOR_SMOKE_OK tournament=3..10 startup=automatic state_recovery=atomic")
	quit(0)

func _test_state_durability(coordinator: Node) -> String:
	_cleanup_state_files()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STATE_PATH.get_base_dir()))

	coordinator._last_improvement_unix = 111
	coordinator._last_research_unix = 112
	coordinator.mutation_population_size = 7
	coordinator._events = [{"time": 1, "kind": "committed", "details": {}}]
	coordinator._last_report = {"marker": "committed"}
	coordinator._save_state()
	if not FileAccess.file_exists(STATE_PATH):
		return "Autonomous state save did not create the canonical file"
	if FileAccess.file_exists(STATE_TEMP_PATH) or FileAccess.file_exists(STATE_BACKUP_PATH):
		return "Autonomous state save left temp/backup files after commit"
	var committed := _read_json_state(STATE_PATH)
	if int(committed.get("schema_version", 0)) != 1 or int(committed.get("last_improvement_unix", 0)) != 111:
		return "Autonomous state save produced an invalid schema/payload"

	# Simulate a crash after the previous committed target was moved to backup but
	# before the new temp became the target. Recovery must prefer the last committed backup.
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(STATE_PATH), ProjectSettings.globalize_path(STATE_BACKUP_PATH)) != OK:
		return "Failed to prepare interrupted-state backup scenario"
	if not _write_json_state(STATE_TEMP_PATH, {
		"schema_version": 1,
		"last_improvement_unix": 222,
		"last_research_unix": 223,
		"mutation_population_size": 8,
		"events": [{"time": 2, "kind": "uncommitted", "details": {}}],
		"last_report": {"marker": "uncommitted"}
	}):
		return "Failed to prepare interrupted-state temp scenario"
	coordinator._last_improvement_unix = 0
	coordinator._last_research_unix = 0
	coordinator._events = []
	coordinator._last_report = {}
	coordinator._load_state()
	if int(coordinator._last_improvement_unix) != 111 or str(coordinator._last_report.get("marker", "")) != "committed":
		return "Interrupted state recovery promoted uncommitted temp over committed backup"
	if FileAccess.file_exists(STATE_TEMP_PATH) or FileAccess.file_exists(STATE_BACKUP_PATH):
		return "Interrupted state recovery left stale temp/backup files"

	# A valid canonical target plus stale backup means the replacement committed;
	# loader must keep canonical and clean the stale backup.
	if not _write_json_state(STATE_PATH, {
		"schema_version": 1,
		"last_improvement_unix": 333,
		"last_research_unix": 334,
		"mutation_population_size": 6,
		"events": [],
		"last_report": {"marker": "new-target"}
	}):
		return "Failed to prepare committed-target scenario"
	if not _write_json_state(STATE_BACKUP_PATH, {
		"schema_version": 1,
		"last_improvement_unix": 111,
		"last_research_unix": 112,
		"mutation_population_size": 7,
		"events": [],
		"last_report": {"marker": "old-backup"}
	}):
		return "Failed to prepare stale-backup scenario"
	coordinator._load_state()
	if int(coordinator._last_improvement_unix) != 333 or str(coordinator._last_report.get("marker", "")) != "new-target":
		return "State recovery replaced a committed target with stale backup"
	if FileAccess.file_exists(STATE_BACKUP_PATH):
		return "State recovery did not clean stale backup after committed replacement"

	# Corrupt canonical with a valid backup: recover the backup rather than silently
	# resetting cooldown/events or accepting malformed JSON.
	var corrupt := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if corrupt == null:
		return "Failed to prepare corrupt canonical state"
	corrupt.store_string("{broken-json")
	corrupt.flush()
	corrupt.close()
	if not _write_json_state(STATE_BACKUP_PATH, {
		"schema_version": 1,
		"last_improvement_unix": 444,
		"last_research_unix": 445,
		"mutation_population_size": 5,
		"events": [{"time": 4, "kind": "backup", "details": {}}],
		"last_report": {"marker": "backup-recovery"}
	}):
		return "Failed to prepare valid backup for corrupt-target recovery"
	coordinator._load_state()
	if int(coordinator._last_improvement_unix) != 444 or str(coordinator._last_report.get("marker", "")) != "backup-recovery":
		return "Corrupt canonical state did not recover from valid backup"

	# Legacy state did not contain schema_version. It must remain loadable.
	_cleanup_state_files()
	if not _write_json_state(STATE_PATH, {
		"last_improvement_unix": 555,
		"last_research_unix": 556,
		"mutation_population_size": 4,
		"events": [],
		"last_report": {"marker": "legacy"}
	}):
		return "Failed to prepare legacy state compatibility scenario"
	coordinator._load_state()
	if int(coordinator._last_improvement_unix) != 555 or str(coordinator._last_report.get("marker", "")) != "legacy":
		return "Legacy autonomy state compatibility regressed"

	_cleanup_state_files()
	return ""

func _write_json_state(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok

func _read_json_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _cleanup_state_files() -> void:
	for path in [STATE_TEMP_PATH, STATE_BACKUP_PATH, STATE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _cleanup(nodes: Array) -> void:
	_cleanup_state_files()
	for node in nodes:
		if node != null and is_instance_valid(node):
			node.free()
