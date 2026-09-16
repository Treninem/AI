extends SceneTree

# Regression probe for pre-registry/direct-import knowledge. A failed transactional
# reimport must preserve legacy rows even when sources.json has no record yet.
const KnowledgeStoreScript: Variant = preload("res://scripts/knowledge_store.gd")
const KnowledgeImportTransactionScript: Variant = preload("res://scripts/knowledge_import_transaction.gd")
const KnowledgeSourceRegistryScript: Variant = preload("res://scripts/knowledge_source_registry.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_LEGACY_ROLLBACK_RESULT="
const PROBE_ROOT := "user://knowledge_legacy_rollback_probe"
const SOURCE := PROBE_ROOT + "/legacy_source.json"
const STABLE_MARKER := "AURORA_LEGACY_UNREGISTERED_STABLE_MARKER"
const PARTIAL_MARKER := "AURORA_LEGACY_UNREGISTERED_PARTIAL_MARKER"
const MB := 1024 * 1024

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	_reset_state()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROBE_ROOT))
	var seed_file: FileAccess = FileAccess.open(SOURCE, FileAccess.WRITE)
	if seed_file == null:
		_emit({"ok": false, "error": "cannot create legacy seed"}, 2)
		return
	seed_file.store_string(JSON.stringify({"fact": STABLE_MARKER, "description": "legacy row before registry existed"}))
	seed_file.close()

	# Deliberately bypass KnowledgeImportTransaction: this models databases created
	# before the source registry existed (or legacy direct KnowledgeStore imports).
	var seed_store: Variant = KnowledgeStoreScript.new()
	var seed_result: Variant = seed_store.call("import_file", SOURCE, {"imported_by": "legacy_pre_registry_probe"})
	var stable_before: bool = not seed_store.call("search", STABLE_MARKER, 5).is_empty()
	var registry_before: Variant = KnowledgeSourceRegistryScript.new().call("record_for_source", SOURCE)

	var broken: FileAccess = FileAccess.open(SOURCE, FileAccess.WRITE)
	if broken == null:
		_emit({"ok": false, "error": "cannot overwrite legacy source"}, 2)
		return
	broken.store_string('{"value":"%s","broken":[1,2,' % PARTIAL_MARKER)
	var block: String = " ".repeat(MB)
	for _i in range(9):
		broken.store_string(block)
	broken.store_string('}')
	broken.close()

	var txn: Variant = KnowledgeImportTransactionScript.new()
	var failed: Variant = txn.call("import_file", KnowledgeStoreScript.new(), SOURCE, {"imported_by": "legacy_rollback_probe"})
	var after_store: Variant = KnowledgeStoreScript.new()
	var stable_after: bool = not after_store.call("search", STABLE_MARKER, 5).is_empty()
	var partial_gone: bool = after_store.call("search", PARTIAL_MARKER, 5).is_empty()
	var registry_after: Variant = KnowledgeSourceRegistryScript.new().call("record_for_source", SOURCE)
	var rolled_back: bool = failed is Dictionary and not bool(failed.get("ok", false)) and str(failed.get("transaction", "")) == "rolled_back"
	var ok: bool = seed_result is Dictionary and bool(seed_result.get("ok", false))
	ok = ok and stable_before and registry_before.is_empty() and rolled_back and stable_after and partial_gone and registry_after.is_empty()
	_emit({
		"ok": ok,
		"seed_import_ok": seed_result is Dictionary and bool(seed_result.get("ok", false)),
		"registry_absent_before": registry_before.is_empty(),
		"stable_before": stable_before,
		"failed_reimport": failed,
		"rolled_back": rolled_back,
		"stable_after": stable_after,
		"partial_removed": partial_gone,
		"registry_absent_after": registry_after.is_empty(),
		"expected_contract": "failed reimport must preserve legacy source rows that predate sources.json"
	}, 0 if ok else 3)

func _reset_state() -> void:
	for path in [
		KnowledgeStoreScript.DB_PATH,
		KnowledgeStoreScript.STRUCTURED_PATH,
		KnowledgeSourceRegistryScript.REGISTRY_PATH,
		KnowledgeImportTransactionScript.DB_BACKUP,
		KnowledgeImportTransactionScript.STRUCTURED_BACKUP,
		KnowledgeImportTransactionScript.REGISTRY_BACKUP,
		KnowledgeStoreScript.DB_PATH + ".rollback.tmp",
		KnowledgeStoreScript.STRUCTURED_PATH + ".rollback.tmp",
		SOURCE
	]:
		if FileAccess.file_exists(str(path)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(str(path)))

func _emit(result: Dictionary, code: int) -> void:
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
