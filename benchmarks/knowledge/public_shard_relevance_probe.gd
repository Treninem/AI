extends SceneTree

const QUESTION := "Почему лёд плавает в воде?"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var db_path := ProjectSettings.globalize_path(KnowledgeStore.DB_PATH)
	if not db_path.to_lower().contains("public-shard-normalized-profile") or not FileAccess.file_exists(KnowledgeStore.DB_PATH):
		print("PUBLIC_SHARD_RELEVANCE ", JSON.stringify({"ok": false, "error": "isolated store missing"}))
		quit(2)
		return
	var client := AIClient.new()
	var query := client._knowledge_query(QUESTION)
	var terms := query.split(" ", false)
	var started := Time.get_ticks_usec()
	var items := KnowledgeStore.new().search(query, AIClient.MAX_KNOWLEDGE_CONTEXT_ITEMS)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var grounded := AIClient._grounded_knowledge_context(KnowledgeStore.new(), query, false)
	var matches: Array[Dictionary] = []
	for item in items:
		var text := str(item.get("text", "")).to_lower()
		var source := str(item.get("source", "")).to_lower()
		var text_hits := 0
		var source_hits := 0
		var matched_terms: Array[String] = []
		for term in terms:
			if text.contains(term):
				text_hits += 1
				matched_terms.append(term)
			if source.contains(term):
				source_hits += 1
		matches.append({"id_sha256": str(item.get("id", "")).sha256_text(), "text_term_hits": text_hits, "matched_terms": matched_terms, "source_term_hits": source_hits, "text_chars": text.length()})
	print("PUBLIC_SHARD_RELEVANCE ", JSON.stringify({"ok": true, "filtered_query": query, "elapsed_ms": elapsed_ms, "grounded_context_present": not grounded.is_empty(), "hits": matches}))
	quit(0)
