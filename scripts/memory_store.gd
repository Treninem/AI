class_name MemoryStore
extends Node

signal semantic_index_updated(indexed: int, pending: int)
signal semantic_backend_status(ready: bool, message: String)

const MEMORY_PATH := "user://memory.json"
const KNOWLEDGE_PATH := "user://knowledge.json"
const VECTOR_PATH := "user://memory_vectors.json"
const CORE_SETTINGS_PATH := "user://aurora_core_settings.json"
const VECTOR_MODEL := AuroraLocalSemanticVectorizer.MODEL_ID
const VECTOR_DIMENSIONS := AuroraLocalSemanticVectorizer.DIMENSIONS
const MAX_MEMORY := 5000
const MAX_KNOWLEDGE := 10000
const LOCAL_INDEX_BATCH := 64
const EXACT_DEDUPE_WINDOW := 1000

var memory: Array = []
var knowledge: Array = []
var vectors: Dictionary = {}
var vectorizer := AuroraLocalSemanticVectorizer.new()

var _index_queue: Array = []
var _queued_ids: Dictionary = {}
var _index_busy := false
var _semantic_ready := false
var _memory_exact_index: Dictionary = {}
var _knowledge_exact_index: Dictionary = {}
var _memory_dirty := false
var _knowledge_dirty := false
var _persistence_flush_scheduled := false
# Kept only as compatibility state for settings/UI. Memory retrieval no longer
# contacts Ollama even when the general Ollama compatibility switch is enabled.
var _legacy_semantic_compat_enabled := false

func _ready() -> void:
	memory = _load_array(MEMORY_PATH)
	knowledge = _load_array(KNOWLEDGE_PATH)
	_load_vector_index()
	_load_core_settings()
	var changed := _migrate_collection(memory, "memory")
	changed = _migrate_collection(knowledge, "knowledge") or changed
	if changed:
		_save_array(MEMORY_PATH, memory)
		_save_array(KNOWLEDGE_PATH, knowledge)
	_rebuild_exact_index(memory, _memory_exact_index)
	_rebuild_exact_index(knowledge, _knowledge_exact_index)
	_queue_missing_vectors(memory, "memory")
	_queue_missing_vectors(knowledge, "knowledge")
	_semantic_ready = vectors.size() > 0 or (_index_queue.is_empty() and memory.is_empty() and knowledge.is_empty())
	set_process(true)
	if not _index_queue.is_empty():
		call_deferred("_drain_local_index")
	else:
		semantic_backend_status.emit(true, VECTOR_MODEL)

func _exit_tree() -> void:
	flush_persistence()

func _process(_delta: float) -> void:
	if _index_busy or _index_queue.is_empty():
		return
	call_deferred("_drain_local_index")

func set_legacy_semantic_compat_enabled(enabled: bool) -> void:
	_legacy_semantic_compat_enabled = enabled
	# Deliberately no HTTP request and no background queue switch here. The local
	# AuroraFox vector index remains the authoritative memory backend.
	semantic_backend_status.emit(true, VECTOR_MODEL)

func legacy_semantic_compat_enabled() -> bool:
	return _legacy_semantic_compat_enabled

func remember(kind: String, content: String, source: String = "", importance: float = 0.55, confidence: float = 0.85) -> void:
	var clean := content.strip_edges()
	if clean.is_empty():
		return
	var duplicate := _find_exact(_memory_exact_index, clean, kind)
	if duplicate >= 0:
		_touch_existing(memory[duplicate], importance, confidence, source)
		_schedule_persistence(true, false)
		_queue_item_vector(memory[duplicate], "memory")
		return
	var item := _make_item("memory", kind, clean, source, importance, confidence)
	memory.append(item)
	if memory.size() > MAX_MEMORY:
		_trim_collection(memory, MAX_MEMORY)
		_rebuild_exact_index(memory, _memory_exact_index)
	else:
		_index_exact_item(memory, _memory_exact_index, item)
	_schedule_persistence(true, false)
	_queue_item_vector(item, "memory")

func learn(content: String, source: String = "", importance: float = 0.65, confidence: float = 0.80, kind: String = "knowledge") -> void:
	var clean := content.strip_edges()
	if clean.is_empty():
		return
	var duplicate := _find_exact(_knowledge_exact_index, clean, kind)
	if duplicate >= 0:
		_touch_existing(knowledge[duplicate], importance, confidence, source)
		_schedule_persistence(false, true)
		_queue_item_vector(knowledge[duplicate], "knowledge")
		return
	var item := _make_item("knowledge", kind, clean, source, importance, confidence)
	knowledge.append(item)
	if knowledge.size() > MAX_KNOWLEDGE:
		_trim_collection(knowledge, MAX_KNOWLEDGE)
		_rebuild_exact_index(knowledge, _knowledge_exact_index)
	else:
		_index_exact_item(knowledge, _knowledge_exact_index, item)
	_schedule_persistence(false, true)
	_queue_item_vector(item, "knowledge")

func flush_persistence() -> void:
	_persistence_flush_scheduled = false
	if _memory_dirty:
		_save_array(MEMORY_PATH, memory)
		_memory_dirty = false
	if _knowledge_dirty:
		_save_array(KNOWLEDGE_PATH, knowledge)
		_knowledge_dirty = false

func _schedule_persistence(memory_changed: bool, knowledge_changed: bool) -> void:
	_memory_dirty = _memory_dirty or memory_changed
	_knowledge_dirty = _knowledge_dirty or knowledge_changed
	if not _memory_dirty and not _knowledge_dirty:
		return
	# Coalesce burst imports to one canonical JSON rewrite in the next idle turn.
	# Detached/test instances keep the old immediate durability behaviour.
	if not is_inside_tree():
		flush_persistence()
		return
	if _persistence_flush_scheduled:
		return
	_persistence_flush_scheduled = true
	call_deferred("flush_persistence")

func recent(limit: int = 12) -> Array:
	if memory.is_empty():
		return []
	var start := maxi(0, memory.size() - limit)
	return memory.slice(start)

func retrieve(query: String, limit: int = 8, include_memory: bool = true, include_knowledge: bool = true) -> Array:
	var clean := query.strip_edges()
	if clean.is_empty() or limit <= 0:
		return []
	var query_vector := vectorizer.embed(clean)
	var semantic := _semantic_search(query_vector, limit, include_memory, include_knowledge)
	var lexical := _lexical_search(clean, limit, include_memory, include_knowledge)
	var result := _merge_results(semantic, lexical, limit)
	_touch_results(result)
	return result

func search_knowledge(query: String, limit: int = 8) -> Array:
	if query.strip_edges().is_empty() or limit <= 0:
		return []
	return _merge_results(
		_semantic_search(vectorizer.embed(query), limit, false, true),
		_lexical_search(query, limit, false, true),
		limit
	)

func search_memory(query: String, limit: int = 8) -> Array:
	if query.strip_edges().is_empty() or limit <= 0:
		return []
	return _merge_results(
		_semantic_search(vectorizer.embed(query), limit, true, false),
		_lexical_search(query, limit, true, false),
		limit
	)

func semantic_status() -> Dictionary:
	return {
		"ready": _semantic_ready,
		"enabled": true,
		"provider": "aurorafox_local_vector",
		"model": VECTOR_MODEL,
		"endpoint": "",
		"dimensions": VECTOR_DIMENSIONS,
		"indexed": vectors.size(),
		"pending": _index_queue.size(),
		"memory_items": memory.size(),
		"knowledge_items": knowledge.size(),
		"network_required": false,
		"external_runtime_required": false,
		"ollama_required": false,
		"legacy_compat_setting": _legacy_semantic_compat_enabled,
		"local_fallback": "lexical"
	}

func reindex_semantic() -> Dictionary:
	flush_persistence()
	vectors.clear()
	_index_queue.clear()
	_queued_ids.clear()
	_save_vector_index()
	_queue_missing_vectors(memory, "memory")
	_queue_missing_vectors(knowledge, "knowledge")
	_drain_local_index(true)
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

func _exact_key(kind: String, content: String) -> String:
	return kind + "\n" + _normalize_text(content)

func _find_exact(index: Dictionary, content: String, kind: String) -> int:
	return int(index.get(_exact_key(kind, content), -1))

func _rebuild_exact_index(items: Array, index: Dictionary) -> void:
	index.clear()
	var start := maxi(0, items.size() - EXACT_DEDUPE_WINDOW)
	for i in range(start, items.size()):
		if not items[i] is Dictionary:
			continue
		var item: Dictionary = items[i]
		index[_exact_key(str(item.get("kind", "")), str(item.get("content", "")))] = i

func _index_exact_item(items: Array, index: Dictionary, item: Dictionary) -> void:
	var item_index := items.size() - 1
	if item_index < 0:
		return
	index[_exact_key(str(item.get("kind", "")), str(item.get("content", "")))] = item_index
	var expired_index := item_index - EXACT_DEDUPE_WINDOW
	if expired_index < 0 or expired_index >= items.size() or not items[expired_index] is Dictionary:
		return
	var expired: Dictionary = items[expired_index]
	var expired_key := _exact_key(str(expired.get("kind", "")), str(expired.get("content", "")))
	if int(index.get(expired_key, -1)) == expired_index:
		index.erase(expired_key)

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

func _queue_missing_vectors(items: Array, collection: String) -> void:
	for item in items:
		if item is Dictionary:
			_queue_item_vector(item, collection)

func _queue_item_vector(item: Dictionary, collection: String) -> void:
	var id := str(item.get("id", ""))
	var content := str(item.get("content", "")).strip_edges()
	if id.is_empty() or content.is_empty() or vectors.has(id) or _queued_ids.has(id):
		return
	_queued_ids[id] = true
	_index_queue.append({
		"id": id,
		"collection": collection,
		"content": content.substr(0, 24000)
	})
	if not _index_busy:
		call_deferred("_drain_local_index")

func _drain_local_index(force_all: bool = false) -> void:
	if _index_busy or _index_queue.is_empty():
		if _index_queue.is_empty():
			_semantic_ready = true
		return
	_index_busy = true
	var processed := 0
	while not _index_queue.is_empty():
		var batch_count := mini(LOCAL_INDEX_BATCH, _index_queue.size())
		var batch: Array = _index_queue.slice(0, batch_count)
		_index_queue = _index_queue.slice(batch_count, _index_queue.size())
		for row in batch:
			var id := str(row.get("id", ""))
			_queued_ids.erase(id)
			var content := str(row.get("content", ""))
			var vector := vectorizer.embed(content)
			if not id.is_empty() and vector is Array and not vector.is_empty():
				vectors[id] = vector
				processed += 1
		if not force_all:
			break
	_save_vector_index()
	_index_busy = false
	_semantic_ready = _index_queue.is_empty() or not vectors.is_empty()
	semantic_index_updated.emit(vectors.size(), _index_queue.size())
	semantic_backend_status.emit(true, VECTOR_MODEL)
	if processed > 0 and not _index_queue.is_empty() and not force_all:
		call_deferred("_drain_local_index")

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
		copy["retrieval"] = "local_vector"
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
		var similarity := vectorizer.similarity(query_vector, vector)
		if similarity < 0.10:
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

func _merge_results(primary: Array, secondary: Array, limit: int) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for source in [primary, secondary]:
		for item in source:
			if not item is Dictionary:
				continue
			var id := str(item.get("id", ""))
			if id.is_empty():
				id = str(item.get("content", "")).sha256_text()
			if seen.has(id):
				continue
			seen[id] = true
			out.append(item)
			if out.size() >= limit:
				return out
	return out

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
	_schedule_persistence(memory_changed, knowledge_changed)

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
	if str(parsed.get("model", "")) != VECTOR_MODEL or int(parsed.get("dimensions", 0)) != VECTOR_DIMENSIONS:
		return
	var stored = parsed.get("vectors", {})
	if stored is Dictionary:
		vectors = stored

func _save_vector_index() -> void:
	_save_json(VECTOR_PATH, {
		"model": VECTOR_MODEL,
		"dimensions": VECTOR_DIMENSIONS,
		"provider": "aurorafox_local_vector",
		"network_required": false,
		"updated_at": Time.get_datetime_string_from_system(true),
		"vectors": vectors
	})

func _load_core_settings() -> void:
	_legacy_semantic_compat_enabled = false
	if not FileAccess.file_exists(CORE_SETTINGS_PATH):
		return
	var file := FileAccess.open(CORE_SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_legacy_semantic_compat_enabled = bool(parsed.get("ollama_fallback", false))

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