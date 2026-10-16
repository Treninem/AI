extends SceneTree

func _initialize() -> void:
	var agent := AgentCore.new()
	var store := MemoryStore.new()
	agent.memory = store
	var catalog := [{"name": "benchmark_probe", "description": "Read-only synthetic probe", "parameters": {"value": "string"}}]
	var simple := agent._system_prompt("Use the read-only benchmark_probe tool once with value GREEN-73.", [], {}, [], {}, [], catalog)
	var project := agent._system_prompt("Search the project repository code before editing a file.", [], {}, [], {}, [], catalog)
	if simple.contains("ПРОТОКОЛ РАБОТЫ С БОЛЬШИМ ПРОЕКТОМ:") or not project.contains("ПРОТОКОЛ РАБОТЫ С БОЛЬШИМ ПРОЕКТОМ:"):
		push_error("Project protocol must be included only for project tasks")
		quit(1)
		return
	for prompt in [simple, project]:
		if not prompt.contains("ГРАНИЦА ДОВЕРИЯ:") or not prompt.contains("ПРОТОКОЛ ПЕСОЧНИЦЫ:") or not prompt.contains("Используй ТОЛЬКО инструменты из списка ниже"):
			print("prompt_characters=", prompt.length(), " trust=", prompt.contains("ГРАНИЦА ДОВЕРИЯ:"), " sandbox=", prompt.contains("ПРОТОКОЛ ПЕСОЧНИЦЫ:"), " tools=", prompt.contains("Используй ТОЛЬКО инструменты из списка ниже"))
			push_error("Prompt compaction removed a trust, sandbox or tool boundary")
			quit(1)
			return
	if simple.length() > 1800 or project.length() - simple.length() < 100:
		push_error("Tool prompt is too large or project guidance is missing: simple=%d project=%d" % [simple.length(), project.length()])
		quit(1)
		return
	var registry := ToolRegistry.new()
	registry._ready()
	var full_catalog := registry.describe_tools()
	var full_prompt := agent._system_prompt("Read a project file before editing it.", [], {}, [], {}, [], full_catalog)
	if full_catalog.size() < 15 or full_prompt.length() > 5000:
		push_error("Full tool catalog was lost or prompt still exceeds the bounded fixture")
		quit(1)
		return
	for entry in full_catalog:
		if not full_prompt.contains(str(entry.get("name", ""))):
			push_error("Compact prompt omitted a registered tool")
			quit(1)
			return
	print("AGENT_CORE_TOOL_PROMPT_BUDGET_PASS simple_chars=", simple.length(), " project_chars=", project.length(), " full_catalog_tools=", full_catalog.size(), " full_chars=", full_prompt.length())
	registry.free()
	agent.free()
	store.free()
	quit(0)
