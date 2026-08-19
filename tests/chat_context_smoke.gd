extends SceneTree

func _init() -> void:
	var agent := AgentCore.new()
	var messages: Array = []
	var context: Array = [
		{
			"role": "user",
			"content": "Посмотри этот документ",
			"attachments": [
				{
					"name": "manual.pdf",
					"kind": "pdf",
					"metadata": {"pages": 12},
					"excerpt": "На второй странице описана настройка давления 0.35 бар."
				}
			]
		},
		{"role": "assistant", "content": "Документ разобран."}
	]
	agent._append_conversation_context(messages, context)
	if messages.size() != 2:
		push_error("Expected two historical chat messages")
		agent.free()
		quit(2)
		return
	var first := str(messages[0].get("content", ""))
	if not first.contains("Посмотри этот документ"):
		push_error("Historical user message was lost")
		agent.free()
		quit(3)
		return
	if not first.contains("manual.pdf") or not first.contains("0.35 бар"):
		push_error("Historical attachment excerpt was not added to model context")
		agent.free()
		quit(4)
		return
	if str(messages[1].get("role", "")) != "assistant":
		push_error("Assistant history role was lost")
		agent.free()
		quit(5)
		return
	agent.free()
	print("AURORA_CHAT_CONTEXT_SMOKE_OK")
	quit(0)
