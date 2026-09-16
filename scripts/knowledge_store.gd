class_name KnowledgeStore
extends RefCounted

const DB_PATH := "user://knowledge/knowledge.jsonl"
const STRUCTURED_PATH := "user://knowledge/structured.jsonl"
const MAX_CHUNK_CHARS := 1800
const LARGE_TEXT_THRESHOLD_BYTES := 8 * 1024 * 1024
const STREAM_BATCH_CHARS := 128 * 1024
const SEARCH_BUFFER_LIMIT := 256
var document_importer := KnowledgeDocumentImporter.new()
var _source_presence_cache: Dictionary = {}
var _source_presence_cache_valid := false
var _source_presence_signature := ""

func import_text(text: String, source := "manual", metadata: Dictionary = {}) -> Dictionary:
	var clean := text.strip_edges()
	if clean.is_empty():
		return {"ok": false, "error": "Пустой материал"}
	_ensure_dir()
	var chunks := _chunk(clean)
	var routed := _empty_routes()
	var rows: Array = []
	var explicit_kind := str(metadata.get("kind", "")).strip_edges()
	for chunk in chunks:
		var kind := explicit_kind if not explicit_kind.is_empty() else _classify_record(source, chunk)
		routed[kind] = int(routed.get(kind, 0)) + 1
		var meta := metadata.duplicate(true)
		meta["kind"] = kind
		meta["scope"] = str(meta.get("scope", "core_knowledge"))
		rows.append(_knowledge_item(source, chunk, kind, meta))
	if not _append_many(DB_PATH, rows):
		return {"ok": false, "error": "Не удалось полностью записать базу знаний", "source": source, "written": 0, "expected": chunks.size()}
	return {"ok": true, "source": source, "chunks": chunks.size(), "kind": _dominant_kind(routed), "routed": routed, "path": DB_PATH}

func import_file(path: String, metadata: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Файл не найден", "path": path}
	var ext := path.get_extension().to_lower()
	if ext == "json":
		return import_json_file(path, metadata)
	if ext in ["jsonl", "ndjson"]:
		return import_json_lines_file(path, metadata)
	if ext in ["csv", "tsv"]:
		return import_delimited_file(path, "\t" if ext == "tsv" else ",", metadata)
	if ext in KnowledgeDocumentImporter.TEXT_EXTENSIONS and _file_size(path) >= LARGE_TEXT_THRESHOLD_BYTES:
		return import_large_text_file(path, metadata)
	var extracted := document_importer.extract(path)
	if not bool(extracted.get("ok", false)):
		return extracted
	remove_source(path)
	var meta := metadata.duplicate(true)
	meta["format"] = ext
	meta["original_file"] = path
	meta["kind_hint"] = extracted.get("kind_hint", "knowledge")
	meta["extractor"] = extracted.get("extractor", "knowledge_document_importer")
	meta["truncated"] = extracted.get("truncated", false)
	meta["scope"] = str(meta.get("scope", "core_knowledge"))
	return import_text(str(extracted.get("text", "")), path, meta)

func import_extracted_file(path: String, text: String, metadata: Dictionary = {}) -> Dictionary:
	if text.strip_edges().is_empty():
		return {"ok": false, "error": "Из документа не извлечён текст", "path": path}
	remove_source(path)
	var meta := metadata.duplicate(true)
	meta["format"] = path.get_extension().to_lower()
	meta["original_file"] = path
	meta["extracted"] = true
	meta["scope"] = str(meta.get("scope", "core_knowledge"))
	return import_text(text, path, meta)

func supported_import_extensions() -> PackedStringArray:
	return document_importer.supported_extensions()

func import_large_text_file(path: String, metadata: Dictionary = {}) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Не удалось открыть большой текстовый источник", "path": path}
	var removed := remove_source(path)
	if not bool(removed.get("ok", false)):
		file.close()
		return removed
	var meta := metadata.duplicate(true)
	meta["format"] = path.get_extension().to_lower()
	meta["original_file"] = path
	meta["streaming"] = true
	meta["source_size_bytes"] = _file_size(path)
	meta["scope"] = str(meta.get("scope", "core_knowledge"))
	var routed := _empty_routes()
	var written := 0
	var batch := ""
	while not file.eof_reached():
		var line := file.get_line()
		if batch.length() + line.length() + 1 > STREAM_BATCH_CHARS and not batch.is_empty():
			var imported := import_text(batch, path, meta)
			if not bool(imported.get("ok", false)):
				file.close()
				return imported
			written += int(imported.get("chunks", 0))
			_merge_routes(routed, imported.get("routed", {}))
			batch = ""
		batch += line + "\n"
	if not batch.strip_edges().is_empty():
		var imported := import_text(batch, path, meta)
		if not bool(imported.get("ok", false)):
			file.close()
			return imported
		written += int(imported.get("chunks", 0))
		_merge_routes(routed, imported.get("routed", {}))
	file.close()
	if written <= 0:
		return {"ok": false, "error": "Большой текстовый источник не содержит данных", "path": path}
	return {"ok": true, "source": path, "format": path.get_extension().to_lower(), "chunks": written, "kind": _dominant_kind(routed), "routed": routed, "streaming": true, "path": DB_PATH}

func import_json_file(path: String, metadata: Dictionary = {}, replace_existing := true) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Не удалось прочитать JSON", "path": path}
	var raw := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var parse_error := parser.parse(raw)
	if parse_error != OK:
		return {"ok": false, "error": "Некорректный JSON: %s" % parser.get_error_message(), "line": parser.get_error_line(), "path": path}
	var parsed = parser.data
	if replace_existing:
		var removed := remove_source(path)
		if not bool(removed.get("ok", false)):
			return removed
	var records: Array = []
	_flatten_json(parsed, "$", records)
	return _import_structured_records(path, records, "json", metadata)

func import_json_lines_file(path: String, metadata: Dictionary = {}) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Не удалось прочитать JSONL", "path": path}
	var removed := remove_source(path)
	if not bool(removed.get("ok", false)):
		file.close()
		return removed
	var state := _structured_state()
	var line_number := 0
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		line_number += 1
		if line.is_empty():
			continue
		var parser := JSON.new()
		if parser.parse(line) != OK:
			file.close()
			return {"ok": false, "error": "Некорректный JSONL в строке %d: %s" % [line_number, parser.get_error_message()], "path": path}
		var imported := _import_structured_value(path, "$[%d]" % (line_number - 1), parser.data, path.get_extension().to_lower(), metadata, state)
		if not bool(imported.get("ok", false)):
			file.close()
			return imported
	file.close()
	return _structured_result(path, path.get_extension().to_lower(), state, true)

func import_delimited_file(path: String, delimiter: String, metadata: Dictionary = {}) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Не удалось прочитать таблицу", "path": path}
	if file.eof_reached():
		file.close()
		return {"ok": false, "error": "Таблица пуста", "path": path}
	var headers := file.get_csv_line(delimiter)
	if headers.is_empty():
		file.close()
		return {"ok": false, "error": "В таблице нет заголовков", "path": path}
	var removed := remove_source(path)
	if not bool(removed.get("ok", false)):
		file.close()
		return removed
	var state := _structured_state()
	var row_index := 0
	while not file.eof_reached():
		var values := file.get_csv_line(delimiter)
		if values.size() == 1 and str(values[0]).is_empty() and file.eof_reached():
			continue
		var row := {}
		for i in range(maxi(headers.size(), values.size())):
			var key := str(headers[i]).strip_edges() if i < headers.size() else "column_%d" % (i + 1)
			if key.is_empty():
				key = "column_%d" % (i + 1)
			row[key] = str(values[i]) if i < values.size() else ""
		var imported := _import_structured_value(path, "$[%d]" % row_index, row, path.get_extension().to_lower(), metadata, state)
		if not bool(imported.get("ok", false)):
			file.close()
			return imported
		row_index += 1
	file.close()
	return _structured_result(path, path.get_extension().to_lower(), state, true)

func _import_structured_records(source: String, records: Array, format: String, metadata: Dictionary) -> Dictionary:
	var state := _structured_state()
	for row in records:
		if not row is Dictionary:
			continue
		var imported := _import_structured_value(source, str(row.get("json_path", "$")), row.get("value"), format, metadata, state)
		if not bool(imported.get("ok", false)):
			return imported
	return _structured_result(source, format, state, false)

func _structured_state() -> Dictionary:
	return {"routed": _empty_routes(), "seen": {}, "structured_written": 0, "normalized_chunks": 0}

func _import_structured_value(source: String, record_path: String, value: Variant, format: String, metadata: Dictionary, state: Dictionary) -> Dictionary:
	var text := _record_text(value)
	if text.strip_edges().is_empty():
		return {"ok": true, "skipped": true}
	var fingerprint := _id(source + record_path, text)
	var seen: Dictionary = state.get("seen", {})
	if seen.has(fingerprint):
		return {"ok": true, "duplicate": true}
	seen[fingerprint] = true
	state["seen"] = seen
	var kind := _classify_record(record_path, value)
	var routed: Dictionary = state.get("routed", _empty_routes())
	routed[kind] = int(routed.get(kind, 0)) + 1
	state["routed"] = routed
	var meta := metadata.duplicate(true)
	meta.merge({
		"kind": kind,
		"format": format,
		"json_path": record_path,
		"original_file": source,
		"scope": "core_knowledge"
	}, true)
	if not _append(STRUCTURED_PATH, {
		"id": fingerprint,
		"kind": kind,
		"source": source,
		"json_path": record_path,
		"value": value,
		"metadata": meta,
		"created_at": Time.get_datetime_string_from_system(true)
	}):
		return {"ok": false, "error": "Не удалось записать структурированную запись", "source": source, "json_path": record_path}
	state["structured_written"] = int(state.get("structured_written", 0)) + 1
	var normalized := import_text(text, source, meta)
	if not bool(normalized.get("ok", false)):
		return normalized
	state["normalized_chunks"] = int(state.get("normalized_chunks", 0)) + int(normalized.get("chunks", 0))
	return {"ok": true}

func _structured_result(source: String, format: String, state: Dictionary, streaming: bool) -> Dictionary:
	var seen: Dictionary = state.get("seen", {})
	if seen.is_empty():
		return {"ok": false, "error": "Источник не содержит структурированных записей", "source": source}
	var structured_written := int(state.get("structured_written", 0))
	if structured_written != seen.size():
		return {"ok": false, "error": "Не удалось полностью записать структурированную базу", "source": source, "written": structured_written, "expected": seen.size()}
	return {
		"ok": true,
		"source": source,
		"format": format,
		"records": seen.size(),
		"chunks": int(state.get("normalized_chunks", 0)),
		"routed": state.get("routed", _empty_routes()),
		"streaming": streaming,
		"note": "Имя файла не влияет на маршрутизацию; назначение определяется по структуре и содержимому."
	}

func remove_source(source: String) -> Dictionary:
	if source.is_empty():
		return {"ok": true, "source": source, "removed": 0, "structured_removed": 0, "streaming": true, "filter_skipped": true}
	if not _source_may_exist(source):
		return {"ok": true, "source": source, "removed": 0, "structured_removed": 0, "streaming": true, "filter_skipped": true}
	var db := _filter_source_jsonl(DB_PATH, source)
	if not bool(db.get("ok", false)):
		return db
	var structured := _filter_source_jsonl(STRUCTURED_PATH, source)
	if not bool(structured.get("ok", false)):
		return structured
	_forget_source(source)
	return {"ok": true, "source": source, "removed": db.get("removed", 0), "structured_removed": structured.get("removed", 0), "streaming": true, "filter_skipped": false}

func search(query: String, limit := 6) -> Array:
	var normalized_query := query.to_lower().strip_edges()
	if normalized_query.is_empty() or limit <= 0 or not FileAccess.file_exists(DB_PATH):
		return []
	var terms := normalized_query.split(" ", false)
	var file := FileAccess.open(DB_PATH, FileAccess.READ)
	if file == null:
		return []
	var scored: Array = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var item = JSON.parse_string(line)
		if not item is Dictionary:
			continue
		var text := str(item.get("text", "")).to_lower()
		var source := str(item.get("source", "")).to_lower()
		var kind := str(item.get("kind", "")).to_lower()
		var score := 0
		if text.contains(normalized_query):
			score += 5
		for term in terms:
			if term.length() < 2:
				continue
			if text.contains(term): score += 2
			if source.contains(term): score += 1
			if kind.contains(term): score += 1
		if score > 0:
			scored.append({"score": score, "item": item})
			if scored.size() >= SEARCH_BUFFER_LIMIT:
				_scored_trim(scored, maxi(limit * 4, 32))
	file.close()
	_scored_trim(scored, limit)
	var out: Array = []
	for row in scored:
		if row is Dictionary:
			out.append(row.get("item", {}))
	return out

func all_items() -> Array:
	return _read_jsonl(DB_PATH)

func context_for(query: String, limit := 6) -> String:
	var parts: Array[String] = []
	for item in search(query, limit):
		parts.append("Тип: %s\nИсточник: %s\n%s" % [
			str(item.get("kind", "knowledge")),
			str(item.get("source", "manual")),
			str(item.get("text", ""))
		])
	return "\n\n---\n\n".join(parts)

func _knowledge_item(source: String, text: String, kind: String, metadata: Dictionary) -> Dictionary:
	return {
		"id": _id(source, text),
		"kind": kind,
		"source": source,
		"text": text,
		"metadata": metadata,
		"created_at": Time.get_datetime_string_from_system(true)
	}

func _empty_routes() -> Dictionary:
	return {"algorithm": 0, "template": 0, "skill": 0, "fact": 0, "example": 0, "instruction": 0, "knowledge": 0}

func _merge_routes(target: Dictionary, value: Variant) -> void:
	if not value is Dictionary:
		return
	for key in value.keys():
		target[key] = int(target.get(key, 0)) + int(value.get(key, 0))

func _dominant_kind(routes: Dictionary) -> String:
	var best := "knowledge"
	var count := -1
	var non_zero := 0
	for key in routes.keys():
		var value := int(routes.get(key, 0))
		if value > 0:
			non_zero += 1
		if value > count:
			count = value
			best = str(key)
	return "mixed" if non_zero > 1 else best

func _classify_record(context: String, value: Variant) -> String:
	var probe := (context + " " + _record_text(value)).to_lower()
	if _has_any(probe, ["algorithm", "алгоритм", "procedure", "workflow", "steps", "шаги", "последовательность"]): return "algorithm"
	if _has_any(probe, ["template", "шаблон", "pattern", "формат ответа", "макет"]): return "template"
	if _has_any(probe, ["skill", "навык", "tool", "инструмент", "capability", "умение"]): return "skill"
	if _has_any(probe, ["example", "пример", "input", "output", "question", "answer", "вопрос", "ответ"]): return "example"
	if _has_any(probe, ["instruction", "инструкция", "rule", "правило", "policy", "регламент"]): return "instruction"
	if _has_any(probe, ["fact", "факт", "knowledge", "знание", "description", "описание", "справка"]): return "fact"
	return "knowledge"

func _flatten_json(value: Variant, path: String, out: Array) -> void:
	if value is Array:
		for i in range(value.size()):
			_flatten_json(value[i], "%s[%d]" % [path, i], out)
	elif value is Dictionary:
		if _is_leaf_object(value):
			out.append({"json_path": path, "value": value})
		else:
			for key in value.keys():
				_flatten_json(value[key], "%s.%s" % [path, str(key)], out)
	else:
		out.append({"json_path": path, "value": value})

func _is_leaf_object(value: Dictionary) -> bool:
	if value.is_empty():
		return true
	var scalar := 0
	for v in value.values():
		if not (v is Dictionary) and not (v is Array):
			scalar += 1
	var threshold := maxi(1, int(ceil(float(value.size()) / 2.0)))
	return scalar >= threshold

func _record_text(value: Variant) -> String:
	if value is Dictionary or value is Array:
		return JSON.stringify(value, "  ", false)
	return str(value)

func _has_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.contains(str(needle)):
			return true
	return false

func _chunk(text: String) -> Array[String]:
	var chunks: Array[String] = []
	var paragraphs := text.replace("\r\n", "\n").split("\n\n", false)
	var current := ""
	for paragraph in paragraphs:
		var p := str(paragraph).strip_edges()
		if p.is_empty():
			continue
		if current.length() + p.length() + 2 > MAX_CHUNK_CHARS and not current.is_empty():
			chunks.append(current)
			current = ""
		while p.length() > MAX_CHUNK_CHARS:
			chunks.append(p.substr(0, MAX_CHUNK_CHARS))
			p = p.substr(MAX_CHUNK_CHARS)
		current = p if current.is_empty() else current + "\n\n" + p
	if not current.is_empty():
		chunks.append(current)
	return chunks

func _append(path: String, value: Dictionary) -> bool:
	return _append_many(path, [value])

func _append_many(path: String, values: Array) -> bool:
	if values.is_empty():
		return true
	_ensure_dir()
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.seek_end()
	var sources: Dictionary = {}
	for value in values:
		if not value is Dictionary:
			continue
		file.store_line(JSON.stringify(value))
		if file.get_error() != OK:
			file.close()
			_source_presence_cache_valid = false
			return false
		var source := str(value.get("source", ""))
		if not source.is_empty():
			sources[source] = true
	file.close()
	_remember_sources(sources)
	return true

func _source_may_exist(source: String) -> bool:
	var signature := _data_signature()
	if not _source_presence_cache_valid or signature != _source_presence_signature:
		_rebuild_source_presence_cache()
	return bool(_source_presence_cache.get(source, false))

func _rebuild_source_presence_cache() -> void:
	_source_presence_cache.clear()
	_scan_source_presence(DB_PATH)
	_scan_source_presence(STRUCTURED_PATH)
	_source_presence_signature = _data_signature()
	_source_presence_cache_valid = true

func _scan_source_presence(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_source_presence_cache_valid = false
		return
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:
			var source := str(parsed.get("source", ""))
			if not source.is_empty():
				_source_presence_cache[source] = true
	file.close()

func _remember_sources(sources: Dictionary) -> void:
	if not _source_presence_cache_valid:
		return
	for source in sources.keys():
		_source_presence_cache[str(source)] = true
	_source_presence_signature = _data_signature()

func _forget_source(source: String) -> void:
	if _source_presence_cache_valid:
		_source_presence_cache.erase(source)
		_source_presence_signature = _data_signature()

func _data_signature() -> String:
	return "%s|%s" % [_file_signature(DB_PATH), _file_signature(STRUCTURED_PATH)]

func _file_signature(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "0:0"
	return "%d:%d" % [_file_size(path), int(FileAccess.get_modified_time(path))]

func _filter_source_jsonl(path: String, source: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "removed": 0}
	_ensure_dir()
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		return {"ok": false, "error": "Не удалось открыть индекс для замены источника", "path": path}
	var temp := path + ".filter.tmp"
	var output := FileAccess.open(temp, FileAccess.WRITE)
	if output == null:
		input.close()
		return {"ok": false, "error": "Не удалось создать временный индекс", "path": temp}
	var removed := 0
	while not input.eof_reached():
		var line := input.get_line()
		if line.strip_edges().is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary and str(parsed.get("source", "")) == source:
			removed += 1
			continue
		output.store_line(line)
	input.close()
	output.close()
	if not _replace_file(temp, path):
		_source_presence_cache_valid = false
		return {"ok": false, "error": "Не удалось завершить потоковую замену индекса", "path": path}
	return {"ok": true, "removed": removed}

func _read_jsonl(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var out: Array = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed)
	file.close()
	return out

func _write_jsonl(path: String, rows: Array) -> bool:
	_ensure_dir()
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	for row in rows:
		file.store_line(JSON.stringify(row))
	file.close()
	var replaced := _replace_file(temp, path)
	_source_presence_cache_valid = false
	return replaced

func _replace_file(temp: String, target: String) -> bool:
	var absolute := ProjectSettings.globalize_path(target)
	var temp_absolute := ProjectSettings.globalize_path(temp)
	if FileAccess.file_exists(target):
		var remove_error := DirAccess.remove_absolute(absolute)
		if remove_error != OK:
			DirAccess.remove_absolute(temp_absolute)
			return false
	return DirAccess.rename_absolute(temp_absolute, absolute) == OK

func _scored_trim(scored: Array, limit: int) -> void:
	scored.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("score", 0)) > int(b.get("score", 0)))
	if scored.size() > limit:
		scored.resize(limit)

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size

func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://knowledge"))

func _id(source: String, text: String) -> String:
	return "%s-%s" % [str(source.hash()).replace("-", "n"), str(text.hash()).replace("-", "n")]