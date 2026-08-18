class_name SelfImprover
extends Node

var tools: ToolRegistry
var ai: AIClient

func setup(tool_registry: ToolRegistry, ai_client: AIClient) -> void:
	tools = tool_registry
	ai = ai_client

func propose_improvement(goal: String) -> Dictionary:
	var prompt := """
Ты анализируешь Godot 4.7.1 проект автономного ИИ.
Предложи одно небольшое безопасное улучшение для цели: %s
Верни JSON:
{"path":"res://generated/<filename>.gd","content":"полный код файла","reason":"зачем"}
Нельзя изменять project.godot, удалять файлы, писать за пределы res://generated/.
""" % goal
	var result := await ai.chat([{"role":"user","content":prompt}], 0.1)
	if not result.get("ok", false):
		return result
	var text := str(result.get("content", "")).replace("```json", "").replace("```", "").strip_edges()
	var proposal = JSON.parse_string(text)
	if not proposal is Dictionary:
		return {"ok": false, "error": "Invalid proposal"}
	var path := str(proposal.get("path", ""))
	if not path.begins_with("res://generated/") or not path.ends_with(".gd"):
		return {"ok": false, "error": "Unsafe proposal path"}
	return {"ok": true, "proposal": proposal}

func apply_generated_module(proposal: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://generated"))
	var write_result = await tools.call_tool("write_file", {
		"path": str(proposal.get("path", "")),
		"content": str(proposal.get("content", ""))
	})
	if not write_result.get("ok", false):
		return write_result
	return {"ok": true, "message": "Generated module written. Review/test before activation."}
