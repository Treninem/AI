class_name AuroraAutonomousCoordinator
extends Node

signal synchronization_completed(report: Dictionary)
signal autonomous_cycle_completed(report: Dictionary)
signal autonomous_cycle_failed(report: Dictionary)

const STATE_DIR := "user://agent"
const STATE_PATH := "user://agent/autonomy_state.json"

@export var autonomous_enabled := true
@export var autonomous_hot_improvements := true
@export var autonomous_research_enabled := true
@export_range(60.0, 86400.0, 1.0) var cycle_interval_seconds := 300.0
@export_range(60.0, 604800.0, 1.0) var mutation_cooldown_seconds := 900.0
@export_range(60.0, 604800.0, 1.0) var research_cooldown_seconds := 300.0
@export_range(3, 10, 1) var mutation_population_size := 5
@export_range(0.0, 120.0, 1.0) var initial_cycle_delay_seconds := 8.0

var component_registry := AuroraComponentRegistry.new()
var goals := AuroraGoals.new()
var research := AuroraResearchCollector.new()

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
var _last_research_unix := 0
var _events: Array = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STATE_DIR))
	if research.get_parent() == null:
		add_child(research)
	_load_state()
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	for _i in range(60):
		_bind_existing()
		if _minimum_integration_ready():
			break
		await get_tree().process_frame
	_bind_existing()
	if tools == null:
		_record_event("bootstrap_failed", {"error": "ToolRegistry unavailable"})
		return
	_register_coordination_tools()
	_setup_timer()
	var report: Dictionary = await synchronize_all()
	if not bool(report.get("compatible", false)):
		_record_event("initial_sync_pending", {
			"missing_components": report.get("missing_components", []),
			"missing_required_tools": report.get("missing_required_tools", [])
		})
	if autonomous_enabled:
		_timer.start()
		call_deferred("_run_initial_cycle")

func _run_initial_cycle() -> void:
	if initial_cycle_delay_seconds > 0.0:
		await get_tree().create_timer(initial_cycle_delay_seconds).timeout
	if autonomous_enabled and not _cycle_running:
		_record_event("initial_autonomous_cycle_started", {"population": mutation_population_size})
		await run_autonomous_cycle()

func _minimum_integration_ready() -> bool:
	if tools == null or ai == null or memory == null or agent_core == null or improver == null or extensions == null:
		return false
	for name in ["workspace_create", "workspace_test"]:
		if not tools.tools.has(name):
			return false
	if OS.get_name() == "Windows":
		for name in ["project_index_status", "index_project", "search_project", "search_symbols", "workspace_import_project", "project_compare_file", "project_apply_file"]:
			if not tools.tools.has(name):
				return false
	return true

func _bind_existing() -> void:
	var main := get_parent()
	if main == null:
		return
	var value: Variant = main.get("tools")
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
	if memory != null and tools != null:
		research.setup(memory, tools)
	_connect_existing_signals()

func _connect_existing_signals() -> void:
	if improver != null:
		if not improver.improvement_verified.is_connected(_on_improvement_verified):
			improver.improvement_verified.connect(_on_improvement_verified)
		if not improver.improvement_rejected.is_connected(_on_improvement_rejected):
			improver.improvement_rejected.connect(_on_improvement_rejected)
		if not improver.mutation_population_started.is_connected(_on_mutation_population_started):
			improver.mutation_population_started.connect(_on_mutation_population_started)
		if not improver.mutation_candidate_completed.is_connected(_on_mutation_candidate_completed):
			improver.mutation_candidate_completed.connect(_on_mutation_candidate_completed)
		if not improver.mutation_tournament_completed.is_connected(_on_mutation_tournament_completed):
			improver.mutation_tournament_completed.connect(_on_mutation_tournament_completed)
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
			"Запустить полный автономный цикл: обучение, 3-10 независимых мутаций, отдельные тесты, соревнование и автоматическую активацию победителя.",
			{},
			Callable(self, "_tool_cycle")
		)
	if not tools.tools.has("aurora_research_now"):
		tools.register_tool(
			"aurora_research_now",
			"Собрать свежие локальные и интернет-наблюдения для текущей цели AuroraFox.",
			{"query": "string"},
			Callable(self, "_tool_research")
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
	var observations: Dictionary = await _collect_observations()
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
	report["autonomous_research_enabled"] = autonomous_research_enabled
	report["hot_improvement_supported"] = _hot_improvement_supported()
	report["mutation_population_size"] = clampi(mutation_population_size, SelfImprover.MIN_MUTATIONS, SelfImprover.MAX_MUTATIONS)
	report["cycle_interval_seconds"] = cycle_interval_seconds
	report["mutation_cooldown_seconds"] = mutation_cooldown_seconds
	report["research_cooldown_seconds"] = research_cooldown_seconds
	report["last_improvement_unix"] = _last_improvement_unix
	report["last_research_unix"] = _last_research_unix
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

	if ai != null:
		result["ai"] = ai.runtime_info()

	var voice_node := get_node_or_null("/root/AuroraVoice")
	if voice_node != null:
		var voice_settings: Variant = voice_node.get("settings")
		result["voice"] = {
			"backend_ready": bool(voice_node.get("backend_is_ready")),
			"enabled": bool(voice_settings.get("enabled", true)) if voice_settings is Dictionary else true,
			"mic_mode": str(voice_settings.get("mic_mode", "unknown")) if voice_settings is Dictionary else "unknown"
		}

	var update_node := get_node_or_null("/root/AuroraUpdate")
	if update_node != null:
		result["update"] = {
			"current_version": str(update_node.get("current_version")),
			"checking": bool(update_node.get("checking")),
			"downloading": bool(update_node.get("downloading")),
			"download_ready": not str(update_node.get("downloaded_path")).is_empty(),
			"settings": update_node.call("get_settings") if update_node.has_method("get_settings") else {}
		}

	if tools == null:
		return result
	if tools.tools.has("git_status"):
		result["git_status"] = await tools.call_tool("git_status", {})
	if tools.tools.has("project_index_status"):
		var index_status: Variant = await tools.call_tool("project_index_status", {"path": "res://"})
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
	var sync_report: Dictionary = await synchronize_all()
	if not bool(sync_report.get("compatible", false)):
		var incompatible := {"ok": false, "stage": "compatibility", "sync": sync_report}
		_record_event("cycle_blocked", incompatible)
		_cycle_running = false
		autonomous_cycle_failed.emit(incompatible)
		return incompatible

	var observations: Dictionary = sync_report.get("observations", {})
	var failures: Array = observations.get("recent_failures", [])
	var selected_goal := goals.choose_goal(sync_report, failures, observations)
	var population_size := _population_size_for_cycle(failures)
	var report := {
		"ok": true,
		"goal": selected_goal,
		"sync": sync_report,
		"research_attempted": false,
		"mutation_attempted": false,
		"mutation_applied": false,
		"mutation_population_size": population_size,
		"hot_improvement_supported": _hot_improvement_supported()
	}

	var now := int(Time.get_unix_time_from_system())
	var research_ready := now - _last_research_unix >= int(research_cooldown_seconds)
	if autonomous_research_enabled and research_ready:
		report["research_attempted"] = true
		var research_result: Dictionary = await research.collect(selected_goal)
		report["research"] = _compact(research_result)
		if research_result.get("ok", false):
			_last_research_unix = now
			_record_event("research_completed", {"goal": selected_goal, "count": int(research_result.get("count", 0)), "sources": research_result.get("sources", {})})

	var cooldown_ready := now - _last_improvement_unix >= int(mutation_cooldown_seconds)
	if autonomous_hot_improvements and _hot_improvement_supported() and cooldown_ready and improver != null and extensions != null and ai != null:
		report["mutation_attempted"] = true
		_record_event("mutation_tournament_started", {"goal": selected_goal, "requested": population_size})
		var tournament: Dictionary = await improver.run_mutation_tournament(selected_goal, population_size)
		report["tournament"] = _compact(tournament)
		if tournament.get("ok", false):
			var activated := extensions.activate_staged(str(tournament.get("stage_path", "")), str(tournament.get("sha256", "")))
			report["activation"] = _compact(activated)
			if activated.get("ok", false):
				report["mutation_applied"] = true
				_last_improvement_unix = int(Time.get_unix_time_from_system())
				_record_event("mutation_winner_activated", {
					"goal": selected_goal,
					"id": activated.get("id", ""),
					"tools": activated.get("tools", []),
					"population_size": tournament.get("population_size", 0),
					"verified_count": tournament.get("verified_count", 0),
					"winner": tournament.get("winner", {})
				})
		else:
			_record_event("mutation_tournament_rejected", {
				"goal": selected_goal,
				"stage": tournament.get("stage", ""),
				"error": tournament.get("error", ""),
				"population_size": tournament.get("population_size", 0),
				"verified_count": tournament.get("verified_count", 0)
			})

	_record_event("cycle_completed", {
		"goal": selected_goal,
		"mutation_applied": report.get("mutation_applied", false),
		"mutation_attempted": report.get("mutation_attempted", false),
		"research_attempted": report.get("research_attempted", false),
		"population_size": population_size
	})
	_cycle_running = false
	_save_state()
	autonomous_cycle_completed.emit(report)
	return report

func _population_size_for_cycle(failures: Array) -> int:
	var size := clampi(mutation_population_size, SelfImprover.MIN_MUTATIONS, SelfImprover.MAX_MUTATIONS)
	# More recent failures create more competing variants, but never more than 10.
	if failures.size() >= 2: size += 1
	if failures.size() >= 4: size += 1
	return clampi(size, SelfImprover.MIN_MUTATIONS, SelfImprover.MAX_MUTATIONS)

func _hot_improvement_supported() -> bool:
	return OS.get_name() == "Windows"

func _tool_status(_args: Dictionary) -> Dictionary:
	return await synchronize_all()

func _tool_sync(_args: Dictionary) -> Dictionary:
	return await synchronize_all()

func _tool_cycle(_args: Dictionary) -> Dictionary:
	return await run_autonomous_cycle()

func _tool_research(args: Dictionary) -> Dictionary:
	var query := str(args.get("query", "")).strip_edges()
	if query.is_empty():
		query = "local AI Godot LLM context optimization"
	var result: Dictionary = await research.collect(query)
	if result.get("ok", false):
		_last_research_unix = int(Time.get_unix_time_from_system())
		_record_event("research_manual", {"query": query, "count": int(result.get("count", 0))})
		_save_state()
	return result

func _on_timer_timeout() -> void:
	if autonomous_enabled and not _cycle_running:
		await run_autonomous_cycle()

func _on_improvement_verified(result: Dictionary) -> void:
	_record_event("improvement_verified", result)

func _on_improvement_rejected(result: Dictionary) -> void:
	_record_event("improvement_rejected", result)

func _on_mutation_population_started(goal: String, requested: int) -> void:
	_record_event("mutation_population_started", {"goal": goal, "requested": requested})

func _on_mutation_candidate_completed(candidate: Dictionary) -> void:
	_record_event("mutation_candidate_completed", {
		"mutation_tag": candidate.get("mutation_tag", ""),
		"strategy": candidate.get("strategy", ""),
		"path": candidate.get("path", ""),
		"verified": candidate.get("verified", false),
		"score": candidate.get("score", 0.0),
		"sha256": candidate.get("sha256", "")
	})

func _on_mutation_tournament_completed(result: Dictionary) -> void:
	_record_event("mutation_tournament_completed", {
		"ok": result.get("ok", false),
		"goal": result.get("goal", ""),
		"population_size": result.get("population_size", 0),
		"verified_count": result.get("verified_count", 0),
		"winner": result.get("winner", {}),
		"error": result.get("error", "")
	})

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
	if _events.size() > 500:
		_events = _events.slice(_events.size() - 500, _events.size())
	_save_state()

func _save_state() -> void:
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"last_improvement_unix": _last_improvement_unix,
		"last_research_unix": _last_research_unix,
		"mutation_population_size": mutation_population_size,
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
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	_last_improvement_unix = int(parsed.get("last_improvement_unix", 0))
	_last_research_unix = int(parsed.get("last_research_unix", 0))
	mutation_population_size = clampi(int(parsed.get("mutation_population_size", mutation_population_size)), SelfImprover.MIN_MUTATIONS, SelfImprover.MAX_MUTATIONS)
	var saved_events: Variant = parsed.get("events", [])
	if saved_events is Array:
		_events = saved_events
	var saved_report: Variant = parsed.get("last_report", {})
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
