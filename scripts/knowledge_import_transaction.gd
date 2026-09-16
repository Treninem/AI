class_name KnowledgeImportTransaction
extends RefCounted

const DB_PATH := "user://knowledge/knowledge.jsonl"
const STRUCTURED_PATH := "user://knowledge/structured.jsonl"
const REGISTRY_PATH := KnowledgeSourceRegistry.REGISTRY_PATH
const DB_BACKUP := "user://knowledge/.knowledge_source.txn.jsonl"
const STRUCTURED_BACKUP := "user://knowledge/.structured_source.txn.jsonl"
const REGISTRY_BACKUP := "user://knowledge/.sources.json.txn"
const TXN_MANIFEST := "user://knowledge/.knowledge_import.txn.json"
const TXN_MANIFEST_TMP := TXN_MANIFEST + ".tmp"
const TXN_SNAPSHOT_MARKER := "user://knowledge/.knowledge_import.snapshotting.json"
const TXN_SNAPSHOT_MARKER_TMP := TXN_SNAPSHOT_MARKER + ".tmp"
const TXN_COMMIT_MARKER := "user://knowledge/.knowledge_import.committed.json"
const TXN_COMMIT_MARKER_TMP := TXN_COMMIT_MARKER + ".tmp"

# Transaction journals use fixed user:// paths. Multiple imports in one process
# therefore cannot safely mutate them concurrently. Serialize the full lifecycle.
static var _transaction_mutex: Mutex = Mutex.new()

# Registry presence is normally enough to decide whether an old source needs a
# rollback journal, but pre-registry/direct KnowledgeStore data can exist without
# sources.json. Cache source presence across stable JSONL files to avoid one scan
# per new source while remaining fail-safe on unreadable storage.
static var _source_presence_cache: Dictionary = {}
static var _source_presence_signature := ""
static var _source_presence_cache_valid := false

var registry := KnowledgeSourceRegistry.new()
var large_json_importer := LargeJsonKnowledgeImporter.new()

func import_file(store: KnowledgeStore, path: String, metadata: Dictionary = {}) -> Dictionary:
	_transaction_mutex.lock()
	var recovery := _recover_interrupted_transaction_locked()
	var result: Dictionary
	if not bool(recovery.get("ok", false)):
		result = {
			"ok": false,
			"error": "Не удалось безопасно восстановить прерванный импорт знаний",
			"transaction": "recovery_failed",
			"startup_recovery": recovery
		}
	else:
		result = _import_file_locked(store, path, metadata)
		if _recovery_changed_state(recovery):
			result["startup_recovery"] = recovery
	_transaction_mutex.unlock()
	result["transaction_serialized"] = true
	return result

func import_extracted_file(store: KnowledgeStore, path: String, text: String, metadata: Dictionary = {}) -> Dictionary:
	_transaction_mutex.lock()
	var recovery := _recover_interrupted_transaction_locked()
	var result: Dictionary
	if not bool(recovery.get("ok", false)):
		result = {
			"ok": false,
			"error": "Не удалось безопасно восстановить прерванный импорт знаний",
			"transaction": "recovery_failed",
			"startup_recovery": recovery
		}
	else:
		result = _import_extracted_file_locked(store, path, text, metadata)
		if _recovery_changed_state(recovery):
			result["startup_recovery"] = recovery
	_transaction_mutex.unlock()
	result["transaction_serialized"] = true
	return result

func recover_interrupted_transaction() -> Dictionary:
	_transaction_mutex.lock()
	var result := _recover_interrupted_transaction_locked()
	_transaction_mutex.unlock()
	return result

func _recovery_changed_state(recovery: Dictionary) -> bool:
	return (
		bool(recovery.get("recovered", false))
		or bool(recovery.get("cleaned_committed", false))
		or bool(recovery.get("cleaned_incomplete_snapshot", false))
		or bool(recovery.get("cleaned_abandoned_snapshot", false))
	)

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
		# The registry write is the final logical data mutation. A distinct durable
		# commit marker prevents restart from rolling back data if cleanup is killed.
		if not _write_new_json_marker(TXN_COMMIT_MARKER, TXN_COMMIT_MARKER_TMP, {
			"phase": "committed",
			"source": path,
			"fingerprint_sha256": inspection.get("fingerprint_sha256", ""),
			"revision": inspection.get("revision", 1),
			"updated_at": Time.get_datetime_string_from_system(true)
		}):
			var marker_failed := result.duplicate(true)
			marker_failed["ok"] = false
			marker_failed["error"] = "Не удалось записать durable commit-marker импорта знаний"
			return _rollback_result(marker_failed, snapshot)
		_cleanup_backups(true)
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
	_cleanup_backups(true)
	var registry_existed := FileAccess.file_exists(REGISTRY_PATH)
	var snapshot := {
		"ok": true,
		"source": source,
		"db_rows": 0,
		"structured_rows": 0,
		"registry_existed": registry_existed,
		"preserve_existing_source": preserve_existing_source,
		"data_journal": "source_rows" if preserve_existing_source else "filter_partial_on_failure",
		"mode": "source_scoped_journal"
	}
	# This marker distinguishes a crash while journals are still being built from
	# a legacy pre-manifest transaction. Storage is not mutated in this phase.
	if not _write_new_json_marker(TXN_SNAPSHOT_MARKER, TXN_SNAPSHOT_MARKER_TMP, {
		"phase": "snapshotting",
		"source": source,
		"updated_at": Time.get_datetime_string_from_system(true)
	}):
		return {"ok": false, "error": "Не удалось открыть snapshot-marker импорта знаний"}

	if preserve_existing_source:
		var db := _journal_source(DB_PATH, DB_BACKUP, source)
		if not bool(db.get("ok", false)):
			_cleanup_backups(true)
			return db
		var structured := _journal_source(STRUCTURED_PATH, STRUCTURED_BACKUP, source)
		if not bool(structured.get("ok", false)):
			_cleanup_backups(true)
			return structured
		snapshot["db_rows"] = int(db.get("rows", 0))
		snapshot["structured_rows"] = int(structured.get("rows", 0))

	if registry_existed:
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(REGISTRY_PATH), ProjectSettings.globalize_path(REGISTRY_BACKUP))
		if err != OK:
			_cleanup_backups(true)
			return {"ok": false, "error": "Не удалось создать резервную копию реестра источников", "code": err}

	if not _write_new_json_marker(TXN_MANIFEST, TXN_MANIFEST_TMP, _manifest_payload(snapshot, "prepared")):
		_cleanup_backups(true)
		return {"ok": false, "error": "Не удалось записать manifest транзакции импорта знаний"}
	_remove_if_exists(TXN_SNAPSHOT_MARKER)
	_remove_if_exists(TXN_SNAPSHOT_MARKER_TMP)
	return snapshot

func _manifest_payload(snapshot: Dictionary, phase: String) -> Dictionary:
	var payload := snapshot.duplicate(true)
	payload.erase("ok")
	payload["phase"] = phase
	payload["updated_at"] = Time.get_datetime_string_from_system(true)
	return payload

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

func _recover_interrupted_transaction_locked() -> Dictionary:
	# Commit marker has highest precedence: the data+registry mutation completed
	# and only cleanup may have been interrupted. Never roll back this state.
	if FileAccess.file_exists(TXN_COMMIT_MARKER):
		var commit_marker := _read_json_file(TXN_COMMIT_MARKER)
		if not bool(commit_marker.get("ok", false)):
			return commit_marker
		_cleanup_backups(true)
		KnowledgeSourceRegistry.invalidate_runtime_cache()
		_source_presence_cache_valid = false
		return {
			"ok": true,
			"recovered": false,
			"cleaned_committed": true,
			"source": str(commit_marker.get("source", "")),
			"phase": "committed"
		}

	if FileAccess.file_exists(TXN_MANIFEST):
		var manifest := _read_json_file(TXN_MANIFEST)
		if not bool(manifest.get("ok", false)):
			return manifest
		var source := str(manifest.get("source", ""))
		if source.is_empty():
			return {"ok": false, "recovered": false, "error": "Transaction manifest does not identify a source"}
		var phase := str(manifest.get("phase", "prepared"))
		# Backward compatibility with the first manifest implementation.
		if phase == "committed":
			_cleanup_backups(true)
			KnowledgeSourceRegistry.invalidate_runtime_cache()
			_source_presence_cache_valid = false
			return {"ok": true, "recovered": false, "cleaned_committed": true, "source": source, "phase": phase}
		if phase != "prepared":
			return {"ok": false, "recovered": false, "error": "Unknown transaction manifest phase", "phase": phase, "source": source}
		var restored := _restore(manifest)
		if not restored:
			return {"ok": false, "recovered": false, "error": "Interrupted knowledge transaction rollback failed", "source": source, "phase": phase}
		var had_rows := int(manifest.get("db_rows", 0)) > 0 or int(manifest.get("structured_rows", 0)) > 0
		_source_presence_cache_valid = false
		if had_rows:
			_rebuild_source_presence_cache()
		return {"ok": true, "recovered": true, "source": source, "phase": phase, "restored_previous_rows": had_rows}

	if FileAccess.file_exists(TXN_SNAPSHOT_MARKER):
		var marker := _read_json_file(TXN_SNAPSHOT_MARKER)
		if not bool(marker.get("ok", false)):
			return marker
		var source := str(marker.get("source", ""))
		# No production storage mutation happens before the prepared manifest exists.
		_cleanup_backups(true)
		return {"ok": true, "recovered": false, "cleaned_incomplete_snapshot": true, "source": source, "phase": "snapshotting"}

	return _recover_legacy_journals_without_manifest()

func _recover_legacy_journals_without_manifest() -> Dictionary:
	var has_db_backup := FileAccess.file_exists(DB_BACKUP)
	var has_structured_backup := FileAccess.file_exists(STRUCTURED_BACKUP)
	var has_registry_backup := FileAccess.file_exists(REGISTRY_BACKUP)
	if not has_db_backup and not has_structured_backup and not has_registry_backup:
		return {"ok": true, "recovered": false}
	if not has_db_backup and not has_structured_backup:
		_cleanup_backups(true)
		return {"ok": true, "recovered": false, "cleaned_abandoned_snapshot": true}
	var source := _infer_source_from_backup(DB_BACKUP)
	if source.is_empty():
		source = _infer_source_from_backup(STRUCTURED_BACKUP)
	if source.is_empty():
		return {
			"ok": false,
			"recovered": false,
			"legacy_journals": true,
			"error": "Legacy transaction journals exist without a manifest and source cannot be inferred; refusing destructive cleanup"
		}
	var snapshot := {
		"source": source,
		"db_rows": _count_nonempty_lines(DB_BACKUP),
		"structured_rows": _count_nonempty_lines(STRUCTURED_BACKUP),
		"registry_existed": has_registry_backup,
		"preserve_existing_source": true,
		"data_journal": "source_rows",
		"mode": "source_scoped_journal"
	}
	var restored := _restore(snapshot)
	_source_presence_cache_valid = false
	return {
		"ok": restored,
		"recovered": restored,
		"legacy_journals": true,
		"source": source,
		"error": "" if restored else "Legacy transaction journal rollback failed"
	}

func _read_json_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "recovered": false, "error": "Cannot read knowledge transaction marker", "path": path}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"ok": false, "recovered": false, "error": "Knowledge transaction marker is malformed", "path": path}
	var value: Dictionary = parsed
	value["ok"] = true
	return value

func _write_new_json_marker(path: String, temp: String, payload: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	_remove_if_exists(temp)
	if FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path)) == OK

func _infer_source_from_backup(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	while not file.eof_reached():
		var line := file.get_line()
		if line.strip_edges().is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:
			var source := str(parsed.get("source", ""))
			if not source.is_empty():
				file.close()
				return source
	file.close()
	return ""

func _count_nonempty_lines(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var count := 0
	while not file.eof_reached():
		if not file.get_line().strip_edges().is_empty():
			count += 1
	file.close()
	return count

func _restore(snapshot: Dictionary) -> bool:
	var source := str(snapshot.get("source", ""))
	if source.is_empty():
		return false
	if not _restore_source_file(DB_PATH, DB_BACKUP, source, int(snapshot.get("db_rows", 0))):
		return false
	if not _restore_source_file(STRUCTURED_PATH, STRUCTURED_BACKUP, source, int(snapshot.get("structured_rows", 0))):
		return false
	if not _restore_registry(bool(snapshot.get("registry_existed", false))):
		return false
	_cleanup_backups(true)
	return true

func _restore_source_file(path: String, backup: String, source: String, expected_rows: int) -> bool:
	# Repair either a previous recovery swap or KnowledgeStore's <path>.filter.tmp
	# replacement window before source-scoped rollback continues.
	if not _repair_recovery_swap(path):
		return false
	if not _repair_interrupted_filter_swap(path):
		return false
	var backup_exists := FileAccess.file_exists(backup)
	if expected_rows > 0 and not backup_exists:
		return false
	if backup_exists:
		var actual_rows := _count_nonempty_lines(backup)
		if actual_rows < 0 or actual_rows != expected_rows:
			return false
	if not _filter_source(path, source):
		return false
	if not backup_exists:
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

func _repair_recovery_swap(path: String) -> bool:
	var original := path + ".recovery.original"
	if not FileAccess.file_exists(original):
		return true
	var original_abs := ProjectSettings.globalize_path(original)
	var target_abs := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path):
		return DirAccess.rename_absolute(original_abs, target_abs) == OK
	return DirAccess.remove_absolute(original_abs) == OK

func _repair_interrupted_filter_swap(path: String) -> bool:
	var temp := path + ".filter.tmp"
	if FileAccess.file_exists(path):
		# A leftover filter temp is stale if the canonical target still exists.
		_remove_if_exists(temp)
		return true
	if not FileAccess.file_exists(temp):
		return true
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path)) == OK

func _filter_source(path: String, source: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		return false
	var temp := path + ".rollback.tmp"
	_remove_if_exists(temp)
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
	return _replace_file_recovery_safe(temp, path)

func _replace_file_recovery_safe(temp: String, target: String) -> bool:
	var original := target + ".recovery.original"
	var target_abs := ProjectSettings.globalize_path(target)
	var temp_abs := ProjectSettings.globalize_path(temp)
	var original_abs := ProjectSettings.globalize_path(original)

	# Finish/repair a prior interrupted swap before starting another one.
	if FileAccess.file_exists(original):
		if not FileAccess.file_exists(target):
			if DirAccess.rename_absolute(original_abs, target_abs) != OK:
				return false
		else:
			if DirAccess.remove_absolute(original_abs) != OK:
				return false

	if not FileAccess.file_exists(target):
		return DirAccess.rename_absolute(temp_abs, target_abs) == OK
	if DirAccess.rename_absolute(target_abs, original_abs) != OK:
		_remove_if_exists(temp)
		return false
	if DirAccess.rename_absolute(temp_abs, target_abs) != OK:
		DirAccess.rename_absolute(original_abs, target_abs)
		return false
	if FileAccess.file_exists(original):
		DirAccess.remove_absolute(original_abs)
	return true

func _restore_registry(existed: bool) -> bool:
	var target_abs := ProjectSettings.globalize_path(REGISTRY_PATH)
	if not existed:
		if FileAccess.file_exists(REGISTRY_PATH) and DirAccess.remove_absolute(target_abs) != OK:
			return false
		KnowledgeSourceRegistry.invalidate_runtime_cache()
		return true
	if not FileAccess.file_exists(REGISTRY_BACKUP):
		return false
	var temp := REGISTRY_PATH + ".rollback.tmp"
	_remove_if_exists(temp)
	var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(REGISTRY_BACKUP), ProjectSettings.globalize_path(temp))
	if copy_error != OK:
		return false
	if not _replace_file_recovery_safe(temp, REGISTRY_PATH):
		return false
	KnowledgeSourceRegistry.invalidate_runtime_cache()
	return true

func _source_has_persisted_rows(source: String) -> bool:
	if source.is_empty():
		return false
	var signature := _data_signature()
	if not _source_presence_cache_valid or signature != _source_presence_signature:
		_rebuild_source_presence_cache()
	# A failed presence scan must never be interpreted as proof that a source is
	# absent. Fail safe by preserving/journaling it.
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

func _remove_if_exists(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK

func _cleanup_backups(include_markers: bool = true) -> void:
	# When a durable commit marker exists it is deliberately removed last. If the
	# process dies during cleanup, restart still knows the new data is committed.
	var paths: Array = [
		DB_BACKUP,
		STRUCTURED_BACKUP,
		REGISTRY_BACKUP,
		DB_PATH + ".rollback.tmp",
		STRUCTURED_PATH + ".rollback.tmp",
		REGISTRY_PATH + ".rollback.tmp",
		DB_PATH + ".recovery.original",
		STRUCTURED_PATH + ".recovery.original",
		REGISTRY_PATH + ".recovery.original",
		TXN_MANIFEST_TMP,
		TXN_SNAPSHOT_MARKER_TMP,
		TXN_COMMIT_MARKER_TMP
	]
	if include_markers:
		paths.append(TXN_MANIFEST)
		paths.append(TXN_SNAPSHOT_MARKER)
		paths.append(TXN_COMMIT_MARKER)
	for value in paths:
		_remove_if_exists(str(value))