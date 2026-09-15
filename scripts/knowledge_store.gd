class_name KnowledgeStore
extends RefCounted

const DB_PATH := "user://knowledge/knowledge.jsonl"
const STRUCTURED_PATH := "user://knowledge/structured.jsonl"
const MAX_CHUNK_CHARS := 1800

func import_text(text: String, source := "manual", metadata: Dictionary = {}) -> Dictionary:
	var clean := text.strip_edges()
	if clean.is_empty(): return {"ok": false, "error": "Пустой материал"}
	_ensure_dir()
	var chunks := _chunk(clean)
	for chunk in chunks:
		_append(DB_PATH, {"id": _id(source, chunk), "kind": str(metadata.get("kind", "knowledge")), "source": source, "text": chunk, "metadata": metadata, "created_at": Time.get_datetime_string_from_system(true)})
	return {"ok": true, "source": source, "chunks": chunks.size(), "path": DB_PATH}

func import_file(path: String, metadata: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": false, "error": "Файл не найден", "path": path}
	var ext := path.get_extension().to_lower()
	if ext == "json": return import_json_file(path, metadata)
	if ext not in ["txt", "md", "csv", "gd", "py", "js", "ts", "html", "css", "xml", "yaml", "yml", "log"]:
		return {"ok": false, "error": "Формат пока требует текстового извлечения", "extension": ext, "path": path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "Не удалось прочитать файл", "path": path}
	var text := file.get_as_text(); file.close()
	return import_text(text, path, metadata)

# Accepts a JSON database with ANY filename and does not require a fixed schema.
# The importer inspects keys/content and routes records into semantic Core Knowledge
# categories while preserving the original structured record for future re-indexing.
func import_json_file(path: String, metadata: Dictionary = {}) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "Не удалось прочитать JSON", "path": path}
	var raw := file.get_as_text(); file.close()
	var parsed = JSON.parse_string(raw)
	if parsed == null: return {"ok": false, "error": "Некорректный JSON", "path": path}
	var records: Array = []
	_flatten_json(parsed, "$", records)
	var routed := {"algorithm": 0, "template": 0, "skill": 0, "fact": 0, "example": 0, "instruction": 0, "knowledge": 0}
	var seen := {}
	for row in records:
		var text := _record_text(row.get("value"))
		if text.strip_edges().is_empty(): continue
		var fingerprint := _id(path + str(row.get("json_path", "")), text)
		if seen.has(fingerprint): continue
		seen[fingerprint] = true
		var kind := _classify_record(str(row.get("json_path", "")), row.get("value"))
		routed[kind] = int(routed.get(kind, 0)) + 1
		var meta := metadata.duplicate(true)
		meta.merge({"kind": kind, "format": "json", "json_path": row.get("json_path", "$"), "original_file": path}, true)
		_append(STRUCTURED_PATH, {"id": fingerprint, "kind": kind, "source": path, "json_path": row.get("json_path", "$"), "value": row.get("value"), "metadata": meta, "created_at": Time.get_datetime_string_from_system(true)})
		import_text(text, path, meta)
	return {"ok": true, "source": path, "format": "json", "records": seen.size(), "routed": routed, "note": "Имя файла не влияет на импорт; назначение определяется по структуре и содержимому."}

func search(query: String, limit := 6) -> Array:
	var terms := query.to_lower().split(" ", false); var scored: Array = []
	for item in all_items():
		var hay := (str(item.get("text", "")) + " " + str(item.get("source", "")) + " " + str(item.get("kind", ""))).to_lower(); var score := 0
		for term in terms:
			if term.length() >= 2 and hay.contains(term): score += 1
		if score > 0: scored.append({"score": score, "item": item})
	scored.sort_custom(func(a, b): return int(a.score) > int(b.score))
	var out: Array = []
	for row in scored.slice(0, mini(limit, scored.size())): out.append(row.item)
	return out

func all_items() -> Array:
	return _read_jsonl(DB_PATH)

func context_for(query: String, limit := 6) -> String:
	var parts: Array[String] = []
	for item in search(query, limit): parts.append("Тип: %s\nИсточник: %s\n%s" % [str(item.get("kind", "knowledge")), str(item.get("source", "manual")), str(item.get("text", ""))])
	return "\n\n---\n\n".join(parts)

func _classify_record(json_path: String, value: Variant) -> String:
	var probe := (json_path + " " + _record_text(value)).to_lower()
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
		# Keep meaningful objects intact so question/answer, algorithm steps and templates stay associated.
		if _is_leaf_object(value): out.append({"json_path": path, "value": value})
		else:
			for key in value.keys(): _flatten_json(value[key], "%s.%s" % [path, str(key)], out)
	else: out.append({"json_path": path, "value": value})

func _is_leaf_object(value: Dictionary) -> bool:
	if value.is_empty(): return true
	var scalar := 0
	for v in value.values():
		if not (v is Dictionary) and not (v is Array): scalar += 1
	return scalar >= maxi(1, value.size() / 2)

func _record_text(value: Variant) -> String:
	if value is Dictionary or value is Array: return JSON.stringify(value, "  ", false)
	return str(value)

func _has_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.contains(str(needle)): return true
	return false

func _chunk(text: String) -> Array[String]:
	var chunks: Array[String] = []; var paragraphs := text.replace("\r\n", "\n").split("\n\n", false); var current := ""
	for paragraph in paragraphs:
		var p := str(paragraph).strip_edges()
		if p.is_empty(): continue
		if current.length() + p.length() + 2 > MAX_CHUNK_CHARS and not current.is_empty(): chunks.append(current); current = ""
		while p.length() > MAX_CHUNK_CHARS: chunks.append(p.substr(0, MAX_CHUNK_CHARS)); p = p.substr(MAX_CHUNK_CHARS)
		current = p if current.is_empty() else current + "\n\n" + p
	if not current.is_empty(): chunks.append(current)
	return chunks

func _append(path: String, value: Dictionary) -> void:
	_ensure_dir(); var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null: file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return
	file.seek_end(); file.store_line(JSON.stringify(value)); file.close()

func _read_jsonl(path: String) -> Array:
	if not FileAccess.file_exists(path): return []
	var file := FileAccess.open(path, FileAccess.READ); if file == null: return []
	var out: Array = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty(): continue
		var parsed = JSON.parse_string(line); if parsed is Dictionary: out.append(parsed)
	file.close(); return out

func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://knowledge"))

func _id(source: String, text: String) -> String:
	return "%s-%s" % [str(source.hash()).replace("-", "n"), str(text.hash()).replace("-", "n")]
