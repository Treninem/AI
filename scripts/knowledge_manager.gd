class_name KnowledgeManager
extends RefCounted

const DB_PATH := "user://knowledge/knowledge.jsonl"
const STRUCTURED_PATH := "user://knowledge/structured.jsonl"
var registry := KnowledgeSourceRegistry.new()
var _scan_cache: Dictionary = {}
var _scan_size := -1
var _scan_mtime := -1
var _recovery_status: Dictionary = {}

func _init() -> void:
	# KnowledgeStore streaming imports mutate source rows before the final registry
	# commit. Recover any manifest-backed interrupted transaction before manager
	# reads expose those files after an application restart.
	_recovery_status = KnowledgeImportTransaction.new().recover_interrupted_transaction()

func recovery_status() -> Dictionary:
	return _recovery_status.duplicate(true)

func sources() -> Array:
	var scan := _scan_db()
	var map: Dictionary = scan.get("sources", {}).duplicate(true)
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
	var scan := _scan_db()
	var registry_stats := registry.stats()
	return {
		"chunks": int(scan.get("chunks", 0)),
		"structured_records": _count_jsonl(STRUCTURED_PATH),
		"sources": int((scan.get("sources", {}) as Dictionary).size()),
		"kinds": scan.get("kinds", {}),
		"bytes": _size(DB_PATH) + _size(STRUCTURED_PATH) + int(registry_stats.get("bytes", 0)),
		"source_aliases": int(registry_stats.get("aliases", 0)),
		"source_revisions_total": int(registry_stats.get("revisions_total", 0)),
		"registry": registry_stats,
		"startup_recovery": _recovery_status.duplicate(true),
		"streaming_index": true
	}

func remove_source(source: String) -> Dictionary:
	var row := registry.record_for_source(source)
	var canonical := str(row.get("source", source)) if not row.is_empty() else source
	var aliases: Array = row.get("aliases", []) if not row.is_empty() and row.get("aliases", []) is Array else []
	var alias_only := not row.is_empty() and canonical != source and source in aliases
	if alias_only:
		# A byte-identical renamed source is an alias of one canonical set of
		# chunks. Removing only that alias must not delete shared canonical data.
		var alias_result := registry.remove_source(source)
		_invalidate_scan()
		return {
			"ok": bool(alias_result.get("ok", false)),
			"source": source,
			"canonical_source": canonical,
			"alias_only": true,
			"removed": 0,
			"structured_removed": 0,
			"registry_removed": alias_result.get("removed", 0),
			"aliases_removed": alias_result.get("aliases_removed", 0),
			"canonical_preserved": true
		}
	var store := KnowledgeStore.new()
	var removed := store.remove_source(canonical)
	if canonical != source and int(removed.get("removed", 0)) == 0 and int(removed.get("structured_removed", 0)) == 0:
		removed = store.remove_source(source)
	var registry_result := registry.remove_source(source)
	_invalidate_scan()
	return {
		"ok": bool(removed.get("ok", false)) and bool(registry_result.get("ok", false)),
		"source": source,
		"canonical_source": canonical,
		"alias_only": false,
		"removed": removed.get("removed", 0),
		"structured_removed": removed.get("structured_removed", 0),
		"registry_removed": registry_result.get("removed", 0),
		"aliases_removed": registry_result.get("aliases_removed", 0),
		"canonical_preserved": false
	}

func compact() -> Dictionary:
	if not FileAccess.file_exists(DB_PATH):
		return {"ok": true, "items": 0, "duplicates_removed": 0, "registry": registry.stats()}
	var input := FileAccess.open(DB_PATH, FileAccess.READ)
	if input == null:
		return {"ok": false, "error": "Не удалось открыть индекс знаний"}
	var temp := DB_PATH + ".compact.tmp"
	var output := FileAccess.open(temp, FileAccess.WRITE)
	if output == null:
		input.close()
		return {"ok": false, "error": "Не удалось создать временный compact-индекс"}
	var seen := {}
	var kept := 0
	var removed := 0
	while not input.eof_reached():
		var line := input.get_line()
		if line.strip_edges().is_empty():
			continue
		var item = JSON.parse_string(line)
		if not item is Dictionary:
			output.store_line(line)
			continue
		var id := str(item.get("id", ""))
		if not id.is_empty() and seen.has(id):
			removed += 1
			continue
		if not id.is_empty(): seen[id] = true
		output.store_line(line)
		kept += 1
	input.close()
	output.close()
	if not _replace_file(temp, DB_PATH):
		return {"ok": false, "error": "Не удалось заменить индекс после compact"}
	_invalidate_scan()
	return {"ok": true, "items": kept, "duplicates_removed": removed, "registry": registry.stats(), "streaming": true}

func _scan_db() -> Dictionary:
	var size := _size(DB_PATH)
	var mtime := int(FileAccess.get_modified_time(DB_PATH)) if FileAccess.file_exists(DB_PATH) else 0
	if size == _scan_size and mtime == _scan_mtime and not _scan_cache.is_empty():
		return _scan_cache.duplicate(true)
	var map := {}
	var kinds := {}
	var chunks := 0
	if FileAccess.file_exists(DB_PATH):
		var file := FileAccess.open(DB_PATH, FileAccess.READ)
		if file != null:
			while not file.eof_reached():
				var line := file.get_line().strip_edges()
				if line.is_empty(): continue
				var item = JSON.parse_string(line)
				if not item is Dictionary: continue
				chunks += 1
				var source := str(item.get("source", "manual"))
				if not map.has(source): map[source] = {"source": source, "chunks": 0, "kinds": {}, "latest": ""}
				map[source]["chunks"] = int(map[source]["chunks"]) + 1
				var kind := str(item.get("kind", "knowledge"))
				map[source]["kinds"][kind] = int(map[source]["kinds"].get(kind, 0)) + 1
				kinds[kind] = int(kinds.get(kind, 0)) + 1
				var created := str(item.get("created_at", ""))
				if created > str(map[source]["latest"]): map[source]["latest"] = created
			file.close()
	_scan_size = size
	_scan_mtime = mtime
	_scan_cache = {"chunks": chunks, "sources": map, "kinds": kinds}
	return _scan_cache.duplicate(true)

func _count_jsonl(path: String) -> int:
	if not FileAccess.file_exists(path): return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return 0
	var count := 0
	while not file.eof_reached():
		if not file.get_line().strip_edges().is_empty(): count += 1
	file.close()
	return count

func _replace_file(temp: String, target: String) -> bool:
	var abs := ProjectSettings.globalize_path(target)
	var temp_abs := ProjectSettings.globalize_path(temp)
	if FileAccess.file_exists(target):
		var remove_error := DirAccess.remove_absolute(abs)
		if remove_error != OK:
			DirAccess.remove_absolute(temp_abs)
			return false
	return DirAccess.rename_absolute(temp_abs, abs) == OK

func _invalidate_scan() -> void:
	_scan_cache = {}
	_scan_size = -1
	_scan_mtime = -1

func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return 0
	var size := file.get_length()
	file.close()
	return size