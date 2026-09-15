class_name KnowledgeStore
extends RefCounted

const DB_PATH := "user://knowledge/knowledge.jsonl"
const STRUCTURED_PATH := "user://knowledge/structured.jsonl"
const MAX_CHUNK_CHARS := 1800
var document_importer := KnowledgeDocumentImporter.new()

func import_text(text: String, source := "manual", metadata: Dictionary = {}) -> Dictionary:
	var clean := text.strip_edges()
	if clean.is_empty():
		return {"ok": false, "error": "Пустой материал"}
	_ensure_dir()
	var chunks := _chunk(clean)
	var routed := _empty_routes()
	var written := 0
	var explicit_kind := str(metadata.get("kind", "")).strip_edges()
	for chunk in chunks:
		var kind := explicit_kind if not explicit_kind.is_empty() else _classify_record(source, chunk)
		routed[kind] = int(routed.get(kind, 0)) + 1
		var meta := metadata.duplicate(true)
		meta["kind"] = kind
		meta["scope"] = str(meta.get("scope", "core_knowledge"))
		if _append(DB_PATH, _knowledge_item(source, chunk, kind, meta)):
			written += 1
	if written != chunks.size():
		return {"ok": false, "error": "Не удалось полностью записать базу знаний", "source": source, "written": written, "expected": chunks.size()}
	return {"ok": true, "source": source, "chunks": written, "kind": _dominant_kind(routed), "routed": routed, "path": DB_PATH}

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
	var extracted := document_importer.extract(path)
	if not bool(extracted.get("ok", false)):
		return extracted
	remove_source(path)
	var meta := metadata.duplicate(true)
	meta["format"] = ext
	meta["original_file"] = path
	meta["kind_hint"] = extracted.get("kind_hint", "knowledge")
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
		remove_source(path)
	var records: Array = []
	_flatten_json(parsed, "$", records)
	return _import_structured_records(path, records, "json", metadata)

func import_json_lines_file(path: String, metadata: Dictionary = {}) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Не удалось прочитать JSONL", "path": path}
	var records: Array = []
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
		records.append({"json_path": "$[%d]" % (line_number - 1), "value": parser.data})
	file.close()
	if records.is_empty():
		return {"ok": false, "error": "JSONL не содержит записей", "path": path}
	remove_source(path)
	return _import_structured_records(path, records, path.get_extension().to_lower(), metadata)

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
	var records: Array = []
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
		records.append({"json_path": "$[%d]" % row_index, "value": row})
		row_index += 1
	file.close()
	if records.is_empty():
		return {"ok": false, "error": "Таблица не содержит строк данных", "path": path}
	remove_source(path)
	return _import_structured_records(path, records, path.get_extension().to_lower(), metadata)

func _import_structured_records(source: String, records: Array, format: String, metadata: Dictionary) -> Dictionary:
	var routed := _empty_routes()
	var seen := {}
	var structured_written := 0
	var normalized_chunks := 0
	for row in records:
		if not row is Dictionary:
			continue
		var value = row.get("value")
		var text := _record_text(value)
		if text.strip_edges().is_empty():
			continue
		var record_path := str(row.get("json_path", "$"))
		var fingerprint := _id(source + record_path, text)
		if seen.has(fingerprint):
			continue
		seen[fingerprint] = true
		var kind := _classify_record(record_path, value)
		routed[kind] = int(routed.get(kind, 0)) + 1
		var meta := metadata.duplicate(true)
		meta.merge({
			"kind": kind,
			"format": format,
			"json_path": record_path,
			"original_file": source,
			"scope": "core_knowledge"
		}, true)
		if _append(STRUCTURED_PATH, {
			"id": fingerprint,
			"kind": kind,
			"source": source,
			"json_path": record_path,
			"value": value,
			"metadata": meta,
			"created_at": Time.get_datetime_string_from_system(true)
		}):
			structured_written += 1
		var normalized := import_text(text, source, meta)
		if not bool(normalized.get("ok", false)):
			return normalized
		normalized_chunks += int(normalized.get("chunks", 0))
	if structured_written != seen.size():
		return {"ok": false, "error": "Не удалось полностью записать структурированную базу", "source": source, "written": structured_written, "expected": seen.size()}
	return {
		"ok": true,
		"source": source,
		"format": format,
		"records": seen.size(),
		"chunks": normalized_chunks,
		"routed": routed,
		"note": "Имя файла не влияет на маршрутизацию; назначение определяется по структуре и содержимому."
	}

func remove_source(source: String) -> Dictionary:
	var before := _read_jsonl(DB_PATH)
	var keep: Array = []
	for item in before:
		if str(item.get("source", "")) != source:
			keep.append(item)
	var structured_before := _read_jsonl(STRUCTURED_PATH)
	var structured_keep: Array = []
	for item in structured_before:
		if str(item.get("source", "")) != source:
			structured_keep.append(item)
	var db_ok := _write_jsonl(DB_PATH, keep)
	var structured_ok := _write_jsonl(STRUCTURED_PATH, structured_keep)
	return {
		"ok": db_ok and structured_ok,
		"source": source,
		"removed": before.size() - keep.size(),
		"structured_removed": structured_before.size() - structured_keep.size()
	}

func search(query: String, limit := 6) -> Array:
	var normalized_query := query.to_lower().strip_edges()
	var terms := normalized_query.split(" ", false)
	var scored: Array = []
	for item in all_items():
		var text := str(item.get("text", "")).to_lower()
		var source := str(item.get("source", "")).to_lower()
		var kind := str(item.get("kind", "")).to_lower()
		var score := 0
		if not normalized_query.is_empty() and text.contains(normalized_query):
			score += 5
		for term in terms:
			if term.length() < 2:
				continue
			if text.contains(term):
				score += 2
			if source.contains(term):
				score += 1
			if kind.contains(term):
				score += 1
		if score > 0:
			scored.append({"score": score, "item": item})
	scored.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("score", 0)) > int(b.get("score", 0)))
	var out: Array = []
	var count := mini(maxi(limit, 0), scored.size())
	for i in range(count):
		out.append((scored[i] as Dictionary).get("item", {}))
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
	_ensure_dir()
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.seek_end()
	file.store_line(JSON.stringify(value))
	file.close()
	return true

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
	var absolute := ProjectSettings.globalize_path(path)
	var temp_absolute := ProjectSettings.globalize_path(temp)
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(absolute)
		if remove_error != OK:
			DirAccess.remove_absolute(temp_absolute)
			return false
	var rename_error := DirAccess.rename_absolute(temp_absolute, absolute)
	return rename_error == OK

func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://knowledge"))

func _id(source: String, text: String) -> String:
	return "%s-%s" % [str(source.hash()).replace("-", "n"), str(text.hash()).replace("-", "n")]
