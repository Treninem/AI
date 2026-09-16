extends SceneTree

class FakeOfflineCore:
	extends AuroraCoreRuntime
	var local_calls := 0
	var compatibility_calls := 0

	func chat_local_only(messages: Array, temperature := 0.2) -> Dictionary:
		local_calls += 1
		var last_text := ""
		for message in messages:
			if message is Dictionary:
				last_text = str(message.get("content", ""))
		var all_text := JSON.stringify(messages)
		if all_text.contains("модуль планирования AuroraFox"):
			return {
				"ok": true,
				"runtime": "aurora_core_offline_test",
				"content": JSON.stringify({
					"objective": "offline integration",
					"steps": ["use local tool", "verify local result"],
					"risks": [],
					"success_checks": ["local tool returned evidence"],
					"needs_tools": true
				}),
				"temperature": temperature
			}
		if last_text.begins_with("TOOL_RESULT offline_echo:"):
			return {
				"ok": true,
				"runtime": "aurora_core_offline_test",
				"content": "offline-final",
				"temperature": temperature
			}
		return {
			"ok": true,
			"runtime": "aurora_core_offline_test",
			"content": JSON.stringify({
				"tool": "offline_echo",
				"args": {"value": "offline-evidence"}
			}),
			"temperature": temperature
		}

	func chat(messages: Array, temperature := 0.2) -> Dictionary:
		compatibility_calls += 1
		return {
			"ok": false,
			"runtime": "ollama_legacy_test",
			"error": "external compatibility must not be used",
			"messages": messages,
			"temperature": temperature
		}

var _offline_tool_calls := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var client := AIClient.new()
	var fake := FakeOfflineCore.new()
	client.core_runtime = fake
	root.add_child(client)

	var memory := MemoryStore.new()
	root.add_child(memory)
	var tools := ToolRegistry.new()
	root.add_child(tools)
	var agent := AgentCore.new()
	agent.enable_planning = true
	agent.enable_self_check = false
	agent.enable_skill_learning = false
	agent.enable_dream_cycle = false
	agent.enable_specialist_team = false
	root.add_child(agent)
	await process_frame

	tools.register_tool(
		"offline_echo",
		"Deterministic local-only smoke tool",
		{"value": "string"},
		Callable(self, "_offline_echo")
	)
	agent.setup(client, memory, tools)

	# Even with legacy compatibility toggled on, the complete normal agent path
	# must remain on AuroraFox Core. No network/external service is contacted by
	# this test; planning, chat, memory and the tool are all local.
	fake.set_ollama_fallback_enabled(true)
	memory.set_legacy_semantic_compat_enabled(true)
	var result := await agent.run_task("offline integration self reliance task")
	if result != "offline-final":
		_fail("offline AgentCore did not complete through the local path: " + result)
		return
	if fake.compatibility_calls != 0:
		_fail("offline AgentCore escaped into external compatibility")
		return
	if fake.local_calls < 3:
		_fail("offline AgentCore did not exercise local planning plus task inference")
		return
	if _offline_tool_calls != 1:
		_fail("offline local tool was not executed exactly once")
		return

	var status := memory.semantic_status()
	if bool(status.get("network_required", true)):
		_fail("memory semantic backend unexpectedly requires network")
		return
	if bool(status.get("external_runtime_required", true)):
		_fail("memory semantic backend unexpectedly requires external runtime")
		return
	if bool(status.get("ollama_required", true)):
		_fail("memory semantic backend unexpectedly requires Ollama")
		return
	if str(status.get("provider", "")) != "aurorafox_local_vector":
		_fail("memory semantic provider is not AuroraFox local vector")
		return

	var remembered_task := false
	var remembered_tool := false
	for item in memory.memory:
		if not item is Dictionary:
			continue
		if str(item.get("kind", "")) == "user_task" and str(item.get("content", "")).contains("offline integration"):
			remembered_task = true
		if str(item.get("kind", "")) == "tool" and str(item.get("content", "")).contains("offline_echo"):
			remembered_tool = true
	if not remembered_task:
		_fail("offline task was not persisted into local memory")
		return
	if not remembered_tool:
		_fail("offline tool evidence was not persisted into local memory")
		return

	print("OFFLINE_AUTONOMY_SMOKE_OK")
	agent.queue_free()
	tools.queue_free()
	memory.queue_free()
	client.queue_free()
	await process_frame
	quit(0)

func _offline_echo(args: Dictionary) -> Dictionary:
	_offline_tool_calls += 1
	return {
		"ok": true,
		"local_only": true,
		"echo": str(args.get("value", ""))
	}

func _fail(message: String) -> void:
	push_error("OFFLINE_AUTONOMY_SMOKE_FAILED: " + message)
	quit(1)
