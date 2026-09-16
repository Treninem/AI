class_name KnowledgeImportTransaction
extends RefCounted

const DB_PATH := "user://knowledge/knowledge.jsonl"
const STRUCTURED_PATH := "user://knowledge/structured.jsonl"
const REGISTRY_PATH := KnowledgeSourceRegistry.REGISTRY_PATH
const DB_BACKUP := "user://knowledge/.knowledge_source.txn.jsonl"
const STRUCTURED_BACKUP := "user://knowledge/.structured_source.txn.jsonl"
const REGISTRY_BACKUP := "user://knowledge/.sources.json.txn"

# Transaction journals use fixed user:// paths. Multiple imports in one process
# therefore cannot safely mutate them concurrently. Serialize the full
# prepare/snapshot/import/register/cleanup lifecycle instead of allowing backup
# files and registry writes to race. Callers may still launch imports from
# different threads; they are explicitly queued here.
static var _transaction_mutex: Mutex = Mutex.new()

# Registry presence is normally enough to decide whether an old source needs a
# rollback journal, but pre-registry/direct KnowledgeStore data can exist without
# sources.json. Build a streaming source-presence index once per stable pair of
# JSONL files, then maintain it after transaction mutations. This preserves
# upgrade safety without returning to one full-store scan for every new source.
static var _source_presence_cache: Dictionary = {}
static var _source_presence_signature := ""
static var _source_presence_cache_valid := false

var registry := KnowledgeSourceRegistry.new()
var large_json_importer := LargeJsonKnowledgeImporter.new()

func import_file(store: KnowledgeStore, path: String, metadata: Dictionary = {}) -> Dictionary:
	_transaction_mutex.lock()
	var result := _import_file_locked(store, path, metadata)
	_transaction_mutex.unlock()
	result["transaction_serialized"] = true
	return result

func _import_file_locked(store: KnowledgeStore, path: String, metadata: Dictionary = {}) -> Dictionary:
	var prepared := _prepare_file(path, metadata)
	if not bool(prepared.get("ok", false)) or bool(prepared.get("skipped", false)):
		return prepared
	var inspection: Dictionary = prepared.get("inspection", {})
	var existing: Dictionary = inspection.get("existing_source", {}) if inspection.get("existing_source", {}) is Dictionary else {}
	var preserve_existing_source := not existing.is_empty() or _source_has_persisted_rows(path)
	var snapshot := _snapshot(path, preserve_existing_source)
	if not bool(snapshot.get("ok", false)):
		return snapshot
	var meta: Dictionary = prepared.get("metadata", metadata)
	var result: Dictionary
	if large_json_importer.should_stream(path):
		result = large_json_importer.import_file(store, path, meta)
	else:
		result = store.import_file(path, meta)
	return _finish_import(path, result, inspection, meta, snapshot)

func import_extracted_file(store: KnowledgeStore, path: String, text: String, metadata: Dictionary = {}) -> Dictionary:
	_transaction_mutex.lock()
	var result := _import_extracted_file_locked(store, path, text, metadata)
	_transaction_mutex.unlock()
	result["transaction_serialized"] = true
	return result

func _import_extracted_file_locked(store: KnowledgeStore, path: String, text: String, metadata: Dictionary = {}) -> Dictionary:
	var prepared := _prepare_file(path, metadata)
	if not bool(prepared.get("ok", false)) or bool(prepared.get("skipped", false)):
		return prepared
	var inspection: Dictionary = prepared.get("inspection", {})
	var existing: Dictionary = inspection.get("existing_source", {}) if inspection.get("existing_source", {}) is Dictionary else {}
	var preserve_existing_source := not existing.is_empty() or _source_has_persisted_rows(path)
	var snapshot := _snapshot(path, preserve_existing_source)
	if not bool(snapshot.get("ok", false)):
		return snapshot
	var meta: Dictionary = prepared.get("metadata", metadata)
	var result := store.import_extracted_file(path, text, meta)
	return _finish_import(path, result, inspection, meta, snapshot)

func _prepare_file(path: String, metadata: Dictionary) -> Dictionary:
	var inspection := registry.inspect_file(path)
	if not bool(inspection.get("ok", false)):
		return inspection
	var existing: Dictionary = inspection.get("existing_source", {})
	var matching: Dictionary = inspection.get("matching_source", {})
	var same_path_same_hash := bool(inspection.get("same_path_same_hash", false))
	var force_reindex := bool(metadata.get("force_reindex", false))
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
		_remember_source_presence(path, int(result.get("chunks", 0)) > 0 or int(result.get("records", result.get("structured_records", 0))) > 0)
		result["transaction"] = "committed"
		result["transaction_mode"] = "source_scoped_journal"
		result["source_snapshot"] = snapshot.get("data_journal", "source_rows")
		result["source_registry"] = registered.get("record", {})
		result["source_id"] = inspection.get("source_id", "")
		result["fingerprint_sha256"] = inspection.get("fingerprint_sha256", "")
		result["revision"] = inspection.get("revision", 1)
		return result
	return _rollback_result(result, snapshot)

func _rollback_result(result: Dictionary, snapshot: Dictionary) -> Dictionary:
	var restored := _restore(snapshot)
	var had_rows := int(snapshot.get("db_rows", 0)) > 0 or int(snapshot.get("structured_rows", 0)) > 0
	_remember_source_presence(str(snapshot.get("source", "")), had_rows if restored else false)
	result["transaction"] = "rolled_back" if restored else "rollback_failed"
	result["transaction_mode"] = "source_scoped_journal"
	result["source_snapshot"] = snapshot.get("data_journal", "source_rows")
	if not restored:
		result["rollback_error"] = "Не удалось полностью восстановить предыдущую базу знаний после ошибки импорта"
	return result

func _snapshot(source: String, preserve_existing_source: bool = true) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://knowledge"))
	_cleanup_backups()
	var db := {"ok": true, "rows": 0}
	var structured := {"ok": true, "rows": 0}
	var data_journal := "filter_partial_on_failure"
	if preserve_existing_source:
		data_journal = "source_rows"
		db = _journal_source(DB_PATH, DB_BACKUP, source)
		if not bool(db.get("ok", false)):
			_cleanup_backups()
			return db
		structured = _journal_source(STRUCTURED_PATH, STRUCTURED_BACKUP, source)
		if not bool(structured.get("ok", false)):
			_cleanup_backups()
			return structured
	var registry_existed := FileAccess.file_exists(REGISTRY_PATH)
	if registry_existed:
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(REGISTRY_PATH), ProjectSettings.globalize_path(REGISTRY_BACKUP))
		if err != OK:
			_cleanup_backups()
			return {"ok": false, "error": "Не удалось создать резервную копию реестра источников", "code": err}
	return {
		"ok": true,
		"source": source,
		"db_rows": int(db.get("rows", 0)),
		"structured_rows": int(structured.get("rows", 0)),
		"registry_existed": registry_existed,
		"preserve_existing_source": preserve_existing_source,
		"data_journal": data_journal,
		"mode": "source_scoped_journal"
	}

func _journal_source(path: String, backup: String, source: String) -> Dictionary:
	var output := FileAccess.open(backup, FileAccess.WRITE)
	if output == null:
		return {"ok": false, "error": "Не удалось создать журнал отката", "path": backup}
	if not FileAccess.file_exists(path):
		output.close()
		return {"ok": true, "rows": 0}
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		output.close()
		return {"ok": false, "error": "Не удалось прочитать индекс для журнала отката", "path": path}
	var rows := 0
	while not input.eof_reached():
		var line := input.get_line()
		if line.strip_edges().is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary and str(parsed.get("source", "")) == source:
			output.store_line(line)
			rows += 1
	input.close()
	output.close()
	return {"ok": true, "rows": rows}

func _restore(snapshot: Dictionary) -> bool:
	var source := str(snapshot.get("source", ""))
	if source.is_empty():
		return false
	var ok := true
	ok = _restore_source_file(DB_PATH, DB_BACKUP, source) and ok
	ok = _restore_source_file(STRUCTURED_PATH, STRUCTURED_BACKUP, source) and ok
	ok = _restore_registry(bool(snapshot.get("registry_existed", false))) and ok
	_cleanup_backups()
	return ok

func _restore_source_file(path: String, backup: String, source: String) -> bool:
	if not _filter_source(path, source):
		return false
	if not FileAccess.file_exists(backup):
		return true
	var saved := FileAccess.open(backup, FileAccess.READ)
	if saved == null:
		return false
	var target := FileAccess.open(path, FileAccess.READ_WRITE)
	if target == null:
		target = FileAccess.open(path, FileAccess.WRITE)
	if target == null:
		saved.close()
		return false
	target.seek_end()
	while not saved.eof_reached():
		var line := saved.get_line()
		if not line.strip_edges().is_empty():
			target.store_line(line)
	saved.close()
	target.close()
	return true

func _filter_source(path: String, source: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		return false
	var temp := path + ".rollback.tmp"
	var output := FileAccess.open(temp, FileAccess.WRITE)
	if output == null:
		input.close()
		return false
	while not input.eof_reached():
		var line := input.get_line()
		if line.strip_edges().is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary and str(parsed.get("source", "")) == source:
			continue
		output.store_line(line)
	input.close()
	output.close()
	var target_abs := ProjectSettings.globalize_path(path)
	var temp_abs := ProjectSettings.globalize_path(temp)
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(target_abs) != OK:
		DirAccess.remove_absolute(temp_abs)
		return false
	return DirAccess.rename_absolute(temp_abs, target_abs) == OK

func _restore_registry(existed: bool) -> bool:
	var target_abs := ProjectSettings.globalize_path(REGISTRY_PATH)
	var backup_abs := ProjectSettings.globalize_path(REGISTRY_BACKUP)
	if FileAccess.file_exists(REGISTRY_PATH):
		if DirAccess.remove_absolute(target_abs) != OK:
			return false
	if not existed:
		KnowledgeSourceRegistry.invalidate_runtime_cache()
		return true
	if not FileAccess.file_exists(REGISTRY_BACKUP):
		return false
	var restored := DirAccess.rename_absolute(backup_abs, target_abs) == OK
	if restored:
		KnowledgeSourceRegistry.invalidate_runtime_cache()
	return restored

func _source_has_persisted_rows(source: String) -> bool:
	if source.is_empty():
		return false
	var signature := _data_signature()
	if not _source_presence_cache_valid or signature != _source_presence_signature:
		_rebuild_source_presence_cache()
	# A failed presence scan must never be interpreted as proof that a source is
	# absent. Fail safe by preserving/journaling it; the journal read can then
	# return an explicit error instead of risking deletion of unknown old rows.
	if not _source_presence_cache_valid:
		return true
	return bool(_source_presence_cache.get(source, false))

func _rebuild_source_presence_cache() -> void:
	_source_presence_cache.clear()
	var db_ok := _scan_source_presence(DB_PATH)
	var structured_ok := _scan_source_presence(STRUCTURED_PATH)
	_source_presence_signature = _data_signature()
	_source_presence_cache_valid = db_ok and structured_ok

func _scan_source_presence(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	while not file.eof_reached():
		var line := file.get_line()
		if line.strip_edges().is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if not parsed is Dictionary:
			continue
		var source := str(parsed.get("source", ""))
		if not source.is_empty():
			_source_presence_cache[source] = true
	file.close()
	return true

func _remember_source_presence(source: String, present: bool) -> void:
	if source.is_empty() or not _source_presence_cache_valid:
		return
	if present:
		_source_presence_cache[source] = true
	else:
		_source_presence_cache.erase(source)
	_source_presence_signature = _data_signature()

func _data_signature() -> String:
	return "%s|%s" % [_file_signature(DB_PATH), _file_signature(STRUCTURED_PATH)]

func _file_signature(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "0:0"
	return "%d:%d" % [_file_size(path), int(FileAccess.get_modified_time(path))]

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size

func _cleanup_backups() -> void:
	for path in [DB_BACKUP, STRUCTURED_BACKUP, REGISTRY_BACKUP, DB_PATH + ".rollback.tmp", STRUCTURED_PATH + ".rollback.tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))