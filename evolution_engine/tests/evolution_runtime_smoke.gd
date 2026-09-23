extends SceneTree

class FakeTools:
	extends Node
	var tools: Dictionary = {}
	func register_tool(name: String, description: String, schema: Dictionary, callable: Callable) -> void:
		tools[name] = {"description": description, "schema": schema, "callable": callable}
	func call_tool(name: String, args: Dictionary = {}) -> Variant:
		if not tools.has(name):
			return {"ok": false, "error": "unknown tool"}
		return await tools[name].callable.call(args)

class FakeCoordinator:
	extends Node
	var _cycle_running := false
	var autonomous_hot_improvements := true
	func synchronize_all() -> Dictionary:
		return {"ok": true, "compatible": true}

class FakeImprover:
	extends Node
	func propose_improvement(_goal: String, _attempt := 0, _strategy := {}, _signatures := {}) -> Dictionary:
		return {"ok": true}
	func run_mutation_tournament(_goal: String, _count := 5) -> Dictionary:
		return {"ok": false, "error": "not used"}

class FakeExtensions:
	extends Node
	func activate_staged(_path: String, _sha := "") -> Dictionary:
		return {"ok": true}
	func deactivate(_id: String) -> Dictionary:
		return {"ok": true}

class FakeMemory:
	extends Node
	func remember(_kind: String, _content: String, _source := "", _importance := 0.5, _confidence := 0.5) -> void:
		pass
	func retrieve(_query: String, _limit := 8, _include_memory := true, _include_knowledge := true) -> Array:
		return []

class FakeKnowledge:
	extends RefCounted
	func search(_query: String, _limit := 6) -> Array:
		return []

class FakeAI:
	extends Node
	var knowledge := FakeKnowledge.new()

class FakeCorePipeline:
	extends Node
	var _running := false
	func status() -> Dictionary:
		return {"ok": true}

class FakeAutonomySettings:
	extends Node
	func get_settings() -> Dictionary:
		return {"master_enabled": true}

class FakeUpdateGuard:
	extends Node
	func status() -> Dictionary:
		return {"updater_bound": true, "paused_hot_improvements": false, "paused_core_candidates": false}

class FakeSandbox:
	extends Node
	func snapshot(_label := "checkpoint") -> Dictionary:
		return {"ok": true}
	func rollback(_snapshot: String) -> Dictionary:
		return {"ok": true}

class FakeSandboxBridge:
	extends Node
	var manager := FakeSandbox.new()
	func _init() -> void:
		add_child(manager)

class FakeMain:
	extends Node
	var tools := FakeTools.new()
	var ai := FakeAI.new()
	var memory := FakeMemory.new()
	var improver := FakeImprover.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := FakeMain.new()
	main.name = "Main"
	main.add_child(main.tools)
	main.add_child(main.ai)
	main.add_child(main.memory)
	main.add_child(main.improver)
	_add_named(main, FakeCoordinator.new(), "AutonomousCoordinator")
	_add_named(main, FakeExtensions.new(), "RuntimeExtensions")
	_add_named(main, FakeCorePipeline.new(), "CoreImprovementPipeline")
	_add_named(main, FakeAutonomySettings.new(), "AutonomySettings")
	_add_named(main, FakeUpdateGuard.new(), "UpdateAutonomyGuard")
	_add_named(main, FakeSandboxBridge.new(), "SandboxTools")
	var runtime := AuroraEvolutionRuntime.new()
	runtime.name = "EvolutionRuntime"
	main.add_child(runtime)
	root.add_child(main)
	await process_frame

	var binding := runtime.bind_now()
	if not bool(binding.get("ok", false)):
		_fail("runtime foundation binding failed: %s" % str(binding), 1)
		return
	if int(binding.get("session_permission_level", -1)) != AuroraEvolutionPolicy.LEVEL_ANALYSIS:
		_fail("runtime did not start at Level 0", 2)
		return
	if bool(binding.get("user_authorized", true)):
		_fail("runtime started with user authorization", 3)
		return
	if not main.tools.tools.has(AuroraEvolutionRuntime.STATUS_TOOL) or not main.tools.tools.has(AuroraEvolutionRuntime.ANALYZE_TOOL):
		_fail("read-only Evolution tools were not registered", 4)
		return
	for forbidden in ["aurora_evolution_authorize", "aurora_evolution_run", "aurora_evolution_activate", "aurora_evolution_promote"]:
		if main.tools.tools.has(forbidden):
			_fail("unsafe agent tool was registered: %s" % forbidden, 5)
			return

	var denied := runtime.authorize_session_level(AuroraEvolutionPolicy.LEVEL_SANDBOX_EXPERIMENT, false)
	if bool(denied.get("ok", false)) or int(runtime.status().get("session_permission_level", -1)) != AuroraEvolutionPolicy.LEVEL_ANALYSIS:
		_fail("permission changed without explicit user confirmation", 6)
		return
	var managed := runtime.begin_managed_session(AuroraEvolutionPolicy.LEVEL_SANDBOX_EXPERIMENT, true)
	if not bool(managed.get("ok", false)):
		_fail("confirmed managed session did not start", 7)
		return
	var coordinator = main.get_node("AutonomousCoordinator")
	if bool(coordinator.get("autonomous_hot_improvements")):
		_fail("legacy auto-activation stayed enabled in managed mode", 8)
		return
	var ended := runtime.end_managed_session()
	if not bool(ended.get("ok", false)) or int(runtime.status().get("session_permission_level", -1)) != AuroraEvolutionPolicy.LEVEL_ANALYSIS:
		_fail("managed session did not reset permission to Level 0", 9)
		return
	if not bool(coordinator.get("autonomous_hot_improvements")):
		_fail("legacy hot-improvement state was not restored", 10)
		return

	var analysis = await main.tools.call_tool(AuroraEvolutionRuntime.ANALYZE_TOOL, {"goal": "runtime safety audit"})
	if not bool(analysis.get("ok", false)):
		_fail("read-only analysis tool failed", 11)
		return

	print("AURORA_EVOLUTION_RUNTIME_SMOKE_OK bound=true default_level=0 read_only_tools=true confirmation=true managed=true reset=true")
	main.queue_free()
	await process_frame
	quit(0)

func _add_named(parent: Node, child: Node, node_name: String) -> void:
	child.name = node_name
	parent.add_child(child)

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
