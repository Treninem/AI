class_name MemoryStore
extends Node

signal semantic_index_updated(indexed: int, pending: int)
signal semantic_backend_status(ready: bool, message: String)

const MEMORY_PATH := "user://memory.json"
const KNOWLEDGE_PATH := "user://knowledge.json"
const VECTOR_PATH := "user://memory_vectors.json"
const EMBEDDING_MODEL := "qwen3-embedding:0.6b"
const EMBED_URL := "http://127.0.0.1:11434/api/embed"
const VECTOR_DIMENSIONS := 256
const MAX_MEMORY := 5000
const MAX_KNOWLEDGE := 10000
const EMBED_BATCH := 12
const EMBED_RETRY_SECONDS := 30.0

var memory: Array = []
var knowledge: Array = []
var vectors: Dictionary = {}

var _embed_queue: Array = []
var _queued_ids: Dictionary = {}
var _embedding_busy := false
var _semantic_ready := false
var _next_embedding_retry_unix := 0.0

func _ready() -> void:
	memory = _load_array(MEMORY_PATH)
	knowledge = _load_array(KNOWLEDGE_PATH)
	_load_vector_index()
	var changed := _migrate_collection(memory, "memory")
	changed = _migrate_collection(knowledge, "knowledge") or changed
	if changed:
		_save_array(MEMORY_PATH, memory)
		_save_array(KNOWLEDGE_PATH, knowledge)
	_queue_missing_embeddings(memory, "memory")
	_queue_missing_embeddings(knowledge, "knowledge")
	set_process(true)
	if not _embed_queue.is_empty():
		call_deferred("_drain_embedding_queue")

func _process(_delta: float) -> void:
	if _embedding_busy or _embed_queue.is_empty():
		return
	if Time.get_unix_time_from_system() < _next_embedding_retry_unix:
		return
	call_deferred("_drain_embedding_queue")

func remember(kind: String, content: String, source: String = "", importance: float = 0.55, confidence: float = 0.85) -> void:
	var clean := content.strip_edges()
	if clean.is_empty():
		return
	var duplicate := _find_exact(memory, clean, kind)
	if duplicate >= 0:
		_touch_existing(memory[duplicate], importance, confidence, source)
		_save_array(MEMORY_PATH, memory)
		_queue_item_embedding(memory[duplicate], "memory")
		return
	var item := _make_item("memory", kind, clean, source, importance, confidence)
	memory.append(item)
	if memory.size() > MAX_MEMORY:
		_trim_collection(memory, MAX_MEMORY)
	_save_array(MEMORY_PATH, memory)
	_queue_item_embedding(item, "memory")

func learn(content: String, source: String = "", importance: float = 0.65, confidence: float = 0.80, kind: String = "knowledge") -> void:
	var clean := content.strip_edges()
	if clean.is_empty():
		return
	var duplicate := _find_exact(knowledge, clean, kind)
	if duplicate >= 0:
		_touch_existing(knowledge[duplicate], importance, confidence, source)
		_save_array(KNOWLEDGE_PATH, knowledge)
		_queue_item_embedding(knowledge[duplicate], "knowledge")
		return
	var item := _make_item("knowledge", kind, clean, source, importance, confidence)
	knowledge.append(item)
	if knowledge.size() > MAX_KNOWLEDGE:
		_trim_collection(knowledge, MAX_KNOWLEDGE)
	_save_array(KNOWLEDGE_PATH, knowledge)
	_queue_item_embedding(item, "knowledge")

func recent(limit: int = 12) -> Array:
	if memory.is_empty():
		return []
	var start := maxi(0, memory.size() - limit)
	return memory.slice(start)

func retrieve(query: String, limit: int = 8, include_memory: bool = true, include_knowledge: bool = true) -> Array:
	var clean := query.strip_edges()
	if clean.is_empty() or limit <= 0:
		return []
	var query_vectors := await _embed_batch(["search_query: " + clean])
	var semantic: Array = []
	if not query_vectors.is_empty() and query_vectors[0] is Array and not (query_vectors[0] as Array).is_empty():
		semantic = _semantic_search(query_vectors[0], limit, include_memory, include_knowledge)
	if semantic.is_empty():
		semantic = _lexical_search(clean, limit, include_memory, include_knowledge)
	_touch_results(semantic)
	return semantic

func search_knowledge(query: String, limit: int = 8) -> Array:
	return _lexical_search(query, limit, false, true)

func search_memory(query: String, limit: int = 8) -> Array:
	return _lexical_search(query, limit, true, false)

func semantic_status() -> Dictionary:
	return {
		"ready": _semantic_ready,
		"model": EMBEDDING_MODEL,
		"dimensions": VECTOR_DIMENSIONS,
		"indexed": vectors.size(),
		"pending": _embed_queue.size(),
		"memory_items": memory.size(),
		"knowledge_items": knowledge.size()
	}

func reindex_semantic() -> Dictionary:
	vectors.clear()
	_embed_queue.clear()
	_queued_ids.clear()
	_save_vector_index()
	_queue_missing_embeddings(memory, "memory")
	_queue_missing_embeddings(knowledge, "knowledge")
	await _drain_embedding_queue(true)
	return semantic_status()

func _make_item(collection: String, kind: String, content: String, source: String, importance: float, confidence: float) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	return {
		"id": _new_id(collection, content),
		"time": Time.get_datetime_string_from_system(true),
		"time_unix": now,
		"kind": kind,
		"content": content,
		"source": source,
		"importance": clampf(importance, 0.0, 1.0),
		"confidence": clampf(confidence, 0.0, 1.0),
		"last_used": 0.0,
		"usage_count": 0
	}

func _new_id(collection: String, content: String) -> String:
	var raw := "%s|%s|%s|%s" % [collection, str(Time.get_unix_time_from_system()), content, str(randi())]
	return "%s_%s" % [collection, raw.sha256_text().substr(0, 24)]

func _migrate_collection(items: Array, collection: String) -> bool:
	var changed := false
	for i in range(items.size()):
		if not items[i] is Dictionary:
			continue
		var item: Dictionary = items[i]
		if str(item.get("id", "")).is_empty():
			item["id"] = _new_id(collection, str(item.get("content", "")))
			changed = true
		if not item.has("time_unix"):
			item["time_unix"] = Time.get_unix_time_from_system()
			changed = true
		if not item.has("importance"):
			item["importance"] = 0.55 if collection == "memory" else 0.65
			changed = true
		if not item.has("confidence"):
			item["confidence"] = 0.75
			changed = true
		if not item.has("last_used"):
			item["last_used"] = 0.0
			changed = true
		if not item.has("usage_count"):
			item["usage_count"] = 0
			changed = true
		items[i] = item
	return changed

func _find_exact(items: Array, content: String, kind: String) -> int:
	var needle := _normalize_text(content)
	var start := maxi(0, items.size() - 1000)
	for i in range(items.size() - 1, start - 1, -1):
		if not items[i] is Dictionary:
			continue
		var item: Dictionary = items[i]
		if str(item.get("kind", "")) != kind:
			continue
		if _normalize_text(str(item.get("content", ""))) == needle:
			return i
	return -1

func _touch_existing(item: Dictionary, importance: float, confidence: float, source: String) -> void:
	item["importance"] = maxf(float(item.get("importance", 0.0)), clampf(importance, 0.0, 1.0))
	item["confidence"] = maxf(float(item.get("confidence", 0.0)), clampf(confidence, 0.0, 1.0))
	item["last_used"] = Time.get_unix_time_from_system()
	item["usage_count"] = int(item.get("usage_count", 0)) + 1
	if str(item.get("source", "")).is_empty() and not source.is_empty():
		item["source"] = source

func _trim_collection(items: Array, max_items: int) -> void:
	if items.size() <= max_items:
		return
	var rows: Array = []
	for item in items:
		if not item is Dictionary:
			continue
		var score := float(item.get("importance", 0.5)) * 0.55 + float(item.get("confidence", 0.5)) * 0.25
		score += minf(0.20, log(1.0 + float(item.get("usage_count", 0))) * 0.04)
		rows.append({"score": score, "item": item})
	rows.sort_custom(func(a, b): return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
	var keep: Array = []
	for row in rows.slice(0, mini(max_items, rows.size())):
		keep.append(row.get("item", {}))
	items.clear()
	items.append_array(keep)
	_remove_orphan_vectors()

func _queue_missing_embeddings(items: Array, collection: String) -> void:
	for item in items:
		if item is Dictionary:
			_queue_item_embedding(item, collection)

func _queue_item_embedding(item: Dictionary, collection: String) -> void:
	var id := str(item.get("id", ""))
	var content := str(item.get("content", "")).strip_edges()
	if id.is_empty() or content.is_empty() or vectors.has(id) or _queued_ids.has(id):
		return
	_queued_ids[id] = true
	_embed_queue.append({
		"id": id,
		"collection": collection,
		"content": "search_document: " + content.substr(0, 24000)
	})
	if not _embedding_busy and Time.get_unix_time_from_system() >= _next_embedding_retry_unix:
		call_deferred("_drain_embedding_queue")

func _drain_embedding_queue(force_all: bool = false) -> void:
	if _embedding_busy or _embed_queue.is_empty():
		return
	if not force_all and Time.get_unix_time_from_system() < _next_embedding_retry_unix:
		return
	_embedding_busy = true
	var processed := 0
	while not _embed_queue.is_empty():
		var batch_count := mini(EMBED_BATCH, _embed_queue.size())
		var batch: Array = _embed_queue.slice(0, batch_count)
		_embed_queue = _embed_queue.slice(batch_count, _embed_queue.size())
		var inputs: Array = []
		for row in batch:
			inputs.append(str(row.get("content", "")))
		var embeddings := await _embed_batch(inputs)
		if embeddings.size() != batch.size():
			_embed_queue = batch + _embed_queue
			for row in batch:
				_queued_ids[str(row.get("id", ""))] = true
			_next_embedding_retry_unix = Time.get_unix_time_from_system() + EMBED_RETRY_SECONDS
			_semantic_ready = false
			semantic_backend_status.emit(false, "Embedding backend/model unavailable")
			break
		for i in range(batch.size()):
			var id := str(batch[i].get("id", ""))
			_queued_ids.erase(id)
			var vector = embeddings[i]
			if vector is Array and not (vector as Array).is_empty():
				vectors[id] = vector
				processed += 1
		_save_vector_index()
		_semantic_ready = true
		semantic_backend_status.emit(true, EMBEDDING_MODEL)
		semantic_index_updated.emit(vectors.size(), _embed_queue.size())
		if not force_all:
			break
	_embedding_busy = false
	if processed > 0 and not _embed_queue.is_empty() and not force_all:
		call_deferred("_drain_embedding_queue")

func _embed_batch(inputs: Array) -> Array:
	if inputs.is_empty():
		return []
	var request_node := HTTPRequest.new()
	request_node.timeout = 45.0
	add_child(request_node)
	var payload := {
		"model": EMBEDDING_MODEL,
		"input": inputs,
		"truncate": true,
		"dimensions": VECTOR_DIMENSIONS
	}
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := request_node.request(EMBED_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		request_node.queue_free()
		return []
	var result: Array = await request_node.request_completed
	request_node.queue_free()
	if int(result[1]) != 200:
		return []
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary:
		return []
	var embeddings = parsed.get("embeddings", [])
	return embeddings if embeddings is Array else []

func _semantic_search(query_vector: Array, limit: int, include_memory: bool, include_knowledge: bool) -> Array:
	var scored: Array = []
	if include_memory:
		_score_semantic_collection(memory, "memory", query_vector, scored)
	if include_knowledge:
		_score_semantic_collection(knowledge, "knowledge", query_vector, scored)
	scored.sort_custom(func(a, b): return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
	var out: Array = []
	var seen: Dictionary = {}
	for row in scored:
		var item = row.get("item", {})
		if not item is Dictionary:
			continue
		var id := str(item.get("id", ""))
		if seen.has(id):
			continue
		seen[id] = true
		var copy: Dictionary = item.duplicate(true)
		copy["retrieval_score"] = float(row.get("score", 0.0))
		copy["retrieval"] = "semantic"
		out.append(copy)
		if out.size() >= limit:
			break
	return out

func _score_semantic_collection(items: Array, _collection: String, query_vector: Array, scored: Array) -> void:
	var now := Time.get_unix_time_from_system()
	for item in items:
		if not item is Dictionary:
			continue
		var id := str(item.get("id", ""))
		if not vectors.has(id):
			continue
		var vector = vectors[id]
		if not vector is Array:
			continue
		var similarity := _dot(query_vector, vector)
		if similarity < 0.20:
			continue
		var age_days := maxf(0.0, (now - float(item.get("time_unix", now))) / 86400.0)
		var recency := 1.0 / (1.0 + age_days / 30.0)
		var usage := minf(1.0, log(1.0 + float(item.get("usage_count", 0))) / 5.0)
		var score := similarity * 0.72
		score += clampf(float(item.get("importance", 0.5)), 0.0, 1.0) * 0.12
		score += clampf(float(item.get("confidence", 0.5)), 0.0, 1.0) * 0.08
		score += recency * 0.05
		score += usage * 0.03
		scored.append({"score": score, "item": item})

func _lexical_search(query: String, limit: int, include_memory: bool, include_knowledge: bool) -> Array:
	var words := _tokens(query)
	var scored: Array = []
	if include_memory:
		_score_lexical_collection(memory, words, scored)
	if include_knowledge:
		_score_lexical_collection(knowledge, words, scored)
	scored.sort_custom(func(a, b): return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
	var out: Array = []
	for row in scored.slice(0, mini(limit, scored.size())):
		var item = row.get("item", {})
		if item is Dictionary:
			var copy: Dictionary = item.duplicate(true)
			copy["retrieval_score"] = float(row.get("score", 0.0))
			copy["retrieval"] = "lexical"
			out.append(copy)
	return out

func _score_lexical_collection(items: Array, words: Array[String], scored: Array) -> void:
	for item in items:
		if not item is Dictionary:
			continue
		var text := _normalize_text(str(item.get("content", "")))
		var matches := 0
		for word in words:
			if text.contains(word):
				matches += 1
		if matches <= 0:
			continue
		var coverage := float(matches) / float(maxi(1, words.size()))
		var score := coverage * 0.72 + clampf(float(item.get("importance", 0.5)), 0.0, 1.0) * 0.18 + clampf(float(item.get("confidence", 0.5)), 0.0, 1.0) * 0.10
		scored.append({"score": score, "item": item})

func _touch_results(items: Array) -> void:
	if items.is_empty():
		return
	var ids: Dictionary = {}
	for result in items:
		if result is Dictionary:
			ids[str(result.get("id", ""))] = true
	var now := Time.get_unix_time_from_system()
	var memory_changed := false
	var knowledge_changed := false
	for item in memory:
		if item is Dictionary and ids.has(str(item.get("id", ""))):
			item["last_used"] = now
			item["usage_count"] = int(item.get("usage_count", 0)) + 1
			memory_changed = true
	for item in knowledge:
		if item is Dictionary and ids.has(str(item.get("id", ""))):
			item["last_used"] = now
			item["usage_count"] = int(item.get("usage_count", 0)) + 1
			knowledge_changed = true
	if memory_changed:
		_save_array(MEMORY_PATH, memory)
	if knowledge_changed:
		_save_array(KNOWLEDGE_PATH, knowledge)

func _dot(a: Array, b: Array) -> float:
	var count := mini(a.size(), b.size())
	if count <= 0:
		return 0.0
	var value := 0.0
	for i in range(count):
		value += float(a[i]) * float(b[i])
	return value

func _tokens(text: String) -> Array[String]:
	var normalized := _normalize_text(text)
	var out: Array[String] = []
	for part in normalized.split(" ", false):
		var word := str(part)
		if word.length() > 2 and word not in out:
			out.append(word)
	return out

func _normalize_text(text: String) -> String:
	var out := ""
	for i in range(text.length()):
		var c := text.substr(i, 1).to_lower()
		var code := c.unicode_at(0)
		var alpha_num := (code >= 48 and code <= 57) or (code >= 97 and code <= 122)
		var cyrillic := code >= 0x0400 and code <= 0x052f
		out += c if alpha_num or cyrillic else " "
	return " ".join(out.split(" ", false))

func _remove_orphan_vectors() -> void:
	var ids: Dictionary = {}
	for item in memory:
		if item is Dictionary:
			ids[str(item.get("id", ""))] = true
	for item in knowledge:
		if item is Dictionary:
			ids[str(item.get("id", ""))] = true
	for id in vectors.keys():
		if not ids.has(str(id)):
			vectors.erase(id)
	_save_vector_index()

func _load_vector_index() -> void:
	vectors = {}
	if not FileAccess.file_exists(VECTOR_PATH):
		return
	var file := FileAccess.open(VECTOR_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	if str(parsed.get("model", "")) != EMBEDDING_MODEL or int(parsed.get("dimensions", 0)) != VECTOR_DIMENSIONS:
		return
	var stored = parsed.get("vectors", {})
	if stored is Dictionary:
		vectors = stored

func _save_vector_index() -> void:
	_save_json(VECTOR_PATH, {
		"model": EMBEDDING_MODEL,
		"dimensions": VECTOR_DIMENSIONS,
		"updated_at": Time.get_datetime_string_from_system(true),
		"vectors": vectors
	})

func _load_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Array else []

func _save_array(path: String, data: Array) -> void:
	_save_json(path, data)

func _save_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()
