extends SceneTree

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _init() -> void:
	var store := MemoryStore.new()
	store.memory = []
	store.knowledge = [
		{
			"id": "knowledge_relevant",
			"time": "2026-08-19T12:00:00Z",
			"time_unix": Time.get_unix_time_from_system(),
			"kind": "preference",
			"content": "Пользователь предпочитает краткие технические ответы с рабочим кодом.",
			"source": "dialog",
			"importance": 0.95,
			"confidence": 0.98,
			"last_used": 0.0,
			"usage_count": 3
		},
		{
			"id": "knowledge_noise",
			"time": "2026-08-19T12:00:00Z",
			"time_unix": Time.get_unix_time_from_system(),
			"kind": "note",
			"content": "Сегодня был обновлён не связанный с ответами тестовый файл.",
			"source": "log",
			"importance": 0.25,
			"confidence": 0.60,
			"last_used": 0.0,
			"usage_count": 0
		}
	]
	store.vectors = {
		"knowledge_relevant": [1.0, 0.0, 0.0, 0.0],
		"knowledge_noise": [0.0, 1.0, 0.0, 0.0]
	}

	var ranked: Array = store._semantic_search([1.0, 0.0, 0.0, 0.0], 2, false, true)
	if ranked.is_empty() or str(ranked[0].get("id", "")) != "knowledge_relevant":
		_fail("Semantic memory did not rank the relevant fact first: " + JSON.stringify(ranked), 2)
		store.free()
		return
	if str(ranked[0].get("retrieval", "")) != "semantic":
		_fail("Semantic retrieval marker is missing", 3)
		store.free()
		return

	var legacy: Array = [{"kind":"legacy", "content":"Старый факт", "source":"old"}]
	if not store._migrate_collection(legacy, "knowledge"):
		_fail("Legacy memory migration did not report changes", 4)
		store.free()
		return
	var migrated: Dictionary = legacy[0]
	for required_key in ["id", "time_unix", "importance", "confidence", "last_used", "usage_count"]:
		if not migrated.has(required_key):
			_fail("Migrated memory is missing metadata: %s" % required_key, 5)
			store.free()
			return

	var duplicates: Array = [
		{"kind":"preference", "content":"Короткие ответы", "source":"dialog"},
		{"kind":"preference", "content":"Другая запись", "source":"dialog"}
	]
	if store._find_exact(duplicates, "  КОРОТКИЕ   ответы ", "preference") != 0:
		_fail("Exact normalized deduplication failed", 6)
		store.free()
		return

	var status := store.semantic_status()
	if str(status.get("model", "")) != "qwen3-embedding:0.6b" or int(status.get("dimensions", 0)) != 256:
		_fail("Semantic memory model/index contract is wrong: " + JSON.stringify(status), 7)
		store.free()
		return

	var agent_source := FileAccess.get_file_as_string("res://scripts/agent_core.gd")
	if not agent_source.contains("await memory.retrieve(task") or not agent_source.contains("Релевантная долговременная память"):
		_fail("AgentCore is not wired to semantic retrieval", 8)
		store.free()
		return

	store.free()
	print("AURORA_SEMANTIC_MEMORY_SMOKE_OK")
	quit(0)
