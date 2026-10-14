extends SceneTree

const QUERIES := [
	"литв",
	"литовская республика",
	"перенаправление",
	"гидроэлектростанция",
	"россия",
	"Почему лёд плавает в воде?",
	"knowledge-00000",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var db_path := ProjectSettings.globalize_path(KnowledgeStore.DB_PATH)
	if not db_path.to_lower().contains("public-shard-normalized-profile") or not FileAccess.file_exists(KnowledgeStore.DB_PATH):
		print("PUBLIC_SHARD_NATIVE_SEARCH ", JSON.stringify({"ok": false, "error": "isolated normalized store missing"}))
		quit(2)
		return
	var file := FileAccess.open(KnowledgeStore.DB_PATH, FileAccess.READ)
	var bytes := file.get_length()
	file.close()
	var store := KnowledgeStore.new()
	var results: Array[Dictionary] = []
	for query in QUERIES:
		var started := Time.get_ticks_usec()
		var hits := store.search(query, 64)
		var digests: Array[String] = []
		for item in hits:
			if item is Dictionary:
				digests.append(str(item.get("id", "")).sha256_text())
		results.append({
			"query": query,
			"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
			"returned": hits.size(),
			"id_digests": digests,
		})
	print("PUBLIC_SHARD_NATIVE_SEARCH ", JSON.stringify({"ok": true, "normalized_jsonl_bytes": bytes, "queries": results}))
	quit(0)
