class_name KnowledgeSourceRegistry
extends RefCounted

const REGISTRY_PATH := "user://knowledge/sources.json"
const REGISTRY_VERSION := 1
const HASH_CHUNK_BYTES := 1024 * 1024

# Each registry instance keeps a deep-copied read cache. The static generation
# invalidates sibling instances after any successful in-process write while
# size/mtime catches ordinary external/process changes. This avoids reparsing
# the whole registry for inspect -> mark -> stats sequences without changing the
# on-disk schema or allowing callers to mutate cached state before an atomic save.
static var _registry_write_generation := 0
var _cached_rows: Array = []
var _cache_size := -1
var _cache_mtime := -1
var _cache_generation := -1
var _cache_valid := false

static func invalidate_runtime_cache() -> void:
	_registry_write_generation += 1

func inspect_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Файл не найден", "path": path}
	var fingerprint := _sha256_file(path)
	if fingerprint.is_empty():
		return {"ok": false, "error": "Не удалось вычислить SHA-256 источника", "path": path}
	var rows := _load_rows()
	var by_path := _find_path(rows, path)
	var by_hash := _find_hash(rows, fingerprint)
	var size := _file_size(path)
	var ext := path.get_extension().to_lower()
	var existing_revision := int(by_path.get("revision", 0)) if not by_path.is_empty() else 0
	var same_path_same_hash := not by_path.is_empty() and str(by_path.get("fingerprint_sha256", "")) == fingerprint
	var duplicate_of := str(by_hash.get("source", "")) if not by_hash.is_empty() else ""
	var existing_role := ""
	if not by_path.is_empty():
		existing_role = "canonical" if str(by_path.get("source", "")) == path else "alias"
	return {
		"ok": true,
		"path": path,
		"fingerprint_sha256": fingerprint,
		"size_bytes": size,
		"format": ext,
		"same_path_same_hash": same_path_same_hash,
		"duplicate": not by_hash.is_empty(),
		"duplicate_of": duplicate_of,
		"existing_source": by_path,
		"existing_role": existing_role,
		"matching_source": by_hash,
		"revision": maxi(1, existing_revision + (0 if same_path_same_hash else 1)),
		"source_id": _source_id(fingerprint)
	}

func register_duplicate(path: String, inspection: Dictionary) -> Dictionary:
	var fingerprint := str(inspection.get("fingerprint_sha256", ""))
	if fingerprint.is_empty():
		return {"ok": false, "error": "Нет fingerprint для регистрации дубля"}
	var rows := _load_rows()
	var index := _find_hash_index(rows, fingerprint)
	if index < 0:
		return {"ok": false, "error": "Исходный источник для дубля не найден"}
	var row: Dictionary = rows[index]
	var aliases: Array = row.get("aliases", []) if row.get("aliases", []) is Array else []
	if str(row.get("source", "")) != path and path not in aliases:
		aliases.append(path)
	row["aliases"] = aliases
	row["last_seen_at"] = Time.get_datetime_string_from_system(true)
	rows[index] = row
	if not _save_rows(rows):
		return {"ok": false, "error": "Не удалось сохранить alias источника"}
	return {
		"ok": true,
		"duplicate": true,
		"skipped": true,
		"source": row.get("source", path),
		"alias": path,
		"source_id": row.get("source_id", _source_id(fingerprint)),
		"fingerprint_sha256": fingerprint,
		"revision": row.get("revision", 1)
	}

func mark_imported(path: String, inspection: Dictionary, result: Dictionary, metadata: Dictionary = {}) -> Dictionary:
	var fingerprint := str(inspection.get("fingerprint_sha256", ""))
	if fingerprint.is_empty():
		return {"ok": false, "error": "Нет fingerprint импортированного источника"}
	var rows := _load_rows()
	var existing_index := _find_path_index(rows, path)
	var matching_index := _find_hash_index(rows, fingerprint)
	var now := Time.get_datetime_string_from_system(true)
	var row := {
		"source_id": str(inspection.get("source_id", _source_id(fingerprint))),
		"source": path,
		"aliases": [],
		"fingerprint_sha256": fingerprint,
		"format": str(inspection.get("format", path.get_extension().to_lower())),
		"size_bytes": int(inspection.get("size_bytes", _file_size(path))),
		"revision": int(inspection.get("revision", 1)),
		"chunks": int(result.get("chunks", 0)),
		"structured_records": int(result.get("records", result.get("structured_records", 0))),
		"kinds": result.get("routed", {}),
		"parser": str(metadata.get("imported_by", "knowledge_store")),
		"parser_version": str(metadata.get("parser_version", "1")),
		"status": "ready",
		"imported_at": now,
		"updated_at": now,
		"last_seen_at": now
	}
	if existing_index >= 0:
		var old: Dictionary = rows[existing_index]
		var old_hash := str(old.get("fingerprint_sha256", ""))
		var old_canonical := str(old.get("source", ""))
		if old_hash == fingerprint:
			# Reindexing unchanged canonical bytes keeps history and aliases.
			row["source"] = old_canonical
			row["source_id"] = str(old.get("source_id", row["source_id"]))
			row["aliases"] = old.get("aliases", []) if old.get("aliases", []) is Array else []
			row["imported_at"] = str(old.get("imported_at", now))
			rows[existing_index] = row
		elif old_canonical == path:
			# Canonical file changed. Existing aliases were fingerprints of the old
			# bytes and must not silently follow this new revision.
			row["aliases"] = []
			row["imported_at"] = str(old.get("imported_at", now))
			rows[existing_index] = row
		else:
			# An alias/copy changed independently. Detach only that alias from the
			# old canonical source and create a new source for its new bytes.
			var aliases: Array = old.get("aliases", []) if old.get("aliases", []) is Array else []
			aliases.erase(path)
			old["aliases"] = aliases
			old["last_seen_at"] = now
			rows[existing_index] = old
			matching_index = _find_hash_index(rows, fingerprint)
			if matching_index >= 0:
				var canonical: Dictionary = rows[matching_index]
				var canonical_aliases: Array = canonical.get("aliases", []) if canonical.get("aliases", []) is Array else []
				if path != str(canonical.get("source", "")) and path not in canonical_aliases:
					canonical_aliases.append(path)
				canonical["aliases"] = canonical_aliases
				canonical["last_seen_at"] = now
				rows[matching_index] = canonical
				row = canonical
			else:
				rows.append(row)
	elif matching_index >= 0:
		# A byte-identical source should normally have been skipped before import.
		# If it reaches here, preserve one canonical row and register this path as an alias.
		var canonical: Dictionary = rows[matching_index]
		var aliases: Array = canonical.get("aliases", []) if canonical.get("aliases", []) is Array else []
		if path != str(canonical.get("source", "")) and path not in aliases:
			aliases.append(path)
		canonical["aliases"] = aliases
		canonical["last_seen_at"] = now
		rows[matching_index] = canonical
		row = canonical
	else:
		rows.append(row)
	if not _save_rows(rows):
		return {"ok": false, "error": "Не удалось сохранить реестр источников"}
	return {"ok": true, "record": row}

func remove_source(source: String) -> Dictionary:
	var rows := _load_rows()
	var removed := 0
	var aliases_removed := 0
	var out: Array = []
	for value in rows:
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		var canonical := str(row.get("source", ""))
		var aliases: Array = row.get("aliases", []) if row.get("aliases", []) is Array else []
		if canonical == source:
			removed += 1
			continue
		if source in aliases:
			aliases.erase(source)
			row["aliases"] = aliases
			row["last_seen_at"] = Time.get_datetime_string_from_system(true)
			aliases_removed += 1
		out.append(row)
	var ok := _save_rows(out)
	return {
		"ok": ok,
		"source": source,
		"removed": removed,
		"aliases_removed": aliases_removed,
		"canonical_preserved": aliases_removed > 0 and removed == 0
	}

func sources() -> Array:
	return _load_rows().duplicate(true)

func record_for_source(source: String) -> Dictionary:
	var rows := _load_rows()
	return _find_path(rows, source)

func canonical_source(source: String) -> String:
	var row := record_for_source(source)
	return str(row.get("source", source)) if not row.is_empty() else source

func storage_is_valid() -> bool:
	if not FileAccess.file_exists(REGISTRY_PATH):
		_cache_valid = false
		return false
	_load_rows()
	return _cache_valid

func stats() -> Dictionary:
	var rows := _load_rows()
	var aliases := 0
	var revisions := 0
	for value in rows:
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		var row_aliases = row.get("aliases", [])
		if row_aliases is Array:
			aliases += row_aliases.size()
		revisions += maxi(1, int(row.get("revision", 1)))
	return {
		"sources": rows.size(),
		"aliases": aliases,
		"revisions_total": revisions,
		"bytes": _file_size(REGISTRY_PATH),
		"path": REGISTRY_PATH
	}

func _find_path(rows: Array, path: String) -> Dictionary:
	var index := _find_path_index(rows, path)
	return rows[index] if index >= 0 and rows[index] is Dictionary else {}

func _find_path_index(rows: Array, path: String) -> int:
	for i in range(rows.size()):
		if not rows[i] is Dictionary:
			continue
		var row: Dictionary = rows[i]
		if str(row.get("source", "")) == path:
			return i
		var aliases = row.get("aliases", [])
		if aliases is Array and path in aliases:
			return i
	return -1

func _find_hash(rows: Array, fingerprint: String) -> Dictionary:
	var index := _find_hash_index(rows, fingerprint)
	return rows[index] if index >= 0 and rows[index] is Dictionary else {}

func _find_hash_index(rows: Array, fingerprint: String) -> int:
	for i in range(rows.size()):
		if rows[i] is Dictionary and str(rows[i].get("fingerprint_sha256", "")) == fingerprint:
			return i
	return -1

func _source_id(fingerprint: String) -> String:
	return "src_" + fingerprint.substr(0, mini(24, fingerprint.length()))

func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return ""
	while file.get_position() < file.get_length():
		var remaining := file.get_length() - file.get_position()
		if ctx.update(file.get_buffer(mini(HASH_CHUNK_BYTES, remaining))) != OK:
			file.close()
			return ""
	file.close()
	return ctx.finish().hex_encode().to_lower()

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size

func _load_rows() -> Array:
	if not FileAccess.file_exists(REGISTRY_PATH):
		_cache_valid = false
		return []
	var size := _file_size(REGISTRY_PATH)
	var mtime := int(FileAccess.get_modified_time(REGISTRY_PATH))
	if _cache_valid and _cache_generation == _registry_write_generation and size == _cache_size and mtime == _cache_mtime:
		return _cached_rows.duplicate(true)
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if file == null:
		_cache_valid = false
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_cache_valid = false
		return []
	if int(parsed.get("schema_version", 0)) != REGISTRY_VERSION:
		_cache_valid = false
		return []
	var rows = parsed.get("sources", [])
	if not rows is Array:
		_cache_valid = false
		return []
	_remember_cache(rows, size, mtime)
	return _cached_rows.duplicate(true)

func _remember_cache(rows: Array, size: int, mtime: int) -> void:
	_cached_rows = rows.duplicate(true)
	_cache_size = size
	_cache_mtime = mtime
	_cache_generation = _registry_write_generation
	_cache_valid = true

func _save_rows(rows: Array) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REGISTRY_PATH.get_base_dir()))
	var temp := REGISTRY_PATH + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"schema_version": REGISTRY_VERSION,
		"updated_at": Time.get_datetime_string_from_system(true),
		"sources": rows
	}, "  "))
	file.close()
	var target_abs := ProjectSettings.globalize_path(REGISTRY_PATH)
	var temp_abs := ProjectSettings.globalize_path(temp)
	if FileAccess.file_exists(REGISTRY_PATH):
		var remove_error := DirAccess.remove_absolute(target_abs)
		if remove_error != OK:
			DirAccess.remove_absolute(temp_abs)
			_cache_valid = false
			return false
	var renamed := DirAccess.rename_absolute(temp_abs, target_abs) == OK
	if not renamed:
		_cache_valid = false
		return false
	_registry_write_generation += 1
	_remember_cache(rows, _file_size(REGISTRY_PATH), int(FileAccess.get_modified_time(REGISTRY_PATH)))
	return true
