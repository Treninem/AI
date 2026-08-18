class_name MemoryStore
extends Node

const MEMORY_PATH := "user://memory.json"
const KNOWLEDGE_PATH := "user://knowledge.json"

var memory: Array = []
var knowledge: Array = []

func _ready() -> void:
	memory = _load_array(MEMORY_PATH)
	knowledge = _load_array(KNOWLEDGE_PATH)

func remember(kind: String, content: String, source: String = "") -> void:
	memory.append({
		"time": Time.get_datetime_string_from_system(true),
		"kind": kind,
		"content": content,
		"source": source
	})
	if memory.size() > 5000:
		memory = memory.slice(memory.size() - 5000)
	_save_array(MEMORY_PATH, memory)

func learn(content: String, source: String = "") -> void:
	knowledge.append({
		"time": Time.get_datetime_string_from_system(true),
		"content": content,
		"source": source
	})
	if knowledge.size() > 10000:
		knowledge = knowledge.slice(knowledge.size() - 10000)
	_save_array(KNOWLEDGE_PATH, knowledge)

func recent(limit: int = 12) -> Array:
	if memory.is_empty():
		return []
	var start := maxi(0, memory.size() - limit)
	return memory.slice(start)

func search_knowledge(query: String, limit: int = 8) -> Array:
	var words := query.to_lower().split(" ", false)
	var scored: Array = []
	for item in knowledge:
		var text := str(item.get("content", "")).to_lower()
		var score := 0
		for word in words:
			if word.length() > 2 and text.contains(word):
				score += 1
		if score > 0:
			scored.append({"score": score, "item": item})
	scored.sort_custom(func(a, b): return int(a.score) > int(b.score))
	var out: Array = []
	for row in scored.slice(0, mini(limit, scored.size())):
		out.append(row.item)
	return out

func _load_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []

func _save_array(path: String, data: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
