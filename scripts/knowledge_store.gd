class_name KnowledgeStore
extends RefCounted

const DB_PATH := "user://knowledge/knowledge.jsonl"
const STRUCTURED_PATH := "user://knowledge/structured.jsonl"
const MAX_CHUNK_CHARS := 1800
var document_importer := KnowledgeDocumentImporter.new()

func import_text(text: String, source := "manual", metadata: Dictionary = {}) -> Dictionary:
	var clean := text.strip_edges()
	if clean.is_empty(): return {"ok": false, "error": "Пустой материал"}
	_ensure_dir()
	var chunks := _chunk(clean)
	var kind := str(metadata.get("kind", _classify_record(source, clean)))
	var written := 0
	for chunk in chunks:
		var meta := metadata.duplicate(true)
		meta["kind"] = kind
		meta["scope"] = str(meta.get("scope", "core_knowledge"))
		if _append(DB_PATH, {"id": _id(source, chunk), "kind": kind, "source": source, "text": chunk, "metadata": meta, "created_at": Time.get_datetime_string_from_system(true)}): written += 1
	if written != chunks.size(): return {"ok": false, "error": "Не удалось полностью записать базу знаний", "source": source, "written": written, "expected": chunks.size()}
	return {"ok": true, "source": source, "chunks": written, "kind": kind, "path": DB_PATH}

func import_file(path: String, metadata: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": false, "error": "Файл не найден", "path": path}
	var extracted := document_importer.extract(path)
	if not bool(extracted.get("ok", false)): return extracted
	remove_source(path)
	if str(extracted.get("mode", "")) == "json": return import_json_file(path, metadata, false)
	var meta := metadata.duplicate(true)
	meta["format"] = path.get_extension().to_lower()
	meta["original_file"] = path
	meta["kind_hint"] = extracted.get("kind_hint", "knowledge")
	meta["scope"] = str(meta.get("scope", "core_knowledge"))
	return import_text(str(extracted.get("text", "")), path, meta)

func import_extracted_file(path: String, text: String, metadata: Dictionary = {}) -> Dictionary:
	if text.strip_edges().is_empty(): return {"ok": false, "error": "Из документа не извлечён текст", "path": path}
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
	if file == null: return {"ok": false, "error": "Не удалось прочитать JSON", "path": path}
	var raw := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(raw)
	if parsed == null: return {"ok": false, "error": "Некорректный JSON", "path": path}
	if replace_existing: remove_source(path)
	var records: Array = []
	_flatten_json(parsed, "$", records)
	var routed := {"algorithm": 0, "template": 0, "skill": 0, "fact": 0, "example": 0, "instruction": 0, "knowledge": 0}
	var seen := {}
	var structured_written := 0
	for row in records:
		var text := _record_text(row.get("value"))
		if text.strip_edges().is_empty(): continue
		var fingerprint := _id(path + str(row.get("json_path", "")), text)
		if seen.has(fingerprint): continue
		seen[fingerprint] = true
		var kind := _classify_record(str(row.get("json_path", "")), row.get("value"))
		routed[kind] = int(routed.get(kind, 0)) + 1
		var meta := metadata.duplicate(true)
		meta.merge({"kind": kind, "format": "json", "json_path": row.get("json_path", "$"), "original_file": path, "scope": "core_knowledge"}, true)
		if _append(STRUCTURED_PATH, {"id": fingerprint, "kind": kind, "source": path, "json_path": row.get("json_path", "$"), "value": row.get("value"), "metadata": meta, "created_at": Time.get_datetime_string_from_system(true)}): structured_written += 1
		var normalized := import_text(text, path, meta)
		if not bool(normalized.get("ok", false)): return normalized
	if structured_written != seen.size(): return {"ok": false, "error": "Не удалось полностью записать структурированную базу", "source": path, "written": structured_written, "expected": seen.size()}
	return {"ok": true, "source": path, "format": "json", "records": seen.size(), "routed": routed, "note": "Имя файла не влияет на импорт; назначение определяется по структуре и содержимому."}

func remove_source(source: String) -> Dictionary:
	var before := _read_jsonl(DB_PATH)
	var keep: Array = []
	for item in before:
		if str(item.get("source", "")) != source: keep.append(item)
	var structured_before := _read_jsonl(STRUCTURED_PATH)
	var structured_keep: Array = []
	for item in structured_before:
		if str(item.get("source", "")) != source: structured_keep.append(item)
	var ok := _write_jsonl(DB_PATH, keep) and _write_jsonl(STRUCTURED_PATH, structured_keep)
	return {"ok": ok, "source": source, "removed": before.size() - keep.size(), "structured_removed": structured_before.size() - structured_keep.size()}

func search(query: String, limit := 6) -> Array:
	var terms := query.to_lower().split(" ", false)
	var scored: Array = []
	for item in all_items():
		var hay := (str(item.get("text", "")) + " " + str(item.get("source", "")) + " " + str(item.get("kind", ""))).to_lower()
		var score := 0
		for term in terms:
			if term.length() >= 2 and hay.contains(term): score += 1
		if score > 0: scored.append({"score": score, "item": item})
	scored.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("score", 0)) > int(b.get("score", 0)))
	var out: Array = []
	var count := mini(maxi(limit, 0), scored.size())
	for i in range(count): out.append((scored[i] as Dictionary).get("item", {}))
	return out

func all_items() -> Array: return _read_jsonl(DB_PATH)

func context_for(query: String, limit := 6) -> String:
	var parts: Array[String] = []
	for item in search(query, limit):
		parts.append("Тип: %s\nИсточник: %s\n%s" % [str(item.get("kind", "knowledge")), str(item.get("source", "manual")), str(item.get("text", ""))])
	return "\n\n---\n\n".join(parts)

func _classify_record(context: String, value: Variant) -> String:
	var probe := (context + " " + _record_text(value)).to_lower()
	if _has_any(probe, ["algorithm", "алгоритм", "procedure", "workflow", "steps", "шаги"]): return "algorithm"
	if _has_any(probe, ["template", "шаблон", "pattern", "формат ответа"]): return "template"
	if _has_any(probe, ["skill", "навык", "tool", "инструмент", "capability"]): return "skill"
	if _has_any(probe, ["example", "пример", "input", "output", "question", "answer", "вопрос", "ответ"]): return "example"
	if _has_any(probe, ["instruction", "инструкция", "rule", "правило", "policy"]): return "instruction"
	if _has_any(probe, ["fact", "факт", "knowledge", "знание", "description", "описание"]): return "fact"
	return "knowledge"

func _flatten_json(value: Variant, path: String, out: Array) -> void:
	if value is Array:
		for i in range(value.size()): _flatten_json(value[i], "%s[%d]" % [path, i], out)
	elif value is Dictionary:
		if _is_leaf_object(value): out.append({"json_path": path, "value": value})
		else:
			for key in value.keys(): _flatten_json(value[key], "%s.%s" % [path, str(key)], out)
	else: out.append({"json_path": path, "value": value})

func _is_leaf_object(value: Dictionary) -> bool:
	if value.is_empty(): return true
	var scalar := 0
	for v in value.values():
		if not (v is Dictionary) and not (v is Array): scalar += 1
	var threshold := maxi(1, int(ceil(float(value.size()) / 2.0)))
	return scalar >= threshold

func _record_text(value: Variant) -> String:
	if value is Dictionary or value is Array: return JSON.stringify(value, "  ", false)
	return str(value)

func _has_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.contains(str(needle)): return true
	return false

func _chunk(text: String) -> Array[String]:
	var chunks: Array[String] = []
	var paragraphs := text.replace("\r\n", "\n").split("\n\n", false)
	var current := ""
	for paragraph in paragraphs:
		var p := str(paragraph).strip_edges()
		if p.is_empty(): continue
		if current.length() + p.length() + 2 > MAX_CHUNK_CHARS and not current.is_empty():
			chunks.append(current)
			current = ""
		while p.length() > MAX_CHUNK_CHARS:
			chunks.append(p.substr(0, MAX_CHUNK_CHARS))
			p = p.substr(MAX_CHUNK_CHARS)
		current = p if current.is_empty() else current + "\n\n" + p
	if not current.is_empty(): chunks.append(current)
	return chunks

func _append(path: String, value: Dictionary) -> bool:
	_ensure_dir()
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null: file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.seek_end()
	file.store_line(JSON.stringify(value))
	file.close()
	return true

func _read_jsonl(path: String) -> Array:
	if not FileAccess.file_exists(path): return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return []
	var out: Array = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty(): continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary: out.append(parsed)
	file.close()
	return out

func _write_jsonl(path: String, rows: Array) -> bool:
	_ensure_dir()
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return false
	for row in rows: file.store_line(JSON.stringify(row))
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
