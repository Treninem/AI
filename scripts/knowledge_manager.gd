class_name KnowledgeManager
extends RefCounted

const DB_PATH := "user://knowledge/knowledge.jsonl"
const STRUCTURED_PATH := "user://knowledge/structured.jsonl"
var registry := KnowledgeSourceRegistry.new()

func sources() -> Array:
	var map := {}
	for item in _read(DB_PATH):
		var source := str(item.get("source", "manual"))
		if not map.has(source): map[source] = {"source": source, "chunks": 0, "kinds": {}, "latest": ""}
		map[source]["chunks"] = int(map[source]["chunks"]) + 1
		var kind := str(item.get("kind", "knowledge"))
		map[source]["kinds"][kind] = int(map[source]["kinds"].get(kind, 0)) + 1
		var created := str(item.get("created_at", ""))
		if created > str(map[source]["latest"]): map[source]["latest"] = created
	var registry_rows := registry.sources()
	for value in registry_rows:
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		var source := str(row.get("source", ""))
		if source.is_empty():
			continue
		if not map.has(source):
			map[source] = {"source": source, "chunks": int(row.get("chunks", 0)), "kinds": row.get("kinds", {}), "latest": str(row.get("updated_at", ""))}
		var merged: Dictionary = map[source]
		for key in ["source_id", "aliases", "fingerprint_sha256", "format", "size_bytes", "revision", "parser", "parser_version", "status", "imported_at", "updated_at", "last_seen_at"]:
			if row.has(key): merged[key] = row[key]
		map[source] = merged
	var result: Array = map.values()
	result.sort_custom(func(a, b): return str(a.get("latest", a.get("updated_at", ""))) > str(b.get("latest", b.get("updated_at", ""))))
	return result

func stats() -> Dictionary:
	var items := _read(DB_PATH)
	var structured := _read(STRUCTURED_PATH)
	var kinds := {}
	for item in items:
		var kind := str(item.get("kind", "knowledge"))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	var registry_stats := registry.stats()
	return {
		"chunks": items.size(),
		"structured_records": structured.size(),
		"sources": sources().size(),
		"kinds": kinds,
		"bytes": _size(DB_PATH) + _size(STRUCTURED_PATH) + int(registry_stats.get("bytes", 0)),
		"source_aliases": int(registry_stats.get("aliases", 0)),
		"source_revisions_total": int(registry_stats.get("revisions_total", 0)),
		"registry": registry_stats
	}

func remove_source(source: String) -> Dictionary:
	var canonical := registry.canonical_source(source)
	var before := _read(DB_PATH)
	var keep: Array = []
	for item in before:
		if str(item.get("source", "")) != canonical and str(item.get("source", "")) != source: keep.append(item)
	var db_ok := _write(DB_PATH, keep)
	var structured_before := _read(STRUCTURED_PATH)
	var structured_keep: Array = []
	for item in structured_before:
		if str(item.get("source", "")) != canonical and str(item.get("source", "")) != source: structured_keep.append(item)
	var structured_ok := _write(STRUCTURED_PATH, structured_keep)
	var registry_result := registry.remove_source(source)
	return {
		"ok": db_ok and structured_ok and bool(registry_result.get("ok", false)),
		"source": source,
		"canonical_source": canonical,
		"removed": before.size() - keep.size(),
		"structured_removed": structured_before.size() - structured_keep.size(),
		"registry_removed": registry_result.get("removed", 0)
	}

func compact() -> Dictionary:
	var seen := {}
	var out: Array = []
	var removed := 0
	for item in _read(DB_PATH):
		var id := str(item.get("id", ""))
		if not id.is_empty() and seen.has(id):
			removed += 1
			continue
		if not id.is_empty(): seen[id] = true
		out.append(item)
	var ok := _write(DB_PATH, out)
	return {"ok": ok, "items": out.size(), "duplicates_removed": removed, "registry": registry.stats()}

func _read(path: String) -> Array:
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

func _write(path: String, rows: Array) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://knowledge"))
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return false
	for row in rows: file.store_line(JSON.stringify(row))
	file.close()
	var abs := ProjectSettings.globalize_path(path)
	var temp_abs := ProjectSettings.globalize_path(temp)
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(abs)
		if remove_error != OK:
			DirAccess.remove_absolute(temp_abs)
			return false
	return DirAccess.rename_absolute(temp_abs, abs) == OK

func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return 0
	var size := file.get_length()
	file.close()
	return size
