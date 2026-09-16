extends SceneTree

const KnowledgeStoreScript: Variant = preload("res://scripts/knowledge_store.gd")
const KnowledgeImportTransactionScript: Variant = preload("res://scripts/knowledge_import_transaction.gd")
const KnowledgeManagerScript: Variant = preload("res://scripts/knowledge_manager.gd")
const KnowledgeSourceRegistryScript: Variant = preload("res://scripts/knowledge_source_registry.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_LOST_REGISTRY_ROLLBACK_RESULT="
const PROBE_ROOT := "user://knowledge_lost_registry_probe"
const SOURCE := PROBE_ROOT + "/source.json"
const STABLE_MARKER := "AURORA_LOST_REGISTRY_STABLE_MARKER"
const PARTIAL_MARKER := "AURORA_LOST_REGISTRY_PARTIAL_MARKER"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	_reset_state()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROBE_ROOT))
	var initial_file := FileAccess.open(SOURCE, FileAccess.WRITE)
	if initial_file == null:
		_emit({"ok": false, "error": "cannot create stable source"}, 2)
		return
	initial_file.store_string(JSON.stringify({"fact": STABLE_MARKER, "description": "valid state before registry loss"}))
	initial_file.close()

	# Seed persisted JSONL directly so KnowledgeImportTransaction's static
	# source-presence cache is still cold. Then create a normal registry row
	# separately and delete it. The failing transaction must rediscover the old
	# source from persisted data rather than succeeding because of a warm cache.
	var store: Variant = KnowledgeStoreScript.new()
	var seed_result: Variant = store.call("import_file", SOURCE, {"imported_by": "lost_registry_seed"})
	if not (seed_result is Dictionary and bool(seed_result.get("ok", false))):
		_emit({"ok": false, "error": "seed import failed", "seed": seed_result}, 3)
		return
	var registry: Variant = KnowledgeSourceRegistryScript.new()
	var inspection: Variant = registry.call("inspect_file", SOURCE)
	var registered: Variant = registry.call("mark_imported", SOURCE, inspection, seed_result, {"imported_by": "lost_registry_seed"})
	if not (registered is Dictionary and bool(registered.get("ok", false))):
		_emit({"ok": false, "error": "registry seed failed", "inspection": inspection, "registered": registered}, 3)
		return

	var before_chunks := int(KnowledgeManagerScript.new().call("stats").get("chunks", 0))
	var stable_before: Variant = store.call("search", STABLE_MARKER, 5)
	var registry_before: Variant = registry.call("record_for_source", SOURCE)

	var registry_path := str(KnowledgeSourceRegistryScript.REGISTRY_PATH)
	if FileAccess.file_exists(registry_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(registry_path))
	KnowledgeSourceRegistryScript.invalidate_runtime_cache()

	var broken := FileAccess.open(SOURCE, FileAccess.WRITE)
	if broken == null:
		_emit({"ok": false, "error": "cannot create malformed replacement"}, 4)
		return
	broken.store_string('{"fact":"%s","broken":[1,2,' % PARTIAL_MARKER)
	broken.close()

	# First transaction instance is created only after registry loss. This forces
	# the production path to rebuild source presence from JSONL on disk.
	var txn: Variant = KnowledgeImportTransactionScript.new()
	var failed: Variant = txn.call("import_file", KnowledgeStoreScript.new(), SOURCE, {"imported_by": "lost_registry_rollback_probe"})
	var after_store: Variant = KnowledgeStoreScript.new()
	var stable_after: Variant = after_store.call("search", STABLE_MARKER, 5)
	var partial_after: Variant = after_store.call("search", PARTIAL_MARKER, 5)
	var after_chunks := int(KnowledgeManagerScript.new().call("stats").get("chunks", 0))
	var registry_after: Variant = KnowledgeSourceRegistryScript.new().call("record_for_source", SOURCE)
	var failed_as_expected := not bool(failed.get("ok", false)) and str(failed.get("transaction", "")) == "rolled_back"
	var conservative_snapshot := str(failed.get("source_snapshot", "")) == "source_rows"
	var preserved := not stable_after.is_empty() and after_chunks == before_chunks and partial_after.is_empty()
	var ok := not stable_before.is_empty() and not registry_before.is_empty()
	ok = ok and failed_as_expected and conservative_snapshot and preserved and registry_after.is_empty()
	_emit({
		"ok": ok,
		"seed_import_ok": seed_result is Dictionary and bool(seed_result.get("ok", false)),
		"registry_seed_ok": registered is Dictionary and bool(registered.get("ok", false)),
		"stable_before": not stable_before.is_empty(),
		"registry_before": not registry_before.is_empty(),
		"registry_deleted_before_failure": true,
		"failed_as_expected": failed_as_expected,
		"transaction": failed.get("transaction", ""),
		"source_snapshot": failed.get("source_snapshot", ""),
		"conservative_snapshot": conservative_snapshot,
		"stable_after": not stable_after.is_empty(),
		"partial_after": not partial_after.is_empty(),
		"registry_absent_after": registry_after.is_empty(),
		"chunks_before": before_chunks,
		"chunks_after": after_chunks,
		"previous_valid_state_preserved": preserved,
		"expected_contract": "after registry loss, a cold transaction must rediscover persisted source rows and preserve them on failed re-import"
	}, 0 if ok else 5)

func _reset_state() -> void:
	for path in [
		"user://knowledge/knowledge.jsonl",
		"user://knowledge/structured.jsonl",
		"user://knowledge/sources.json",
		"user://knowledge/.knowledge_source.txn.jsonl",
		"user://knowledge/.structured_source.txn.jsonl",
		"user://knowledge/.sources.json.txn",
		"user://knowledge/.knowledge_import.txn.json",
		"user://knowledge/.knowledge_import.txn.json.tmp",
		SOURCE
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	KnowledgeSourceRegistryScript.invalidate_runtime_cache()

func _emit(result: Dictionary, code: int) -> void:
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
