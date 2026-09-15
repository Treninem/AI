class_name KnowledgeStore
extends RefCounted

const DB_PATH := "user://knowledge/knowledge.jsonl"
const MAX_CHUNK_CHARS := 1800

func import_text(text: String, source := "manual", metadata: Dictionary = {}) -> Dictionary:
	var clean := text.strip_edges()
	if clean.is_empty():
		return {"ok": false, "error": "Пустой материал"}
	_ensure_dir()
	var chunks := _chunk(clean)
	var file := FileAccess.open(DB_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(DB_PATH, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Не удалось открыть базу знаний"}
	file.seek_end()
	var now := Time.get_datetime_string_from_system(true)
	for chunk in chunks:
		file.store_line(JSON.stringify({"id": _id(source, chunk), "source": source, "text": chunk, "metadata": metadata, "created_at": now}))
	file.close()
	return {"ok": true, "source": source, "chunks": chunks.size(), "path": DB_PATH}

func import_file(path: String, metadata: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Файл не найден", "path": path}
	var ext := path.get_extension().to_lower()
	if ext not in ["txt", "md", "json", "csv", "gd", "py", "js", "ts", "html", "css", "xml", "yaml", "yml", "log"]:
		return {"ok": false, "error": "Формат пока требует текстового извлечения", "extension": ext, "path": path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Не удалось прочитать файл", "path": path}
	var text := file.get_as_text()
	file.close()
	return import_text(text, path, metadata)

func search(query: String, limit := 6) -> Array:
	var terms := query.to_lower().split(" ", false)
	var scored: Array = []
	for item in all_items():
		var hay := (str(item.get("text", "")) + " " + str(item.get("source", ""))).to_lower()
		var score := 0
		for term in terms:
			if term.length() >= 2 and hay.contains(term): score += 1
		if score > 0:
			scored.append({"score": score, "item": item})
	scored.sort_custom(func(a, b): return int(a.score) > int(b.score))
	var out: Array = []
	for row in scored.slice(0, mini(limit, scored.size())):
		out.append(row.item)
	return out

func all_items() -> Array:
	if not FileAccess.file_exists(DB_PATH): return []
	var file := FileAccess.open(DB_PATH, FileAccess.READ)
	if file == null: return []
	var out: Array = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty(): continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary: out.append(parsed)
	file.close()
	return out

func context_for(query: String, limit := 6) -> String:
	var parts: Array[String] = []
	for item in search(query, limit):
		parts.append("Источник: %s\n%s" % [str(item.get("source", "manual")), str(item.get("text", ""))])
	return "\n\n---\n\n".join(parts)

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

func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://knowledge"))

func _id(source: String, text: String) -> String:
	return "%s-%s" % [str(source.hash()).replace("-", "n"), str(text.hash()).replace("-", "n")]
