extends SceneTree

# Multi-process canonical source-removal recovery probe. Python orchestrates:
# seed A+B+C -> start canonical B removal -> kill after first storage mutation ->
# verify that startup recovery restores the last fully committed A+B+C state.
const KnowledgeStoreScript: Variant = preload("res://scripts/knowledge_store.gd")
const KnowledgeImportTransactionScript: Variant = preload("res://scripts/knowledge_import_transaction.gd")
const KnowledgeSourceRegistryScript: Variant = preload("res://scripts/knowledge_source_registry.gd")
const KnowledgeManagerScript: Variant = preload("res://scripts/knowledge_manager.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_REMOVE_INTERRUPT_RESULT="
const ROOT := "user://knowledge_remove_interrupt_probe"
const SOURCE_A := ROOT + "/source_A.jsonl"
const SOURCE_B := ROOT + "/source_B.jsonl"
const SOURCE_C := ROOT + "/source_C.jsonl"
const MARKER_A := "AURORA_REMOVE_KEEP_A_MARKER"
const MARKER_B := "AURORA_REMOVE_TARGET_B_MARKER"
const MARKER_C := "AURORA_REMOVE_KEEP_C_MARKER"
const MB := 1024 * 1024

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	var phase := OS.get_environment("AURORA_REMOVE_INTERRUPT_PHASE").strip_edges()
	match phase:
		"seed": _seed()
		"remove": _remove_live()
		"verify": _verify()
		_: _emit({"ok": false, "error": "unknown removal interruption phase", "phase": phase}, 2)

func _seed() -> void:
	_reset_state()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var target_mb := maxi(4, int(OS.get_environment("AURORA_REMOVE_INTERRUPT_TARGET_MB")))
	var a := _write_source(SOURCE_A, MARKER_A, 192 * 1024)
	var b := _write_source(SOURCE_B, MARKER_B, target_mb * MB)
	var c := _write_source(SOURCE_C, MARKER_C, 192 * 1024)
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)) or not bool(c.get("ok", false)):
		_emit({"ok": false, "phase": "seed", "a": a, "b": b, "c": c}, 2)
		return

	var store: Variant = KnowledgeStoreScript.new()
	var txn: Variant = KnowledgeImportTransactionScript.new()
	var imported_a: Variant = txn.call("import_file", store, SOURCE_A, {"imported_by": "interrupted_removal_probe"})
	var imported_b: Variant = txn.call("import_file", store, SOURCE_B, {"imported_by": "interrupted_removal_probe"})
	var imported_c: Variant = txn.call("import_file", store, SOURCE_C, {"imported_by": "interrupted_removal_probe"})
	var registry: Variant = KnowledgeSourceRegistryScript.new()
	var row_b: Variant = registry.call("record_for_source", SOURCE_B)
	var ok := bool(imported_a.get("ok", false)) and bool(imported_b.get("ok", false)) and bool(imported_c.get("ok", false))
	ok = ok and not store.call("search", MARKER_A, 4).is_empty()
	ok = ok and not store.call("search", MARKER_B, 4).is_empty()
	ok = ok and not store.call("search", MARKER_C, 4).is_empty()
	ok = ok and row_b is Dictionary and not row_b.is_empty()
	_emit({
		"ok": ok,
		"phase": "seed",
		"source_b": SOURCE_B,
		"target_mb": target_mb,
		"db_abs": ProjectSettings.globalize_path(KnowledgeStoreScript.DB_PATH),
		"structured_abs": ProjectSettings.globalize_path(KnowledgeStoreScript.STRUCTURED_PATH),
		"registry_abs": ProjectSettings.globalize_path(KnowledgeSourceRegistryScript.REGISTRY_PATH),
		"manifest_abs": ProjectSettings.globalize_path(KnowledgeImportTransactionScript.TXN_MANIFEST),
		"db_backup_abs": ProjectSettings.globalize_path(KnowledgeImportTransactionScript.DB_BACKUP),
		"structured_backup_abs": ProjectSettings.globalize_path(KnowledgeImportTransactionScript.STRUCTURED_BACKUP),
		"registry_backup_abs": ProjectSettings.globalize_path(KnowledgeImportTransactionScript.REGISTRY_BACKUP),
		"db_size": _file_size(KnowledgeStoreScript.DB_PATH),
		"structured_size": _file_size(KnowledgeStoreScript.STRUCTURED_PATH),
		"registry_size": _file_size(KnowledgeSourceRegistryScript.REGISTRY_PATH)
	}, 0 if ok else 3)

func _remove_live() -> void:
	print("AURORA_KNOWLEDGE_REMOVE_STARTED=" + JSON.stringify({"source": SOURCE_B}))
	var manager: Variant = KnowledgeManagerScript.new()
	var result: Variant = manager.call("remove_source", SOURCE_B)
	# Python is expected to kill this process after the first storage mutation.
	_emit({
		"ok": false,
		"phase": "remove",
		"error": "canonical removal completed before interruption",
		"remove": result
	}, 4)

func _verify() -> void:
	# Manager construction must trigger production startup recovery before reads.
	var manager: Variant = KnowledgeManagerScript.new()
	var recovery: Dictionary = manager.call("recovery_status")
	var store: Variant = KnowledgeStoreScript.new()
	var registry: Variant = KnowledgeSourceRegistryScript.new()
	var a_present := not store.call("search", MARKER_A, 4).is_empty()
	var b_present := not store.call("search", MARKER_B, 4).is_empty()
	var c_present := not store.call("search", MARKER_C, 4).is_empty()
	var b_registry: Variant = registry.call("record_for_source", SOURCE_B)
	var journals_clean := not FileAccess.file_exists(KnowledgeImportTransactionScript.DB_BACKUP)
	journals_clean = journals_clean and not FileAccess.file_exists(KnowledgeImportTransactionScript.STRUCTURED_BACKUP)
	journals_clean = journals_clean and not FileAccess.file_exists(KnowledgeImportTransactionScript.REGISTRY_BACKUP)
	journals_clean = journals_clean and not FileAccess.file_exists(KnowledgeImportTransactionScript.TXN_MANIFEST)
	journals_clean = journals_clean and not FileAccess.file_exists(KnowledgeImportTransactionScript.TXN_SNAPSHOT_MARKER)
	journals_clean = journals_clean and not FileAccess.file_exists(KnowledgeImportTransactionScript.TXN_COMMIT_MARKER)
	var ok := bool(recovery.get("ok", false)) and bool(recovery.get("recovered", false))
	ok = ok and a_present and b_present and c_present
	ok = ok and b_registry is Dictionary and not b_registry.is_empty() and journals_clean
	_emit({
		"ok": ok,
		"phase": "verify",
		"startup_recovery": recovery,
		"source_a_present": a_present,
		"source_b_restored": b_present,
		"source_c_present": c_present,
		"source_b_registry_restored": b_registry is Dictionary and not b_registry.is_empty(),
		"journals_clean": journals_clean,
		"expected_contract": "kill during canonical source removal restores last fully committed A+B+C state"
	}, 0 if ok else 5)

func _write_source(path: String, marker: String, target_bytes: int) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot create removal probe source", "path": path}
	var filler := "Aurora local knowledge removal recovery данные source safety " + "x".repeat(720)
	var count := 0
	while file.get_position() < target_bytes:
		file.store_line(JSON.stringify({
			"index": count,
			"kind": "fact",
			"content": "%s %s row_%d" % [marker, filler, count]
		}))
		count += 1
	var size := file.get_position()
	file.close()
	return {"ok": true, "bytes": size, "records": count}

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size

func _reset_state() -> void:
	var paths: Array = [
		KnowledgeStoreScript.DB_PATH,
		KnowledgeStoreScript.STRUCTURED_PATH,
		KnowledgeSourceRegistryScript.REGISTRY_PATH,
		KnowledgeSourceRegistryScript.REGISTRY_PATH + ".tmp",
		KnowledgeSourceRegistryScript.REGISTRY_PATH + ".write.original",
		KnowledgeImportTransactionScript.DB_BACKUP,
		KnowledgeImportTransactionScript.STRUCTURED_BACKUP,
		KnowledgeImportTransactionScript.REGISTRY_BACKUP,
		KnowledgeImportTransactionScript.TXN_MANIFEST,
		KnowledgeImportTransactionScript.TXN_MANIFEST_TMP,
		KnowledgeImportTransactionScript.TXN_SNAPSHOT_MARKER,
		KnowledgeImportTransactionScript.TXN_SNAPSHOT_MARKER_TMP,
		KnowledgeImportTransactionScript.TXN_COMMIT_MARKER,
		KnowledgeImportTransactionScript.TXN_COMMIT_MARKER_TMP,
		KnowledgeStoreScript.DB_PATH + ".filter.tmp",
		KnowledgeStoreScript.STRUCTURED_PATH + ".filter.tmp",
		SOURCE_A,
		SOURCE_B,
		SOURCE_C
	]
	for value in paths:
		var path := str(value)
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _emit(result: Dictionary, code: int) -> void:
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
