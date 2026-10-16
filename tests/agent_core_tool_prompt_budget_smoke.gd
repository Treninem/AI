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
	if project.length() - simple.length() < 700:
		push_error("Simple tool prompt did not save enough context")
		quit(1)
		return
	print("AGENT_CORE_TOOL_PROMPT_BUDGET_PASS simple_chars=", simple.length(), " project_chars=", project.length())
	agent.free()
	store.free()
	quit(0)
