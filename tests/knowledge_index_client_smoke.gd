extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var db_path := ProjectSettings.globalize_path(KnowledgeStore.DB_PATH)
	if not db_path.to_lower().contains("index-client-fallback-profile") or not FileAccess.file_exists(KnowledgeStore.DB_PATH):
		_fail("synthetic profile missing")
		return
	var index_client = load("res://scripts/knowledge_index_client.gd")
	var indexed: Dictionary = index_client.search("mars", 8)
	if not bool(indexed.get("ok", false)) or not indexed.get("results", null) is Array:
		_fail("valid synthetic index was not used")
		return
	var native := KnowledgeStore.new().search("mars", 8)
	if indexed["results"].size() != native.size():
		_fail("indexed result count differs from native search")
		return
	var russian: Dictionary = index_client.search("лёд плавает воде", 8)
	if not bool(russian.get("ok", false)) or not russian.get("results", null) is Array or russian["results"].is_empty():
		_fail("indexed Russian query failed")
		return
	var added := KnowledgeStore.new().import_text("Mars has a new synthetic note.", "synthetic://fresh")
	if not bool(added.get("ok", false)):
		_fail("synthetic append failed")
		return
	if bool(index_client.search("mars", 8).get("ok", false)):
		_fail("stale index was accepted after append")
		return
	var rebuilt: Dictionary = index_client.rebuild()
	if not bool(rebuilt.get("ok", false)) or int(rebuilt.get("indexed_rows", 0)) <= 0:
		_fail("synthetic index rebuild failed")
		return
	if not bool(index_client.search("mars", 8).get("ok", false)):
		_fail("rebuilt index was not used")
		return
	# A later source mutation must still fall back to the canonical store.
	added = KnowledgeStore.new().import_text("Mars has another synthetic note.", "synthetic://fresh-2")
	if not bool(added.get("ok", false)) or bool(index_client.search("mars", 8).get("ok", false)):
		_fail("rebuilt index did not become stale after a second append")
		return
	var client := AIClient.new()
	root.add_child(client)
	var grounded: Array = client._with_knowledge([{"role": "user", "content": "По базе знаний: расскажи про Mars"}])
	if grounded.size() != 2:
		_fail("AIClient did not fall back to native Knowledge search")
		return
	print("KNOWLEDGE_INDEX_CLIENT_SMOKE_PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
