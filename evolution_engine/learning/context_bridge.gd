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

	# MemoryStore can search both memory and its legacy knowledge collection.
	# Evolution requests memory only here because canonical KnowledgeStore is
	# queried separately below. This prevents duplicate context from being
	# counted as independent evidence.
	var memory_rows = memory.retrieve(goal, safe_memory_limit, true, false)
	var knowledge_rows = knowledge.search(goal, safe_knowledge_limit)
	var compact_memory := _compact_rows(memory_rows, safe_memory_limit, {})
	var seen := _fingerprints(compact_memory)
	var compact_knowledge := _compact_rows(knowledge_rows, safe_knowledge_limit, seen)
	return {
		"ok": true,
		"memory": compact_memory,
		"knowledge": compact_knowledge,
		"memory_count": compact_memory.size(),
		"knowledge_count": compact_knowledge.size()
	}

func _compact_rows(value: Variant, limit: int, seen: Dictionary) -> Array:
	var out: Array = []
	if not value is Array:
		return out
	for row in value:
		if out.size() >= limit:
			break
		if not row is Dictionary:
			continue
		var compact := _compact_row(row)
		var fingerprint := _fingerprint(compact)
		if fingerprint.is_empty() or seen.has(fingerprint):
			continue
		seen[fingerprint] = true
		out.append(compact)
	return out

func _fingerprints(rows: Array) -> Dictionary:
	var seen: Dictionary = {}
	for row in rows:
		if row is Dictionary:
			var fingerprint := _fingerprint(row)
			if not fingerprint.is_empty():
				seen[fingerprint] = true
	return seen

func _fingerprint(row: Dictionary) -> String:
	var content := str(row.get("content", "")).strip_edges().to_lower()
	if not content.is_empty():
		return "content:" + content.substr(0, 700)
	var id := str(row.get("id", "")).strip_edges()
	if not id.is_empty():
		return "id:" + id
	return ""

func _compact_row(row: Dictionary) -> Dictionary:
	return {
		"id": str(row.get("id", "")).substr(0, 120),
		"kind": str(row.get("kind", "")).substr(0, 120),
		"source": str(row.get("source", "")).substr(0, 500),
		"content": str(row.get("content", row.get("text", ""))).substr(0, MAX_CONTENT_CHARS),
		"score": float(row.get("retrieval_score", row.get("score", 0.0))),
		"importance": float(row.get("importance", 0.0)),
		"confidence": float(row.get("confidence", 0.0))
	}
