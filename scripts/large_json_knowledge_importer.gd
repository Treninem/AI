class_name LargeJsonKnowledgeImporter
extends RefCounted

const LARGE_JSON_THRESHOLD_BYTES := 8 * 1024 * 1024

var reader := AuroraJsonStreamReader.new()

func should_stream(path: String) -> bool:
	if path.get_extension().to_lower() != "json" or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var size := file.get_length()
	file.close()
	return size >= LARGE_JSON_THRESHOLD_BYTES

func import_file(store: KnowledgeStore, path: String, metadata: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "JSON-файл не найден", "path": path}
	var removed := store.remove_source(path)
	if not bool(removed.get("ok", false)):
		return removed
	var state := store._structured_state()
	var meta := metadata.duplicate(true)
	meta["format"] = "json"
	meta["original_file"] = path
	meta["streaming"] = true
	meta["stream_parser"] = "aurora_json_stream_v1"
	meta["scope"] = str(meta.get("scope", "core_knowledge"))
	var parsed := reader.parse_file(path, func(json_path: String, value: Variant) -> Dictionary:
		return store._import_structured_value(path, json_path, value, "json", meta, state)
	)
	if not bool(parsed.get("ok", false)):
		return parsed
	var result := store._structured_result(path, "json", state, true)
	if not bool(result.get("ok", false)):
		return result
	result["stream_parser"] = "aurora_json_stream_v1"
	result["stream_records"] = int(parsed.get("records", 0))
	result["max_depth"] = int(parsed.get("max_depth", 0))
	result["bytes_read"] = int(parsed.get("bytes_read", 0))
	result["memory_model"] = "bounded_by_single_scalar_and_knowledge_chunk"
	return result
