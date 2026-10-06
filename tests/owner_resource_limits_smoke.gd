extends SceneTree

# Keep genuine production memory algorithms; isolate filesystem/deferred IO only.
class IsolatedMemory extends MemoryStore:
	func _schedule_persistence(_memory_changed: bool, _knowledge_changed: bool) -> void:
		pass
	func _queue_item_vector(item: Dictionary, collection: String) -> void:
		_index_queue.append({"id": item.id, "collection": collection, "content": OwnerResourcePolicy.clip(str(item.content), "index_text_chars")})
	func _save_vector_index() -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := "user://owner_resource_fixture.cfg"
	var original := OwnerResourcePolicy._cached.duplicate()
	OwnerResourcePolicy._cached = OwnerResourcePolicy.DEFAULTS.duplicate()
	assert(OwnerResourcePolicy.save({"task_trace_chars": 50000, "index_batch": 129}, path) == OK)
	assert(OwnerResourcePolicy.limits(path).task_trace_chars == 50000)
	assert(OwnerResourcePolicy.save({"memory_max_items": 0}, path) == OK)
	assert(OwnerResourcePolicy.limits(path).task_trace_chars == 50000) # Partial save preserves fields.
	assert(OwnerResourcePolicy.save({"index_batch": 0}, path) == ERR_INVALID_PARAMETER)
	assert(OwnerResourcePolicy.save({"task_trace_chars": -1}, path) == ERR_INVALID_PARAMETER)
	assert(OwnerResourcePolicy.save({"task_trace_chars": 1.5}, path) == ERR_INVALID_PARAMETER)
	assert(OwnerResourcePolicy.save({"task_trace_chars": NAN}, path) == ERR_INVALID_PARAMETER)
	assert(OwnerResourcePolicy.save({"unknown": 1}, path) == ERR_INVALID_PARAMETER)
	assert(OwnerResourcePolicy.save({"chat_max_tokens": 2147483648}, path) == ERR_INVALID_PARAMETER)
	assert(OwnerResourcePolicy.save({"task_trace_chars": 10}, "user://missing_resource_fixture_dir/value.cfg") != OK)
	var long_text := "Привет 🌍".repeat(3000)
	assert(OwnerResourcePolicy.clip(long_text, "task_trace_chars").length() == 12000)
	OwnerResourcePolicy._cached.task_trace_chars = 0
	assert(OwnerResourcePolicy.clip(long_text, "task_trace_chars") == long_text)
	OwnerResourcePolicy._cached.task_trace_chars = 2
	assert(OwnerResourcePolicy.clip("АБВ", "task_trace_chars") == "АБ")
	OwnerResourcePolicy._cached.direct_history_items = 0
	assert(OwnerResourcePolicy.count(30, "direct_history_items") == 30)
	var vectorizer := AuroraLocalSemanticVectorizer.new()
	OwnerResourcePolicy._cached.vector_features = 1
	assert(vectorizer.embed("alpha") == vectorizer.embed("alpha beta gamma"))
	OwnerResourcePolicy._cached.vector_features = 0
	OwnerResourcePolicy._cached.vector_tokens = 1
	assert(vectorizer.embed("alpha") == vectorizer.embed("alpha beta gamma"))
	OwnerResourcePolicy._cached.vector_tokens = 0
	assert(vectorizer.embed("alpha") != vectorizer.embed("alpha beta gamma"))
	OwnerResourcePolicy._cached.vector_tokens = 768
	OwnerResourcePolicy._cached.vector_features = 4096
	var agent := AgentCore.new()
	var messages: Array = []
	var history: Array = []
	for i in range(6): history.append({"role": "user", "content": "АБВГД"})
	OwnerResourcePolicy._cached.direct_history_chars = 3
	agent._append_direct_conversation_context(messages, history)
	assert(messages.size() == 6 and messages[0].content == "АБВ")
	OwnerResourcePolicy._cached.agent_history_items = 0
	OwnerResourcePolicy._cached.attachment_items = 0
	OwnerResourcePolicy._cached.attachment_excerpt_chars = 0
	OwnerResourcePolicy._cached.context_message_chars = 0
	messages.clear()
	agent._append_conversation_context(messages, [{"role": "user", "content": "x", "attachments": [{"name": "a", "excerpt": long_text}, {"name": "b", "excerpt": long_text}]}])
	assert(messages[0].content.contains(long_text) and messages[0].content.contains("тип:"))
	OwnerResourcePolicy._cached.tool_result_chars = 0
	OwnerResourcePolicy._cached.tool_result_items = 0
	assert(agent._compact_result({"text": long_text}).text == long_text)
	assert(agent._compact_result(range(40)).size() == 40)
	OwnerResourcePolicy._cached.tool_result_chars = 3
	assert(agent._compact_result({"text": "АБВГД"}).text == "АБВ…")
	var desktop := DesktopLocalRuntime.new()
	assert(desktop._generation_budget({}, false) == 768)
	OwnerResourcePolicy._cached.chat_max_tokens = 20000
	assert(desktop._generation_budget({}, false) == 20000)
	assert(desktop._generation_budget({"max_tokens": 16}, false) == 16)
	assert(desktop._generation_budget({"max_tokens": 2147483648}, false) == -2)
	assert(desktop._generation_budget({"max_tokens": 1.5}, false) == -2)
	OwnerResourcePolicy._cached.chat_max_tokens = 0
	assert(desktop._generation_budget({}, false) == -1)
	var store := IsolatedMemory.new()
	OwnerResourcePolicy._cached.memory_max_items = 0
	OwnerResourcePolicy._cached.knowledge_max_items = 0
	OwnerResourcePolicy._cached.dedupe_window = 2
	OwnerResourcePolicy._cached.index_text_chars = 0
	for i in range(5): store.remember("fixture", "record" + str(i), "fixture")
	assert(store.memory.size() == 5)
	OwnerResourcePolicy._cached.dedupe_window = 0
	OwnerResourcePolicy.revision += 1
	store.remember("fixture", "record0", "fixture")
	assert(store.memory.size() == 5) # Rebuild expands dedupe coverage after live policy change.
	store.learn(long_text, "fixture")
	assert(store.knowledge[0].content == long_text)
	assert(store._index_queue[-1].content == long_text)
	OwnerResourcePolicy._cached.index_batch = 2
	store._drain_local_index()
	assert(store.vectors.size() == 2 and store._index_queue.size() == 5)
	var old_signature := store._vector_policy_signature
	OwnerResourcePolicy._cached.vector_tokens = 0
	OwnerResourcePolicy.revision += 1
	store._sync_owner_resources()
	assert(store._vector_policy_signature != old_signature and store.vectors.is_empty())
	assert(store._index_queue.size() == store.memory.size() + store.knowledge.size())
	OwnerResourcePolicy._cached.memory_max_items = 3
	store.remember("fixture", "new-record", "fixture")
	assert(store.memory.size() == 3)
	OwnerResourcePolicy._cached = original
	OwnerResourcePolicy.revision += 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	agent.free()
	desktop.free()
	store.free()
	print("AURORA_OWNER_RESOURCE_LIMITS_OK")
	quit(0)
