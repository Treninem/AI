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
	if str(ranked[0].get("retrieval", "")) != "local_vector":
		_fail("Local-vector retrieval marker is missing", 3)
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

	# Exact dedupe is a public learn() behavior. Keep this smoke independent from
	# the private index representation so internal performance refactors do not
	# invalidate the contract test while normalized duplicates still must collapse.
	var before_dedupe := store.knowledge.size()
	store.learn("Короткие ответы", "dialog", 0.70, 0.80, "preference")
	store.learn("  КОРОТКИЕ   ответы ", "dialog", 0.75, 0.85, "preference")
	if store.knowledge.size() != before_dedupe + 1:
		_fail("Exact normalized deduplication through learn() failed", 6)
		store.free()
		return
	var deduped: Dictionary = store.knowledge[store.knowledge.size() - 1]
	if int(deduped.get("usage_count", 0)) != 1:
		_fail("Duplicate learn() did not touch the existing item", 6)
		store.free()
		return

	var status := store.semantic_status()
	if not bool(status.get("enabled", false)):
		_fail("AuroraFox local semantic memory is unexpectedly disabled: " + JSON.stringify(status), 7)
		store.free()
		return
	if str(status.get("provider", "")) != "aurorafox_local_vector" or not str(status.get("endpoint", "x")).is_empty():
		_fail("Default memory provider is not fully local: " + JSON.stringify(status), 8)
		store.free()
		return
	if str(status.get("model", "")) != "aurorafox-local-vector-v1" or int(status.get("dimensions", 0)) != 256:
		_fail("Local semantic vector contract changed unexpectedly: " + JSON.stringify(status), 9)
		store.free()
		return
	if bool(status.get("network_required", true)) or bool(status.get("external_runtime_required", true)) or bool(status.get("ollama_required", true)):
		_fail("Local semantic memory unexpectedly depends on network/Ollama: " + JSON.stringify(status), 10)
		store.free()
		return
	if bool(status.get("legacy_compat_setting", true)):
		_fail("Legacy semantic compatibility must remain disabled by default: " + JSON.stringify(status), 11)
		store.free()
		return

	# When no vector exists for an item, retrieval must still fall back to the
	# fully local lexical path rather than contacting an external embedding API.
	store.vectors.clear()
	var lexical: Array = await store.retrieve("краткие технические ответы", 2, false, true)
	if lexical.is_empty() or str(lexical[0].get("id", "")) != "knowledge_relevant":
		_fail("Local lexical fallback retrieval failed: " + JSON.stringify(lexical), 12)
		store.free()
		return
	if str(lexical[0].get("retrieval", "")) != "lexical":
		_fail("Local lexical retrieval marker is missing", 13)
		store.free()
		return

	var agent_source := FileAccess.get_file_as_string("res://scripts/agent_core.gd")
	if not agent_source.contains("await memory.retrieve(task") or not agent_source.contains("Релевантная долговременная память"):
		_fail("AgentCore is not wired to memory retrieval", 14)
		store.free()
		return

	store.free()
	print("AURORA_SEMANTIC_MEMORY_SMOKE_OK provider=aurorafox_local_vector fallback=lexical network=false ollama=false")
	quit(0)