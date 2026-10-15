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
	print("WINDOWS_CHAT_CONTEXT_SMOKE_PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
