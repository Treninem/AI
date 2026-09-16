extends SceneTree

# Deterministic cross-platform write-failure injection. A directory is created at
# sources.json.tmp, so registry finalization cannot open its temp file after the
# KnowledgeStore has already written the candidate revision. Transaction rollback
# must restore the previously committed rows and source registry atomically.
const KnowledgeStoreScript: Variant = preload("res://scripts/knowledge_store.gd")
const KnowledgeImportTransactionScript: Variant = preload("res://scripts/knowledge_import_transaction.gd")
const KnowledgeSourceRegistryScript: Variant = preload("res://scripts/knowledge_source_registry.gd")
const KnowledgeManagerScript: Variant = preload("res://scripts/knowledge_manager.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_WRITE_FAILURE_RESULT="
const ROOT := "user://knowledge_write_failure_probe"
const SOURCE := ROOT + "/source.json"
const STABLE_MARKER := "AURORA_WRITE_FAILURE_STABLE_MARKER"
const CANDIDATE_MARKER := "AURORA_WRITE_FAILURE_CANDIDATE_MARKER"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	_reset_state()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))

	var first := FileAccess.open(SOURCE, FileAccess.WRITE)
	if first == null:
		_emit({"ok": false, "error": "cannot create stable write-failure seed"}, 2)
		return
	first.store_string(JSON.stringify({"kind": "fact", "content": STABLE_MARKER}))
	first.close()

	var store: Variant = KnowledgeStoreScript.new()
	var txn: Variant = KnowledgeImportTransactionScript.new()
	var initial: Variant = txn.call("import_file", store, SOURCE, {"imported_by": "write_failure_probe"})
	if not initial is Dictionary or not bool(initial.get("ok", false)):
		_emit({"ok": false, "error": "stable seed import failed", "initial": initial}, 3)
		return
	var old_fp := str(initial.get("fingerprint_sha256", ""))
	var old_revision := int(initial.get("revision", 0))
	var stable_before := not store.call("search", STABLE_MARKER, 5).is_empty()

	var changed := FileAccess.open(SOURCE, FileAccess.WRITE)
	if changed == null:
		_emit({"ok": false, "error": "cannot overwrite source for write failure"}, 2)
		return
	changed.store_string(JSON.stringify({"kind": "fact", "content": CANDIDATE_MARKER}))
	changed.close()

	var registry_constants := KnowledgeSourceRegistryScript.get_script_constant_map()
	var temp_path := str(registry_constants.get("REGISTRY_TEMP", KnowledgeSourceRegistryScript.REGISTRY_PATH + ".tmp"))
	_remove_path(temp_path)
	var temp_abs := ProjectSettings.globalize_path(temp_path)
	var temp_dir_error := DirAccess.make_dir_recursive_absolute(temp_abs)
	if temp_dir_error != OK:
		_emit({"ok": false, "error": "cannot create registry temp collision", "code": temp_dir_error, "path": temp_path}, 2)
		return

	var failed: Variant = txn.call("import_file", store, SOURCE, {"imported_by": "write_failure_probe"})
	_remove_path(temp_path)

	# Re-create objects to force disk state rather than trusting in-process cache.
	KnowledgeSourceRegistryScript.invalidate_runtime_cache()
	var restarted_store: Variant = KnowledgeStoreScript.new()
	var restarted_registry: Variant = KnowledgeSourceRegistryScript.new()
	var stable_after := not restarted_store.call("search", STABLE_MARKER, 5).is_empty()
	var candidate_gone := restarted_store.call("search", CANDIDATE_MARKER, 5).is_empty()
	var row: Variant = restarted_registry.call("record_for_source", SOURCE)
	var fp_restored := row is Dictionary and str(row.get("fingerprint_sha256", "")) == old_fp
	var revision_restored := row is Dictionary and int(row.get("revision", 0)) == old_revision
	var manager: Variant = KnowledgeManagerScript.new()
	var recovery: Variant = manager.call("recovery_status")
	var journals_clean := _journals_clean()
	var rolled_back := failed is Dictionary and not bool(failed.get("ok", false)) and str(failed.get("transaction", "")) == "rolled_back"
	var ok := stable_before and rolled_back and stable_after and candidate_gone and fp_restored and revision_restored
	ok = ok and recovery is Dictionary and bool(recovery.get("ok", false)) and journals_clean
	_emit({
		"ok": ok,
		"write_failure_injected": true,
		"failure_target": temp_path,
		"failed_import": failed,
		"transaction_rolled_back": rolled_back,
		"stable_before": stable_before,
		"stable_after": stable_after,
		"candidate_partial_absent": candidate_gone,
		"fingerprint_restored": fp_restored,
		"revision_restored": revision_restored,
		"journals_clean": journals_clean,
		"startup_recovery": recovery,
		"network_required": false,
		"external_runtime_required": false,
		"ollama_required": false,
		"expected_contract": "registry finalization write failure must preserve the last committed Knowledge source"
	}, 0 if ok else 5)

func _journals_clean() -> bool:
	for path in [
		KnowledgeImportTransactionScript.DB_BACKUP,
		KnowledgeImportTransactionScript.STRUCTURED_BACKUP,
		KnowledgeImportTransactionScript.REGISTRY_BACKUP,
		KnowledgeImportTransactionScript.TXN_MANIFEST,
		KnowledgeImportTransactionScript.TXN_SNAPSHOT_MARKER,
		KnowledgeImportTransactionScript.TXN_COMMIT_MARKER
	]:
		if FileAccess.file_exists(str(path)):
			return false
	return true

func _reset_state() -> void:
	var registry_constants := KnowledgeSourceRegistryScript.get_script_constant_map()
	var registry_temp := str(registry_constants.get("REGISTRY_TEMP", KnowledgeSourceRegistryScript.REGISTRY_PATH + ".tmp"))
	var registry_original := str(registry_constants.get("REGISTRY_ORIGINAL", KnowledgeSourceRegistryScript.REGISTRY_PATH + ".write.original"))
	for path in [
		KnowledgeStoreScript.DB_PATH,
		KnowledgeStoreScript.STRUCTURED_PATH,
		KnowledgeSourceRegistryScript.REGISTRY_PATH,
		registry_temp,
		registry_original,
		KnowledgeImportTransactionScript.DB_BACKUP,
		KnowledgeImportTransactionScript.STRUCTURED_BACKUP,
		KnowledgeImportTransactionScript.REGISTRY_BACKUP,
		KnowledgeImportTransactionScript.TXN_MANIFEST,
		KnowledgeImportTransactionScript.TXN_MANIFEST_TMP,
		KnowledgeImportTransactionScript.TXN_SNAPSHOT_MARKER,
		KnowledgeImportTransactionScript.TXN_SNAPSHOT_MARKER_TMP,
		KnowledgeImportTransactionScript.TXN_COMMIT_MARKER,
		KnowledgeImportTransactionScript.TXN_COMMIT_MARKER_TMP,
		SOURCE
	]:
		_remove_path(str(path))

func _remove_path(path: String) -> void:
	if path.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute)
		return
	if DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(absolute)

func _emit(result: Dictionary, code: int) -> void:
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
