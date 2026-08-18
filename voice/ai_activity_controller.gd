class_name AuroraAIActivityController
extends Node

var tools: ToolRegistry
var _return_timer := 0.0

func _ready() -> void:
	await get_tree().process_frame
	tools = _find_tool_registry(get_tree().current_scene)
	if tools != null:
		tools.tool_called.connect(_on_tool_called)
	set_process(true)

func _process(delta: float) -> void:
	if _return_timer <= 0.0: return
	_return_timer -= delta
	if _return_timer <= 0.0 and AuroraVoice.avatar.current_state not in ["AI_SPEAKING", "AI_LISTENING"]:
		AuroraVoice.avatar.set_state("AI_WORKING")

func _on_tool_called(name: String, _args: Dictionary) -> void:
	var state := _state_for_tool(name)
	AuroraVoice.avatar.set_state(state)
	AuroraVoice.emotions.set_emotion("focused", 0.52, 3.5)
	_return_timer = 2.2

func _state_for_tool(name: String) -> String:
	var n := name.to_lower()
	if n in ["http_get", "web_search", "search_web"] or n.contains("search"):
		return "AI_SEARCHING"
	if n in ["read_file", "list_dir", "workspace_read", "workspace_tree", "screen_snapshot"] or n.contains("read"):
		return "AI_READING"
	if n in ["write_file", "workspace_write", "workspace_exec", "workspace_test", "sandbox_exec", "sandbox_write", "git_diff", "git_status"]:
		return "AI_CODING"
	if n in ["computer_goal", "computer_plan"]:
		return "AI_WORKING"
	return "AI_WORKING"

func _find_tool_registry(node: Node) -> ToolRegistry:
	if node == null: return null
	if node is ToolRegistry: return node
	for child in node.get_children():
		var found := _find_tool_registry(child)
		if found != null: return found
	return null
