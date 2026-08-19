extends SceneTree

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
	coordinator.free()

	var main_scene_text := FileAccess.get_file_as_string("res://main.tscn")
	if not main_scene_text.contains("AutonomousCoordinator"):
		push_error("Main scene does not contain AutonomousCoordinator")
		_cleanup([tools, agent_core, improver, extensions, memory, ai])
		quit(8)
		return

	_cleanup([tools, agent_core, improver, extensions, memory, ai])
	print("AURORA_AUTONOMOUS_COORDINATOR_SMOKE_OK")
	quit(0)

func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			node.free()
