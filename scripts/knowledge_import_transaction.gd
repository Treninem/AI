class_name KnowledgeImportTransaction
extends RefCounted

const DB_PATH := "user://knowledge/knowledge.jsonl"
const STRUCTURED_PATH := "user://knowledge/structured.jsonl"
const REGISTRY_PATH := KnowledgeSourceRegistry.REGISTRY_PATH
const DB_BACKUP := "user://knowledge/.knowledge.jsonl.txn"
const STRUCTURED_BACKUP := "user://knowledge/.structured.jsonl.txn"
const REGISTRY_BACKUP := "user://knowledge/.sources.json.txn"

var registry := KnowledgeSourceRegistry.new()
var large_json_importer := LargeJsonKnowledgeImporter.new()

func import_file(store: KnowledgeStore, path: String, metadata: Dictionary = {}) -> Dictionary:
	var prepared := _prepare_file(path, metadata)
	if not bool(prepared.get("ok", false)) or bool(prepared.get("skipped", false)):
		return prepared
	var snapshot := _snapshot()
	if not bool(snapshot.get("ok", false)):
		return snapshot
	var meta: Dictionary = prepared.get("metadata", metadata)
	var result: Dictionary
	if large_json_importer.should_stream(path):
		result = large_json_importer.import_file(store, path, meta)
	else:
		result = store.import_file(path, meta)
	return _finish_import(path, result, prepared.get("inspection", {}), meta, snapshot)

func import_extracted_file(store: KnowledgeStore, path: String, text: String, metadata: Dictionary = {}) -> Dictionary:
	var prepared := _prepare_file(path, metadata)
	if not bool(prepared.get("ok", false)) or bool(prepared.get("skipped", false)):
		return prepared
	var snapshot := _snapshot()
	if not bool(snapshot.get("ok", false)):
		return snapshot
	var meta: Dictionary = prepared.get("metadata", metadata)
	var result := store.import_extracted_file(path, text, meta)
	return _finish_import(path, result, prepared.get("inspection", {}), meta, snapshot)

func _prepare_file(path: String, metadata: Dictionary) -> Dictionary:
	var inspection := registry.inspect_file(path)
	if not bool(inspection.get("ok", false)):
		return inspection
	var existing: Dictionary = inspection.get("existing_source", {})
	var matching: Dictionary = inspection.get("matching_source", {})
	var same_path_same_hash := bool(inspection.get("same_path_same_hash", false))
	var force_reindex := bool(metadata.get("force_reindex", false))
	# Identical bytes already indexed under this path, or a truly new alias/copy
	# of another source, do not create another set of chunks. An explicit reindex
	# bypasses this shortcut so parser/index upgrades can rebuild unchanged files.
	var safe_duplicate := not force_reindex and (same_path_same_hash or (existing.is_empty() and not matching.is_empty()))
	if safe_duplicate:
		var duplicate := registry.register_duplicate(path, inspection)
		duplicate["transaction"] = "skipped_duplicate"
		duplicate["format"] = inspection.get("format", path.get_extension().to_lower())
		return duplicate
	var meta := metadata.duplicate(true)
	meta["source_id"] = inspection.get("source_id", "")
	meta["source_fingerprint"] = inspection.get("fingerprint_sha256", "")
	meta["source_revision"] = inspection.get("revision", 1)
	meta["source_size_bytes"] = inspection.get("size_bytes", 0)
	meta["source_registry_version"] = KnowledgeSourceRegistry.REGISTRY_VERSION
	if large_json_importer.should_stream(path):
		meta["streaming_json"] = true
		meta["parser_version"] = "aurora_json_stream_v1"
	return {"ok": true, "inspection": inspection, "metadata": meta}

func _finish_import(path: String, result: Dictionary, inspection: Dictionary, metadata: Dictionary, snapshot: Dictionary) -> Dictionary:
	if bool(result.get("ok", false)):
		var registered := registry.mark_imported(path, inspection, result, metadata)
		if not bool(registered.get("ok", false)):
			var failed := result.duplicate(true)
			failed["ok"] = false
			failed["error"] = str(registered.get("error", "Не удалось записать реестр источников"))
			return _rollback_result(failed, snapshot)
		_cleanup_backups()
		result["transaction"] = "committed"
		result["source_registry"] = registered.get("record", {})
		result["source_id"] = inspection.get("source_id", "")
		result["fingerprint_sha256"] = inspection.get("fingerprint_sha256", "")
		result["revision"] = inspection.get("revision", 1)
		return result
	return _rollback_result(result, snapshot)

func _rollback_result(result: Dictionary, snapshot: Dictionary) -> Dictionary:
	var restored := _restore(snapshot)
	result["transaction"] = "rolled_back" if restored else "rollback_failed"
	if not restored:
		result["rollback_error"] = "Не удалось полностью восстановить предыдущую базу знаний после ошибки импорта"
	return result

func _snapshot() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://knowledge"))
	_cleanup_backups()
	var mapping := [
		{"path": DB_PATH, "backup": DB_BACKUP, "key": "db_existed", "label": "поискового индекса"},
		{"path": STRUCTURED_PATH, "backup": STRUCTURED_BACKUP, "key": "structured_existed", "label": "структурированной базы"},
		{"path": REGISTRY_PATH, "backup": REGISTRY_BACKUP, "key": "registry_existed", "label": "реестра источников"}
	]
	var result := {"ok": true}
	for row in mapping:
		var path := str(row["path"])
		var backup := str(row["backup"])
		var existed := FileAccess.file_exists(path)
		result[str(row["key"])] = existed
		if not existed:
			continue
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup))
		if err != OK:
			_cleanup_backups()
			return {"ok": false, "error": "Не удалось создать резервную копию %s" % str(row["label"]), "code": err}
	return result

func _restore(snapshot: Dictionary) -> bool:
	var ok := true
	ok = _restore_one(DB_PATH, DB_BACKUP, bool(snapshot.get("db_existed", false))) and ok
	ok = _restore_one(STRUCTURED_PATH, STRUCTURED_BACKUP, bool(snapshot.get("structured_existed", false))) and ok
	ok = _restore_one(REGISTRY_PATH, REGISTRY_BACKUP, bool(snapshot.get("registry_existed", false))) and ok
	_cleanup_backups()
	return ok

func _restore_one(path: String, backup: String, existed: bool) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var backup_absolute := ProjectSettings.globalize_path(backup)
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(absolute)
		if remove_error != OK:
			return false
	if not existed:
		return true
	if not FileAccess.file_exists(backup):
		return false
	return DirAccess.rename_absolute(backup_absolute, absolute) == OK

func _cleanup_backups() -> void:
	for path in [DB_BACKUP, STRUCTURED_BACKUP, REGISTRY_BACKUP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
