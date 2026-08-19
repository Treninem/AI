class_name DeveloperRuntimeToolBridge
extends Node

var runtime := DeveloperRuntimeManager.new()
var _registered := false

func _ready() -> void:
	if OS.get_name() != "Windows": return
	add_child(runtime)
	call_deferred("_register_tools")

func _register_tools() -> void:
	if _registered: return
	var main := get_parent()
	if main == null: return
	var registry = main.get("tools")
	if not registry is ToolRegistry: return
	registry.register_tool(
		"workspace_test",
		"Проверить код активной песочницы подходящим тестом/компилятором. Для GDScript AuroraFox автоматически готовит и использует ровно Godot 4.7.1.",
		{"language":"string","cwd":"string"},
		Callable(self, "_workspace_test")
	)
	registry.register_tool(
		"developer_runtime_status",
		"Проверить наличие локального Godot 4.7.1, используемого для headless тестов и контролируемого самоулучшения.",
		{},
		Callable(self, "_runtime_status")
	)
	registry.register_tool(
		"developer_runtime_prepare",
		"Подготовить локальный Godot 4.7.1 developer runtime. Загружается один раз, затем работает офлайн.",
		{},
		Callable(self, "_prepare_runtime")
	)
	_registered = true

func _sandbox_bridge() -> SandboxToolBridge:
	var main := get_parent()
	if main == null: return null
	return main.get_node_or_null("SandboxTools") as SandboxToolBridge

func _workspace_test(args: Dictionary) -> Dictionary:
	var language := str(args.get("language", "")).to_lower()
	var cwd := str(args.get("cwd", "."))
	var bridge := _sandbox_bridge()
	if bridge == null: return {"ok": false, "error": "SandboxTools node is unavailable"}

	if language in ["gdscript", "godot", "gd"]:
		var prepared := await runtime.ensure_ready()
		if not prepared.get("ok", false):
			return {"ok": false, "stage": "developer_runtime", "error": prepared.get("error", "Godot developer runtime unavailable"), "runtime": prepared}
		var godot_path := runtime.path()
		if godot_path.is_empty(): return {"ok": false, "error": "Pinned Godot runtime path is empty"}
		# Use an absolute executable path and local mode. The computer service may
		# have started before PATH was updated, and Docker intentionally has no
		# Godot profile. Path(command[0]).name is still godot.exe and remains on
		# the computer-service executable allowlist.
		var result := await bridge.manager.execute(
			[godot_path, "--headless", "--path", ".", "--quit"],
			cwd,
			180,
			"local"
		)
		result["runtime"] = godot_path
		result["expected_version"] = DeveloperRuntimeManager.GODOT_VERSION
		return result

	return await bridge.manager.test(language, cwd)

func _runtime_status(_args: Dictionary) -> Dictionary:
	return {"ok": true, "available": runtime.has_runtime(), "path": runtime.path(), "version": DeveloperRuntimeManager.GODOT_VERSION}

func _prepare_runtime(_args: Dictionary) -> Dictionary:
	return await runtime.ensure_ready()
