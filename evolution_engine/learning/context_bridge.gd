class_name AuroraEvolutionContextBridge
extends RefCounted

const MAX_CONTEXT_ITEMS := 12
const MAX_CONTENT_CHARS := 900

var memory
var knowledge

func bind(memory_value, knowledge_value) -> void:
	memory = memory_value
	knowledge = knowledge_value

func available() -> bool:
	return (
		memory != null
		and memory.has_method("retrieve")
		and knowledge != null
		and knowledge.has_method("search")
	)

func build(goal: String, memory_limit := 6, knowledge_limit := 6) -> Dictionary:
	if not available():
		return {"ok": false, "memory": [], "knowledge": [], "error": "existing MemoryStore/KnowledgeStore retrieval is unavailable"}
	var safe_memory_limit := clampi(memory_limit, 1, MAX_CONTEXT_ITEMS)
	var safe_knowledge_limit := clampi(knowledge_limit, 1, MAX_CONTEXT_ITEMS)
	var memory_rows = memory.retrieve(goal, safe_memory_limit, true, true)
	var knowledge_rows = knowledge.search(goal, safe_knowledge_limit)
	return {
		"ok": true,
		"memory": _compact_rows(memory_rows, safe_memory_limit),
		"knowledge": _compact_rows(knowledge_rows, safe_knowledge_limit)
	}

func _compact_rows(value: Variant, limit: int) -> Array:
	var out: Array = []
	if not value is Array:
		return out
	for row in value:
		if out.size() >= limit:
			break
		if row is Dictionary:
			out.append(_compact_row(row))
	return out

func _compact_row(row: Dictionary) -> Dictionary:
	return {
		"id": str(row.get("id", "")).substr(0, 120),
		"kind": str(row.get("kind", "")).substr(0, 120),
		"source": str(row.get("source", "")).substr(0, 500),
		"content": str(row.get("content", row.get("text", ""))).substr(0, MAX_CONTENT_CHARS),
		"score": float(row.get("score", 0.0)),
		"importance": float(row.get("importance", 0.0)),
		"confidence": float(row.get("confidence", 0.0))
	}
