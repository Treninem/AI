class_name AgentCore
extends Node

var ai: AIClient
var memory: MemoryStore
var tools: ToolRegistry
var max_steps := 8

func setup(ai_client: AIClient, memory_store: MemoryStore, tool_registry: ToolRegistry) -> void:
	ai = ai_client
	memory = memory_store
	tools = tool_registry

func run_task(task: String) -> String:
	memory.remember("user_task", task)
	var messages: Array = []
	messages.append({"role":"system", "content": _system_prompt(task)})
	messages.append({"role":"user", "content": task})

	for step in range(max_steps):
		var result := await ai.chat(messages)
		if not result.get("ok", false):
			return "Ошибка модели: " + str(result.get("error", "unknown"))
		var text := str(result.get("content", ""))
		var action := _extract_action(text)
		if action.is_empty():
			memory.remember("assistant_answer", text)
			return text

		var tool_name := str(action.get("tool", ""))
		var args: Dictionary = action.get("args", {})
		var tool_result = await tools.call_tool(tool_name, args)
		messages.append({"role":"assistant", "content": text})
		messages.append({"role":"user", "content": "TOOL_RESULT %s: %s" % [tool_name, JSON.stringify(tool_result)]})
		memory.remember("tool", JSON.stringify({"tool": tool_name, "args": args, "result": tool_result}))

	return "Достигнут лимит автономных шагов."

func _system_prompt(task: String) -> String:
	var recent := memory.recent(8)
	var knowledge := memory.search_knowledge(task, 6)
	return """
Ты автономный программный агент, работающий внутри Godot 4.7.1.
Твоя задача — решать задачи пользователя с помощью рассуждения, памяти и инструментов.
Не выдумывай результаты инструментов. Если нужен инструмент, верни ТОЛЬКО JSON в формате:
{"tool":"tool_name","args":{...}}
Когда инструмент не нужен — дай обычный конечный ответ.
Не удаляй данные, не обходи аутентификацию/CAPTCHA и не выполняй разрушительные действия.
Доступные инструменты:
%s
Недавняя память:
%s
Подходящие знания:
%s
""" % [JSON.stringify(tools.describe_tools()), JSON.stringify(recent), JSON.stringify(knowledge)]

func _extract_action(text: String) -> Dictionary:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("```"):
		cleaned = cleaned.replace("```json", "").replace("```", "").strip_edges()
	if not cleaned.begins_with("{"):
		return {}
	var parsed = JSON.parse_string(cleaned)
	if parsed is Dictionary and parsed.has("tool"):
		return parsed
	return {}
