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
	var weak_import := knowledge.import_text("Лёд формируется в воде при низкой температуре.", "synthetic://weak-ice")
	if not bool(weak_import.get("ok", false)):
		_fail("weak synthetic Knowledge import failed")
		return
	var ordinary: Array = client._with_knowledge([{"role": "user", "content": "Почему лёд плавает в воде?"}])
	if ordinary.size() != 1:
		_fail("ordinary question received weak Knowledge context")
		return
	var ordinary_async: Array = await client._with_knowledge_async([{"role": "user", "content": "Почему лёд плавает в воде?"}])
	if ordinary_async.size() != 1:
		_fail("async ordinary question received weak Knowledge context")
		return
	var ordinary_english: Array = client._with_knowledge([{"role": "user", "content": "What moons does Mars have?"}])
	if ordinary_english.size() != 2 or not str(ordinary_english[0].get("content", "")).contains("synthetic://mars"):
		_fail("ordinary English question lost relevant Knowledge")
		return
	var explicit_ice: Array = client._with_knowledge([{"role": "user", "content": "По базе знаний: почему лёд плавает в воде?"}])
	if explicit_ice.size() != 2 or not str(explicit_ice[0].get("content", "")).contains("synthetic://weak-ice"):
		_fail("explicit Knowledge request lost weak lexical source")
		return
	var strong_import := knowledge.import_text("Лёд плавает в воде благодаря меньшей плотности.", "synthetic://strong-ice")
	if not bool(strong_import.get("ok", false)):
		_fail("strong synthetic Knowledge import failed")
		return
	var grounded: Array = client._with_knowledge([{"role": "user", "content": "Почему лёд плавает в воде?"}])
	if grounded.size() != 2 or not str(grounded[0].get("content", "")).contains("synthetic://strong-ice"):
		_fail("ordinary question lost strongly grounded Knowledge")
		return
	print("WINDOWS_CHAT_CONTEXT_SMOKE_PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
