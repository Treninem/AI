class_name KnowledgeImportTransaction
extends RefCounted

const DB_PATH := "user://knowledge/knowledge.jsonl"
const STRUCTURED_PATH := "user://knowledge/structured.jsonl"
const DB_BACKUP := "user://knowledge/.knowledge.jsonl.txn"
const STRUCTURED_BACKUP := "user://knowledge/.structured.jsonl.txn"

func import_file(store: KnowledgeStore, path: String, metadata: Dictionary = {}) -> Dictionary:
	var snapshot := _snapshot()
	if not bool(snapshot.get("ok", false)):
		return snapshot
	var result := store.import_file(path, metadata)
	return _finish(result, snapshot)

func import_extracted_file(store: KnowledgeStore, path: String, text: String, metadata: Dictionary = {}) -> Dictionary:
	var snapshot := _snapshot()
	if not bool(snapshot.get("ok", false)):
		return snapshot
	var result := store.import_extracted_file(path, text, metadata)
	return _finish(result, snapshot)

func _finish(result: Dictionary, snapshot: Dictionary) -> Dictionary:
	if bool(result.get("ok", false)):
		_cleanup_backups()
		result["transaction"] = "committed"
		return result
	var restored := _restore(snapshot)
	result["transaction"] = "rolled_back" if restored else "rollback_failed"
	if not restored:
		result["rollback_error"] = "Не удалось восстановить предыдущую базу знаний после ошибки импорта"
	return result

func _snapshot() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://knowledge"))
	_cleanup_backups()
	var db_exists := FileAccess.file_exists(DB_PATH)
	var structured_exists := FileAccess.file_exists(STRUCTURED_PATH)
	if db_exists:
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(DB_PATH), ProjectSettings.globalize_path(DB_BACKUP))
		if err != OK:
			_cleanup_backups()
			return {"ok": false, "error": "Не удалось создать резервную копию поискового индекса", "code": err}
	if structured_exists:
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(STRUCTURED_PATH), ProjectSettings.globalize_path(STRUCTURED_BACKUP))
		if err != OK:
			_cleanup_backups()
			return {"ok": false, "error": "Не удалось создать резервную копию структурированной базы", "code": err}
	return {"ok": true, "db_existed": db_exists, "structured_existed": structured_exists}

func _restore(snapshot: Dictionary) -> bool:
	var ok := true
	ok = _restore_one(DB_PATH, DB_BACKUP, bool(snapshot.get("db_existed", false))) and ok
	ok = _restore_one(STRUCTURED_PATH, STRUCTURED_BACKUP, bool(snapshot.get("structured_existed", false))) and ok
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
	for path in [DB_BACKUP, STRUCTURED_BACKUP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
