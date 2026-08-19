class_name AuroraAutonomousCoordinator
extends Node

signal synchronization_completed(report: Dictionary)
signal autonomous_cycle_completed(report: Dictionary)
signal autonomous_cycle_failed(report: Dictionary)

const STATE_DIR := "user://agent"
const STATE_PATH := "user://agent/autonomy_state.json"

@export var autonomous_enabled := true
@export var autonomous_hot_improvements := true
@export_range(60.0, 86400.0, 1.0) var cycle_interval_seconds := 900.0
@export_range(300.0, 604800.0, 1.0) var mutation_cooldown_seconds := 21600.0

var component_registry := AuroraComponentRegistry.new()
var goals := AuroraGoals.new()

var tools: ToolRegistry
var ai: AIClient
var memory: MemoryStore
var agent_core: AgentCore
var improver: SelfImprover
var extensions: RuntimeExtensionManager

var _timer: Timer
var _cycle_running := false
var _last_report: Dictionary = {}
var _last_improvement_unix := 0
var _events: Array = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STATE_DIR))
	_load_state()
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	for _i in range(40):
		_bind_existing()
		if tools != null and agent_core != null and improver != null and extensions != null:
			break
		await get_tree().process_frame
	_bind_existing()
	if tools == null:
		_record_event("bootstrap_failed", {"error": "ToolRegistry unavailable"})
		return
	_register_coordination_tools()
	_setup_timer()
	var report := await synchronize_all()
	if autonomous_enabled and bool(report.get("compatible", false)):
		_timer.start()

func _bind_existing() -> void:
	var main := get_parent()
	if main == null:
		return
	var value = main.get("tools")
	if value is ToolRegistry:
		tools = value
	value = main.get("ai")
	if value is AIClient:
		ai = value
	value = main.get("memory")
	if value is MemoryStore:
		memory = value
	value = main.get("agent")
	if value is AgentCore:
		agent_core = value
	value = main.get("improver")
	if value is SelfImprover:
		improver = value
	var extension_node := main.get_node_or_null("RuntimeExtensions")
	if extension_node is RuntimeExtensionManager:
		extensions = extension_node
		if tools != null:
			extensions.bind_registry(tools)
	_connect_existing_signals()

func _connect_existing_signals() -> void:
	if improver != null:
		if not improver.improvement_verified.is_connected(_on_improvement_verified):
			improver.improvement_verified.connect(_on_improvement_verified)
		if not improver.improvement_rejected.is_connected(_on_improvement_rejected):
			improver.improvement_rejected.connect(_on_improvement_rejected)
	if extensions != null:
		if not extensions.extension_activated.is_connected(_on_extension_activated):
			extensions.extension_activated.connect(_on_extension_activated)
		if not extensions.extension_error.is_connected(_on_extension_error):
			extensions.extension_error.connect(_on_extension_error)

func _register_coordination_tools() -> void:
	if tools == null:
		return
	if not tools.tools.has("aurora_sync_status"):
		tools.register_tool(
			"aurora_sync_status",
			"Показать единое состояние совместимости старых и новых подсистем AuroraFox.",
			{},
			Callable(self, "_tool_status")
		)
	if not tools.tools.has("aurora_sync_now"):
		tools.register_tool(
			"aurora_sync_now",
			"Синхронизировать AgentCore, память, File Intelligence, runtime extensions, self-improvement, voice и updater.",
			{},
			Callable(self, "_tool_sync")
		)
	if not tools.tools.has("aurora_autonomous_cycle"):
		tools.register_tool(
			"aurora_autonomous_cycle",
			"Запустить один полный автономный цикл наблюдения, синхронизации и проверенного улучшения AuroraFox.",
			{},
			Callable(self, "_tool_cycle")
		)

func _setup_timer() -> void:
	if _timer != null:
		return
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = cycle_interval_seconds
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)

func synchronize_all() -> Dictionary:
	_bind_existing()
	var observations := await _collect_observations()
	var services := {
		"platform": OS.get_name(),
		"voice": get_node_or_null("/root/AuroraVoice") != null,
		"update": get_node_or_null("/root/AuroraUpdate") != null,
		"file_intelligence": tools != null and tools.tools.has("analyze_file") and tools.tools.has("search_file_cache"),
		"project_index": tools != null and tools.tools.has("project_index_status")
	}
	var report := component_registry.build_report(agent_core, improver, extensions, tools, memory, ai, services)
	report["observations"] = observations
	report["goals"] = goals.snapshot()
	report["autonomous_enabled"] = autonomous_enabled
	report["autonomous_hot_improvements"] = autonomous_hot_improvements
	report["hot_improvement_supported"] = _hot_improvement_supported()
	report["last_improvement_unix"] = _last_improvement_unix
	report["events"] = _events.slice(maxi(0, _events.size() - 20), _events.size())
	_last_report = report.duplicate(true)
	_save_state()
	synchronization_completed.emit(report)
	return report

func _collect_observations() -> Dictionary:
	var result := {
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"platform": OS.get_name(),
		"godot": Engine.get_version_info(),
		"tools_count": tools.tools.size() if tools != null else 0
	}
	if tools == null:
		return result
	if tools.tools.has("git_status"):
		result["git_status"] = await tools.call_tool("git_status", {})
	if tools.tools.has("project_index_status"):
		var index_status = await tools.call_tool("project_index_status", {"path": "res://"})
		result["project_index"] = index_status
		if index_status is Dictionary and index_status.get("ok", false) and int(index_status.get("files", 0)) == 0 and tools.tools.has("index_project"):
			result["project_index_refresh"] = await tools.call_tool("index_project", {"path": "res://", "max_files": 30000, "force": false})
	if extensions != null:
		result["runtime_extensions"] = extensions.list_extensions()
	if agent_core != null:
		result["recent_failures"] = agent_core.experience.recent_failures(5)
	return result

func run_autonomous_cycle() -> Dictionary:
	if _cycle_running:
		return {"ok": false, "error": "Autonomous cycle is already running"}
	_cycle_running = true
	var sync_report := await synchronize_all()
	if not bool(sync_report.get("compatible", false)):
		var incompatible := {"ok": false, "stage": "compatibility", "sync": sync_report}
		_record_event("cycle_blocked", incompatible)
		_cycle_running = false
		autonomous_cycle_failed.emit(incompatible)
		return incompatible

	var observations: Dictionary = sync_report.get("observations", {})
	var failures: Array = observations.get("recent_failures", [])
	var selected_goal := goals.choose_goal(sync_report, failures, observations)
	var report := {
		"ok": true,
		"goal": selected_goal,
		"sync": sync_report,
		"mutation_attempted": false,
		"mutation_applied": false,
		"hot_improvement_supported": _hot_improvement_supported()
	}

	var now := int(Time.get_unix_time_from_system())
	var cooldown_ready := now - _last_improvement_unix >= int(mutation_cooldown_seconds)
	if autonomous_hot_improvements and _hot_improvement_supported() and cooldown_ready and improver != null and extensions != null and ai != null:
		report["mutation_attempted"] = true
		var proposal_result := await improver.propose_improvement(selected_goal)
		report["proposal"] = _compact(proposal_result)
		if proposal_result.get("ok", false):
			var proposal: Dictionary = proposal_result.get("proposal", {})
			var staged := await improver.apply_generated_module(proposal)
			report["verification"] = _compact(staged)
			if staged.get("ok", false):
				var activated := extensions.activate_staged(str(staged.get("stage_path", "")), str(staged.get("sha256", "")))
				report["activation"] = _compact(activated)
				if activated.get("ok", false):
					report["mutation_applied"] = true
					_last_improvement_unix = now
					_record_event("mutation_activated", {"goal": selected_goal, "id": activated.get("id", ""), "tools": activated.get("tools", [])})

	_record_event("cycle_completed", {"goal": selected_goal, "mutation_applied": report.get("mutation_applied", false)})
	_cycle_running = false
	_save_state()
	autonomous_cycle_completed.emit(report)
	return report

func _hot_improvement_supported() -> bool:
	return OS.get_name() == "Windows"

func _tool_status(_args: Dictionary) -> Dictionary:
	return await synchronize_all()

func _tool_sync(_args: Dictionary) -> Dictionary:
	return await synchronize_all()

func _tool_cycle(_args: Dictionary) -> Dictionary:
	return await run_autonomous_cycle()

func _on_timer_timeout() -> void:
	if autonomous_enabled and not _cycle_running:
		await run_autonomous_cycle()

func _on_improvement_verified(result: Dictionary) -> void:
	_record_event("improvement_verified", result)

func _on_improvement_rejected(result: Dictionary) -> void:
	_record_event("improvement_rejected", result)

func _on_extension_activated(id: String, tool_names: Array) -> void:
	_record_event("extension_activated", {"id": id, "tools": tool_names})

func _on_extension_error(message: String, details: Dictionary) -> void:
	_record_event("extension_error", {"message": message, "details": _compact(details)})

func _record_event(kind: String, details: Dictionary) -> void:
	_events.append({
		"time": int(Time.get_unix_time_from_system()),
		"kind": kind,
		"details": _compact(details)
	})
	if _events.size() > 200:
		_events = _events.slice(_events.size() - 200, _events.size())

func _save_state() -> void:
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"last_improvement_unix": _last_improvement_unix,
		"events": _events,
		"last_report": _last_report
	}))
	file.close()

func _load_state() -> void:
	if not FileAccess.file_exists(STATE_PATH):
		return
	var file := FileAccess.open(STATE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	_last_improvement_unix = int(parsed.get("last_improvement_unix", 0))
	var saved_events = parsed.get("events", [])
	if saved_events is Array:
		_events = saved_events
	var saved_report = parsed.get("last_report", {})
	if saved_report is Dictionary:
		_last_report = saved_report

func _compact(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = value.duplicate(true)
		for key in out.keys():
			var text := str(out[key])
			if text.length() > 5000:
				out[key] = text.substr(0, 5000) + "…"
		return out
	if value is Array:
		var arr: Array = value
		return arr.slice(0, mini(arr.size(), 50))
	return value
