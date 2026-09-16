extends SceneTree

# Multi-process crash/restart probe. Python runs seed -> live reimport (killed after
# transaction snapshot and first storage mutation) -> verify in the same isolated
# user:// directory. Production scripts are called directly; no fake storage.
const KnowledgeStoreScript: Variant = preload("res://scripts/knowledge_store.gd")
const KnowledgeImportTransactionScript: Variant = preload("res://scripts/knowledge_import_transaction.gd")
const KnowledgeSourceRegistryScript: Variant = preload("res://scripts/knowledge_source_registry.gd")
const KnowledgeManagerScript: Variant = preload("res://scripts/knowledge_manager.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_INTERRUPT_RESULT="
const PROBE_ROOT := "user://knowledge_interrupt_probe"
const SOURCE := PROBE_ROOT + "/source.jsonl"
const STABLE_MARKER := "AURORA_INTERRUPT_STABLE_COMMITTED_MARKER"
const NEW_MARKER := "AURORA_INTERRUPT_UNCOMMITTED_NEW_MARKER"
const MB := 1024 * 1024

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	var phase: String = OS.get_environment("AURORA_INTERRUPT_PHASE").strip_edges()
	match phase:
		"seed": _seed()
		"import": _live_import()
		"verify": _verify_after_restart()
		_: _emit({"ok": false, "error": "unknown interruption phase", "phase": phase}, 2)

func _seed() -> void:
	_reset_state()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROBE_ROOT))
	var file: FileAccess = FileAccess.open(SOURCE, FileAccess.WRITE)
	if file == null:
		_emit({"ok": false, "error": "cannot create interruption seed"}, 2)
		return
	for i in range(256):
		file.store_line(JSON.stringify({
			"kind": "fact",
			"content": "%s stable_record_%d" % [STABLE_MARKER, i]
		}))
	file.close()
	var txn: Variant = KnowledgeImportTransactionScript.new()
	var imported: Variant = txn.call("import_file", KnowledgeStoreScript.new(), SOURCE, {"imported_by": "interrupt_probe_seed"})
	var found: Variant = KnowledgeStoreScript.new().call("search", STABLE_MARKER, 8)
	var registry: Variant = KnowledgeSourceRegistryScript.new().call("record_for_source", SOURCE)
	var ok: bool = imported is Dictionary and bool(imported.get("ok", false)) and not found.is_empty() and not registry.is_empty()
	_emit({
		"ok": ok,
		"phase": "seed",
		"source": SOURCE,
		"stable_marker": STABLE_MARKER,
		"new_marker": NEW_MARKER,
		"user_data_dir": OS.get_user_data_dir(),
		"db_abs": ProjectSettings.globalize_path(KnowledgeStoreScript.DB_PATH),
		"structured_abs": ProjectSettings.globalize_path(KnowledgeStoreScript.STRUCTURED_PATH),
		"db_backup_abs": ProjectSettings.globalize_path(KnowledgeImportTransactionScript.DB_BACKUP),
		"structured_backup_abs": ProjectSettings.globalize_path(KnowledgeImportTransactionScript.STRUCTURED_BACKUP),
		"registry_backup_abs": ProjectSettings.globalize_path(KnowledgeImportTransactionScript.REGISTRY_BACKUP),
		"registry_abs": ProjectSettings.globalize_path(KnowledgeSourceRegistryScript.REGISTRY_PATH),
		"db_size": _file_size(KnowledgeStoreScript.DB_PATH),
		"structured_size": _file_size(KnowledgeStoreScript.STRUCTURED_PATH),
		"fingerprint_sha256": str(registry.get("fingerprint_sha256", "")) if registry is Dictionary else ""
	}, 0 if ok else 3)

func _live_import() -> void:
	if not FileAccess.file_exists(SOURCE):
		_emit({"ok": false, "error": "seed source missing", "phase": "import"}, 2)
		return
	var target_mb: int = maxi(16, int(OS.get_environment("AURORA_INTERRUPT_TARGET_MB")))
	var generated: Dictionary = _write_large_replacement(target_mb * MB)
	if not bool(generated.get("ok", false)):
		_emit(generated, 2)
		return
	print("AURORA_KNOWLEDGE_INTERRUPT_IMPORT_STARTED=" + JSON.stringify({"target_mb": target_mb, "bytes": generated.get("bytes", 0)}))
	var txn: Variant = KnowledgeImportTransactionScript.new()
	var imported: Variant = txn.call("import_file", KnowledgeStoreScript.new(), SOURCE, {"imported_by": "interrupt_probe_live"})
	# Normally Python kills this process before this line. Reaching it is reported
	# as a failed injection so the gate never silently passes without a real kill.
	_emit({
		"ok": false,
		"phase": "import",
		"error": "live import completed before interruption",
		"import": imported,
		"dataset": generated
	}, 4)

func _verify_after_restart() -> void:
	# Production restart contract: creating KnowledgeManager must recover before
	# any manager scan can expose partial rows. Do not invoke recovery manually here.
	var manager: Variant = KnowledgeManagerScript.new()
	var recovery: Variant = manager.call("recovery_status") if manager.has_method("recovery_status") else {"ok": false, "recovered": false, "error": "manager recovery status missing"}
	var store: Variant = KnowledgeStoreScript.new()
	var stable: Variant = store.call("search", STABLE_MARKER, 8)
	var uncommitted: Variant = store.call("search", NEW_MARKER, 8)
	var registry: Variant = KnowledgeSourceRegistryScript.new().call("record_for_source", SOURCE)
	var journals_clean := _transaction_artifacts_clean()
	var ok: bool = recovery is Dictionary and bool(recovery.get("ok", false)) and bool(recovery.get("recovered", false))
	ok = ok and not stable.is_empty() and uncommitted.is_empty() and not registry.is_empty() and journals_clean
	_emit({
		"ok": ok,
		"phase": "verify",
		"recovery": recovery,
		"automatic_manager_recovery": true,
		"stable_committed_marker_present": not stable.is_empty(),
		"uncommitted_marker_absent": uncommitted.is_empty(),
		"registry_present": not registry.is_empty(),
		"journals_clean": journals_clean,
		"expected_contract": "process kill during reimport must restore last committed source on next process"
	}, 0 if ok else 5)

func _transaction_artifacts_clean() -> bool:
	for path in _transaction_artifact_paths():
		if FileAccess.file_exists(path):
			return false
	return true

func _transaction_artifact_paths() -> Array[String]:
	var paths: Array[String] = [
		str(KnowledgeImportTransactionScript.DB_BACKUP),
		str(KnowledgeImportTransactionScript.STRUCTURED_BACKUP),
		str(KnowledgeImportTransactionScript.REGISTRY_BACKUP),
		str(KnowledgeStoreScript.DB_PATH) + ".rollback.tmp",
		str(KnowledgeStoreScript.STRUCTURED_PATH) + ".rollback.tmp",
		str(KnowledgeStoreScript.DB_PATH) + ".filter.tmp",
		str(KnowledgeStoreScript.STRUCTURED_PATH) + ".filter.tmp",
		str(KnowledgeStoreScript.DB_PATH) + ".recovery.original",
		str(KnowledgeStoreScript.STRUCTURED_PATH) + ".recovery.original"
	]
	var constants: Dictionary = KnowledgeImportTransactionScript.get_script_constant_map()
	for name in [
		"TXN_MANIFEST",
		"TXN_MANIFEST_TMP",
		"TXN_SNAPSHOT_MARKER",
		"TXN_SNAPSHOT_MARKER_TMP",
		"TXN_COMMIT_MARKER",
		"TXN_COMMIT_MARKER_TMP"
	]:
		if constants.has(name):
			var value := str(constants.get(name, ""))
			if not value.is_empty():
				paths.append(value)
	return paths

func _write_large_replacement(target_bytes: int) -> Dictionary:
	var file: FileAccess = FileAccess.open(SOURCE, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot overwrite interruption source", "phase": "import"}
	var filler: String = "Aurora interrupted import replacement data данные memory retrieval local " + "x".repeat(768)
	var count := 0
	while file.get_position() < target_bytes:
		file.store_line(JSON.stringify({
			"index": count,
			"kind": "fact",
			"content": "%s %s row_%d" % [NEW_MARKER, filler, count]
		}))
		count += 1
	var size := file.get_position()
	file.close()
	return {"ok": true, "bytes": size, "records": count}

func _file_size(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size

func _reset_state() -> void:
	var paths := _transaction_artifact_paths()
	paths.append(str(KnowledgeStoreScript.DB_PATH))
	paths.append(str(KnowledgeStoreScript.STRUCTURED_PATH))
	paths.append(str(KnowledgeSourceRegistryScript.REGISTRY_PATH))
	paths.append(SOURCE)
	for path in paths:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _emit(result: Dictionary, code: int) -> void:
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
