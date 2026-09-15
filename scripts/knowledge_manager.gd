class_name KnowledgeManager
extends RefCounted

const DB_PATH := "user://knowledge/knowledge.jsonl"
const STRUCTURED_PATH := "user://knowledge/structured.jsonl"

func sources() -> Array:
	var map := {}
	for item in _read(DB_PATH):
		var source := str(item.get("source", "manual"))
		if not map.has(source): map[source] = {"source": source, "chunks": 0, "kinds": {}, "latest": ""}
		map[source]["chunks"] = int(map[source]["chunks"]) + 1
		var kind := str(item.get("kind", "knowledge")); map[source]["kinds"][kind] = int(map[source]["kinds"].get(kind, 0)) + 1
		var created := str(item.get("created_at", "")); if created > str(map[source]["latest"]): map[source]["latest"] = created
	return map.values()

func stats() -> Dictionary:
	var items := _read(DB_PATH); var structured := _read(STRUCTURED_PATH); var kinds := {}
	for item in items:
		var kind := str(item.get("kind", "knowledge")); kinds[kind] = int(kinds.get(kind, 0)) + 1
	return {"chunks": items.size(), "structured_records": structured.size(), "sources": sources().size(), "kinds": kinds, "bytes": _size(DB_PATH) + _size(STRUCTURED_PATH)}

func remove_source(source: String) -> Dictionary:
	var before := _read(DB_PATH); var keep: Array = []
	for item in before:
		if str(item.get("source", "")) != source: keep.append(item)
	_write(DB_PATH, keep)
	var structured_keep: Array = []
	for item in _read(STRUCTURED_PATH):
		if str(item.get("source", "")) != source: structured_keep.append(item)
	_write(STRUCTURED_PATH, structured_keep)
	return {"ok": true, "source": source, "removed": before.size() - keep.size()}

func compact() -> Dictionary:
	var seen := {}; var out: Array = []; var removed := 0
	for item in _read(DB_PATH):
		var id := str(item.get("id", ""))
		if not id.is_empty() and seen.has(id): removed += 1; continue
		if not id.is_empty(): seen[id] = true
		out.append(item)
	_write(DB_PATH, out)
	return {"ok": true, "items": out.size(), "duplicates_removed": removed}

func _read(path: String) -> Array:
	if not FileAccess.file_exists(path): return []
	var file := FileAccess.open(path, FileAccess.READ); if file == null: return []
	var out: Array = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges(); if line.is_empty(): continue
		var parsed = JSON.parse_string(line); if parsed is Dictionary: out.append(parsed)
	file.close(); return out

func _write(path: String, rows: Array) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://knowledge"))
	var temp := path + ".tmp"; var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return
	for row in rows: file.store_line(JSON.stringify(row))
	file.close()
	var abs := ProjectSettings.globalize_path(path); var temp_abs := ProjectSettings.globalize_path(temp)
	if FileAccess.file_exists(path): DirAccess.remove_absolute(abs)
	DirAccess.rename_absolute(temp_abs, abs)

func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return 0
	var size := file.get_length(); file.close(); return size
