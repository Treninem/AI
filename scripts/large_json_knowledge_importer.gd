class_name LargeJsonKnowledgeImporter
extends RefCounted

const LARGE_JSON_THRESHOLD_BYTES := 8 * 1024 * 1024
const MAX_AGGREGATE_FIELDS := 64
const MAX_AGGREGATE_CHARS := 256 * 1024

var reader := AuroraJsonStreamReader.new()
var _store: KnowledgeStore
var _source := ""
var _meta: Dictionary = {}
var _state: Dictionary = {}
var _pending_parent := ""
var _pending_object: Dictionary = {}
var _pending_chars := 0
var _aggregated_records := 0

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
	_store = store
	_source = path
	_state = store._structured_state()
	_meta = metadata.duplicate(true)
	_meta["format"] = "json"
	_meta["original_file"] = path
	_meta["streaming"] = true
	_meta["stream_parser"] = "aurora_json_stream_v1"
	_meta["scope"] = str(_meta.get("scope", "core_knowledge"))
	_pending_parent = ""
	_pending_object = {}
	_pending_chars = 0
	_aggregated_records = 0

	var parsed := reader.parse_file(path, Callable(self, "_on_stream_value"))
	if bool(parsed.get("ok", false)):
		var flushed := _flush_pending()
		if not bool(flushed.get("ok", false)):
			parsed = flushed
	var state := _state
	var aggregated := _aggregated_records
	_reset_active()
	if not bool(parsed.get("ok", false)):
		return parsed
	var result := store._structured_result(path, "json", state, true)
	if not bool(result.get("ok", false)):
		return result
	result["stream_parser"] = "aurora_json_stream_v1"
	result["stream_values"] = int(parsed.get("records", 0))
	result["aggregated_records"] = aggregated
	result["max_depth"] = int(parsed.get("max_depth", 0))
	result["bytes_read"] = int(parsed.get("bytes_read", 0))
	result["memory_model"] = "bounded_by_64_fields_256k_record_and_16m_scalar"
	return result

func _on_stream_value(json_path: String, value: Variant) -> Dictionary:
	var segment := _split_last_segment(json_path)
	var object_field := bool(segment.get("object_field", false))
	if object_field and not (value is Dictionary) and not (value is Array):
		var parent := str(segment.get("parent", ""))
		var field := str(segment.get("field", ""))
		var cost := _value_cost(field, value)
		if not _pending_parent.is_empty() and _pending_parent != parent:
			var previous := _flush_pending()
			if not bool(previous.get("ok", false)):
				return previous
		if _pending_parent.is_empty():
			_pending_parent = parent
		if _pending_object.size() >= MAX_AGGREGATE_FIELDS or _pending_chars + cost > MAX_AGGREGATE_CHARS:
			var bounded := _flush_pending()
			if not bool(bounded.get("ok", false)):
				return bounded
			_pending_parent = parent
		_pending_object[field] = value
		_pending_chars += cost
		return {"ok": true, "buffered": true}

	var flushed := _flush_pending()
	if not bool(flushed.get("ok", false)):
		return flushed
	return _store._import_structured_value(_source, json_path, value, "json", _meta, _state)

func _flush_pending() -> Dictionary:
	if _pending_parent.is_empty() or _pending_object.is_empty():
		_pending_parent = ""
		_pending_object = {}
		_pending_chars = 0
		return {"ok": true, "empty": true}
	var parent := _pending_parent
	var value := _pending_object.duplicate(true)
	_pending_parent = ""
	_pending_object = {}
	_pending_chars = 0
	var imported := _store._import_structured_value(_source, parent, value, "json", _meta, _state)
	if bool(imported.get("ok", false)):
		_aggregated_records += 1
	return imported

func _split_last_segment(path: String) -> Dictionary:
	if path.is_empty() or not path.ends_with("]"):
		return {"object_field": false}
	var in_string := false
	var escaped := false
	var last_open := -1
	for i in range(path.length()):
		var c := path.substr(i, 1)
		if in_string:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				in_string = false
			continue
		if c == "\"":
			in_string = true
		elif c == "[":
			last_open = i
	if last_open < 0 or last_open >= path.length() - 1:
		return {"object_field": false}
	var token := path.substr(last_open + 1, path.length() - last_open - 2)
	if not token.begins_with("\""):
		return {"object_field": false, "parent": path.substr(0, last_open)}
	var parsed = JSON.parse_string(token)
	if not parsed is String:
		return {"object_field": false}
	return {"object_field": true, "parent": path.substr(0, last_open), "field": str(parsed)}

func _value_cost(field: String, value: Variant) -> int:
	var rendered := JSON.stringify(value) if not value is String else str(value)
	return field.length() + rendered.length() + 8

func _reset_active() -> void:
	_store = null
	_source = ""
	_meta = {}
	_state = {}
	_pending_parent = ""
	_pending_object = {}
	_pending_chars = 0
	_aggregated_records = 0
