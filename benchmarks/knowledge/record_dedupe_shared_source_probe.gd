extends SceneTree

# Proves record-level dedupe separately from whole-file SHA dedupe. Exact repeated
# records within one source should not explode the normalized knowledge store.
# Across distinct sources, provenance may remain source-scoped, but removing one
# source must preserve an identical shared fact owned by the other source.
const KnowledgeStoreScript: Variant = preload("res://scripts/knowledge_store.gd")
const KnowledgeImportTransactionScript: Variant = preload("res://scripts/knowledge_import_transaction.gd")
const KnowledgeSourceRegistryScript: Variant = preload("res://scripts/knowledge_source_registry.gd")
const KnowledgeManagerScript: Variant = preload("res://scripts/knowledge_manager.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_RECORD_DEDUPE_RESULT="
const ROOT := "user://knowledge_record_dedupe_probe"
const SOURCE_A := ROOT + "/source_A.jsonl"
const SOURCE_B := ROOT + "/source_B.jsonl"
const SHARED := "AURORA_RECORD_DEDUPE_SHARED_FACT_314159"
const UNIQUE_A := "AURORA_RECORD_DEDUPE_UNIQUE_A_271828"
const UNIQUE_B := "AURORA_RECORD_DEDUPE_UNIQUE_B_161803"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	_reset_state()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	if not _write_sources():
		_emit({"ok": false, "error": "cannot create record-dedupe sources"}, 2)
		return

	var store: Variant = KnowledgeStoreScript.new()
	var txn: Variant = KnowledgeImportTransactionScript.new()
	var imported_a: Variant = txn.call("import_file", store, SOURCE_A, {"imported_by": "record_dedupe_probe"})
	if not (imported_a is Dictionary and bool(imported_a.get("ok", false))):
		_emit({"ok": false, "error": "source A import failed", "result": imported_a}, 3)
		return
	var imported_b: Variant = txn.call("import_file", store, SOURCE_B, {"imported_by": "record_dedupe_probe"})
	if not (imported_b is Dictionary and bool(imported_b.get("ok", false))):
		_emit({"ok": false, "error": "source B import failed", "result": imported_b}, 4)
		return

	var before := _count_shared_rows()
	var same_source_dedupe_ok := int(before.get("a", 0)) == 1
	# Distinct sources keep independent provenance, so exactly one normalized copy
	# per source is expected rather than one global row with ambiguous ownership.
	var cross_source_dedupe_ok := int(before.get("a", 0)) == 1 and int(before.get("b", 0)) == 1
	var manager: Variant = KnowledgeManagerScript.new()
	var removed_b: Variant = manager.call("remove_source", SOURCE_B)
	var shared_after: Variant = store.call("search", SHARED, 8)
	var unique_a_after: Variant = store.call("search", UNIQUE_A, 8)
	var unique_b_after: Variant = store.call("search", UNIQUE_B, 8)
	var registry: Variant = KnowledgeSourceRegistryScript.new()
	var a_row: Variant = registry.call("record_for_source", SOURCE_A)
	var b_row: Variant = registry.call("record_for_source", SOURCE_B)
	var after := _count_shared_rows()

	var lifecycle_ok := removed_b is Dictionary and bool(removed_b.get("ok", false))
	lifecycle_ok = lifecycle_ok and _contains_source(shared_after, SOURCE_A)
	lifecycle_ok = lifecycle_ok and _contains_source(unique_a_after, SOURCE_A)
	lifecycle_ok = lifecycle_ok and unique_b_after.is_empty()
	lifecycle_ok = lifecycle_ok and a_row is Dictionary and not a_row.is_empty()
	lifecycle_ok = lifecycle_ok and b_row is Dictionary and b_row.is_empty()
	lifecycle_ok = lifecycle_ok and int(after.get("a", 0)) == 1 and int(after.get("b", 0)) == 0

	var dedupe_ok := same_source_dedupe_ok and cross_source_dedupe_ok
	_emit({
		"ok": lifecycle_ok and dedupe_ok,
		"same_source_dedupe_ok": same_source_dedupe_ok,
		"cross_source_provenance_dedupe_ok": cross_source_dedupe_ok,
		"source_removal_preserves_shared_fact": lifecycle_ok,
		"shared_rows_before": before,
		"shared_rows_after_remove_b": after,
		"expected_shared_rows_before": {"a": 1, "b": 1, "total": 2},
		"input_duplicate_records_in_a": 5,
		"removed_b": removed_b,
		"network_required": false,
		"external_runtime_required": false,
		"ollama_required": false
	}, 0 if lifecycle_ok and dedupe_ok else 5)

func _write_sources() -> bool:
	var a: FileAccess = FileAccess.open(SOURCE_A, FileAccess.WRITE)
	if a == null:
		return false
	for _i in range(5):
		a.store_line(JSON.stringify({"kind": "fact", "content": SHARED}))
	a.store_line(JSON.stringify({"kind": "fact", "content": UNIQUE_A}))
	a.close()
	var b: FileAccess = FileAccess.open(SOURCE_B, FileAccess.WRITE)
	if b == null:
		return false
	b.store_line(JSON.stringify({"kind": "fact", "content": SHARED}))
	b.store_line(JSON.stringify({"kind": "fact", "content": UNIQUE_B}))
	b.close()
	return true

func _count_shared_rows() -> Dictionary:
	var out := {"a": 0, "b": 0, "total": 0}
	if not FileAccess.file_exists(KnowledgeStoreScript.DB_PATH):
		return out
	var file: FileAccess = FileAccess.open(KnowledgeStoreScript.DB_PATH, FileAccess.READ)
	if file == null:
		return out
	while not file.eof_reached():
		var line := file.get_line()
		if line.strip_edges().is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if not parsed is Dictionary or not str(parsed.get("text", "")).contains(SHARED):
			continue
		var source := str(parsed.get("source", ""))
		if source == SOURCE_A:
			out["a"] = int(out.get("a", 0)) + 1
		elif source == SOURCE_B:
			out["b"] = int(out.get("b", 0)) + 1
		out["total"] = int(out.get("total", 0)) + 1
	file.close()
	return out

func _contains_source(items: Variant, source: String) -> bool:
	if not items is Array:
		return false
	for item in items:
		if item is Dictionary and str(item.get("source", "")) == source:
			return true
	return false

func _reset_state() -> void:
	var paths: Array[String] = [
		str(KnowledgeStoreScript.DB_PATH),
		str(KnowledgeStoreScript.STRUCTURED_PATH),
		str(KnowledgeSourceRegistryScript.REGISTRY_PATH),
		str(KnowledgeImportTransactionScript.DB_BACKUP),
		str(KnowledgeImportTransactionScript.STRUCTURED_BACKUP),
		str(KnowledgeImportTransactionScript.REGISTRY_BACKUP),
		SOURCE_A,
		SOURCE_B
	]
	var constants: Dictionary = KnowledgeImportTransactionScript.get_script_constant_map()
	for name in ["TXN_MANIFEST", "TXN_MANIFEST_TMP", "TXN_SNAPSHOT_MARKER", "TXN_SNAPSHOT_MARKER_TMP", "TXN_COMMIT_MARKER", "TXN_COMMIT_MARKER_TMP"]:
		if constants.has(name):
			paths.append(str(constants.get(name, "")))
	var registry_constants: Dictionary = KnowledgeSourceRegistryScript.get_script_constant_map()
	for name in ["REGISTRY_TEMP", "REGISTRY_ORIGINAL"]:
		if registry_constants.has(name):
			paths.append(str(registry_constants.get(name, "")))
	for path in paths:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _emit(result: Dictionary, code: int) -> void:
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
