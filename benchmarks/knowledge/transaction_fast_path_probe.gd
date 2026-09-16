extends SceneTree

# Variant-typed handles keep this probe portable on fresh headless Windows
# runners without depending on editor-generated global class caches.
const KnowledgeSourceRegistryScript: Variant = preload("res://scripts/knowledge_source_registry.gd")
const KnowledgeStoreScript: Variant = preload("res://scripts/knowledge_store.gd")
const LargeJsonKnowledgeImporterScript: Variant = preload("res://scripts/large_json_knowledge_importer.gd")
const KnowledgeImportTransactionScript: Variant = preload("res://scripts/knowledge_import_transaction.gd")

const RESULT_PREFIX := "AURORA_TRANSACTION_FAST_PATH_PROBE="
const ROOT := "user://knowledge_transaction_fast_path_probe"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	_reset_state()
	var store = KnowledgeStoreScript.new()
	var txn = KnowledgeImportTransactionScript.new()
	var path := ROOT.path_join("existing_source.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))

	var first_file := FileAccess.open(path, FileAccess.WRITE)
	if first_file == null:
		_emit({"ok": false, "error": "cannot create initial source"}, 2)
		return
	first_file.store_string('{"fact":"AURORA_TXN_FAST_PATH_STABLE","value":1}')
	first_file.close()
	var first: Dictionary = txn.import_file(store, path, {"imported_by": "transaction_fast_path_probe"})
	if not bool(first.get("ok", false)):
		_emit({"ok": false, "error": "initial import failed", "first": first}, 2)
		return
	var first_fp := str(first.get("fingerprint_sha256", ""))
	var new_source_fast_path := bool(first.get("snapshot_scan_skipped", false))

	var broken := FileAccess.open(path, FileAccess.WRITE)
	if broken == null:
		_emit({"ok": false, "error": "cannot overwrite existing source"}, 2)
		return
	broken.store_string('{"fact":"AURORA_TXN_FAST_PATH_PARTIAL","broken":[1,2,')
	broken.close()
	var failed: Dictionary = txn.import_file(store, path, {"imported_by": "transaction_fast_path_probe"})
	var existing_source_journaled := not bool(failed.get("snapshot_scan_skipped", true))
	var stable_restored := not store.search("AURORA_TXN_FAST_PATH_STABLE", 5).is_empty()
	var partial_absent := store.search("AURORA_TXN_FAST_PATH_PARTIAL", 5).is_empty()
	var registry = KnowledgeSourceRegistryScript.new()
	var restored_row: Dictionary = registry.record_for_source(path)
	var fingerprint_restored := str(restored_row.get("fingerprint_sha256", "")) == first_fp
	var existing_rollback_ok := (
		not bool(failed.get("ok", false))
		and str(failed.get("transaction", "")) == "rolled_back"
		and existing_source_journaled
		and stable_restored
		and partial_absent
		and fingerprint_restored
	)

	var failed_new_path := ROOT.path_join("brand_new_malformed.json")
	var failed_new_file := FileAccess.open(failed_new_path, FileAccess.WRITE)
	if failed_new_file == null:
		_emit({"ok": false, "error": "cannot create malformed new source"}, 2)
		return
	failed_new_file.store_string('{"fact":"AURORA_TXN_NEW_PARTIAL","broken":[1,2,')
	failed_new_file.close()
	var failed_new: Dictionary = txn.import_file(store, failed_new_path, {"imported_by": "transaction_fast_path_probe"})
	var failed_new_fast_path := bool(failed_new.get("snapshot_scan_skipped", false))
	var failed_new_registry_absent := registry.record_for_source(failed_new_path).is_empty()
	var failed_new_partial_absent := store.search("AURORA_TXN_NEW_PARTIAL", 5).is_empty()
	var new_failure_rollback_ok := (
		not bool(failed_new.get("ok", false))
		and str(failed_new.get("transaction", "")) == "rolled_back"
		and failed_new_fast_path
		and failed_new_registry_absent
		and failed_new_partial_absent
	)

	_emit({
		"ok": new_source_fast_path and existing_rollback_ok and new_failure_rollback_ok,
		"new_source_snapshot_scan_skipped": new_source_fast_path,
		"existing_source_snapshot_scan_skipped": bool(failed.get("snapshot_scan_skipped", true)),
		"existing_source_journaled": existing_source_journaled,
		"existing_failure_rollback_ok": existing_rollback_ok,
		"stable_restored": stable_restored,
		"partial_absent": partial_absent,
		"fingerprint_restored": fingerprint_restored,
		"new_failure_snapshot_scan_skipped": failed_new_fast_path,
		"new_failure_rollback_ok": new_failure_rollback_ok,
		"new_failure_registry_absent": failed_new_registry_absent,
		"new_failure_partial_absent": failed_new_partial_absent,
		"network_required": false,
		"external_runtime_required": false,
		"ollama_required": false
	}, 0 if new_source_fast_path and existing_rollback_ok and new_failure_rollback_ok else 2)

func _reset_state() -> void:
	for path in [
		KnowledgeStoreScript.DB_PATH,
		KnowledgeStoreScript.STRUCTURED_PATH,
		KnowledgeSourceRegistryScript.REGISTRY_PATH,
		KnowledgeImportTransactionScript.DB_BACKUP,
		KnowledgeImportTransactionScript.STRUCTURED_BACKUP,
		KnowledgeImportTransactionScript.REGISTRY_BACKUP,
		KnowledgeStoreScript.DB_PATH + ".filter.tmp",
		KnowledgeStoreScript.STRUCTURED_PATH + ".filter.tmp",
		KnowledgeStoreScript.DB_PATH + ".rollback.tmp",
		KnowledgeStoreScript.STRUCTURED_PATH + ".rollback.tmp"
	]:
		_remove_file(str(path))
	_remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))

func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var dir := DirAccess.open(absolute)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child := path.path_join(name)
			if dir.current_is_dir():
				_remove_tree(child)
			else:
				_remove_file(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(absolute)

func _emit(result: Dictionary, code: int) -> void:
	result["runtime"] = {"os": OS.get_name(), "godot": Engine.get_version_info()}
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
