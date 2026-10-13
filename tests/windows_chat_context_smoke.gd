extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var knowledge := KnowledgeStore.new()
	var imported := knowledge.import_text("Mars has two moons named Phobos and Deimos.", "synthetic://mars")
	if not bool(imported.get("ok", false)):
		_fail("synthetic Knowledge import failed")
		return
	var client := AIClient.new()
	root.add_child(client)
	var arithmetic: Array = client._with_knowledge([{"role": "user", "content": "Сколько будет 6 умножить на 7? Ответь одним числом."}])
	if arithmetic.size() != 1:
		_fail("simple arithmetic unexpectedly loaded Knowledge")
		return
	var requested: Array = client._with_knowledge([{"role": "user", "content": "По базе знаний: какие спутники есть у Mars?"}])
	if requested.size() != 2 or not str(requested[0].get("content", "")).contains("Phobos"):
		_fail("explicit Knowledge query lost synthetic source")
		return
	var async_requested: Array = await client._with_knowledge_async([{"role": "user", "content": "По базе знаний: какие спутники есть у Mars?"}])
	if async_requested.size() != 2 or not str(async_requested[0].get("content", "")).contains("Phobos"):
		_fail("asynchronous Knowledge query lost synthetic source")
		return
	var long_import := knowledge.import_text("Mars " + "synthetic context ".repeat(500), "synthetic://long-mars")
	if not bool(long_import.get("ok", false)):
		_fail("long synthetic Knowledge import failed")
		return
	var bounded: Array = await client._with_knowledge_async([{"role": "user", "content": "По базе знаний: расскажи про Mars"}])
	if bounded.size() != 2 or str(bounded[0].get("content", "")).length() > AIClient.MAX_KNOWLEDGE_CONTEXT_CHARS + 300:
		_fail("Knowledge prompt exceeded context budget")
		return
	if not str(bounded[0].get("content", "")).contains("Контекст знаний сокращён"):
		_fail("truncated Knowledge context was not marked honestly")
		return
	print("WINDOWS_CHAT_CONTEXT_SMOKE_PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
