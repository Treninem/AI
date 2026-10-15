extends SceneTree

class RecordingAI extends AIClient:
	var captured_messages: Array = []
	var captured_temperature := -1.0
	func chat(messages: Array, temperature: float = 0.2) -> Dictionary:
		captured_messages = messages.duplicate(true)
		captured_temperature = temperature
		return {"ok": true, "content": "Synthetic answer."}

class SyntheticMemory extends MemoryStore:
	func retrieve(_query: String, _limit: int = -1, _include_memory: bool = true, _include_knowledge: bool = true) -> Array:
		return []
	func remember(_kind: String, _content: String, _source: String = "", _importance: float = 0.65, _confidence: float = 0.8) -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var client := RecordingAI.new()
	var memory := SyntheticMemory.new()
	var tools := ToolRegistry.new()
	var agent := AgentCore.new()
	root.add_child(client)
	root.add_child(memory)
	root.add_child(tools)
	root.add_child(agent)
	await process_frame
	agent.setup(client, memory, tools)
	var reply := await agent._run_direct_conversation("Why does a metal boat float? Answer briefly.", [], Callable())
	var system_text := str(client.captured_messages[0].get("content", "")) if not client.captured_messages.is_empty() else ""
	var passed := reply == "Synthetic answer." and client.captured_temperature == 0.0 and system_text.contains("направление сравнений") and client.captured_messages.size() == 2
	if passed:
		print("DIRECT_CHAT_PRECISION_PAYLOAD_OK")
	else:
		push_error("Direct factual chat lost zero-temperature causal check or changed message routing")
	quit(0 if passed else 1)
