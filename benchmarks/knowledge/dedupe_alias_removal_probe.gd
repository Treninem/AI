extends SceneTree

# Dynamic handles keep this correctness probe independent from editor class cache.
const KnowledgeStoreScript: Variant = preload("res://scripts/knowledge_store.gd")
const KnowledgeImportTransactionScript: Variant = preload("res://scripts/knowledge_import_transaction.gd")
const KnowledgeManagerScript: Variant = preload("res://scripts/knowledge_manager.gd")
const KnowledgeSourceRegistryScript: Variant = preload("res://scripts/knowledge_source_registry.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_ALIAS_REMOVAL_RESULT="
const PROBE_ROOT := "user://knowledge_alias_removal_probe"
const ORIGINAL := PROBE_ROOT + "/original.jsonl"
const ALIAS := PROBE_ROOT + "/копия базы с пробелами.jsonl"
const MARKER := "AURORA_ALIAS_REMOVAL_SHARED_MARKER"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	_reset_state()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROBE_ROOT))
	var file := FileAccess.open(ORIGINAL, FileAccess.WRITE)
	if file == null:
		_emit({"ok": false, "error": "cannot create source"}, 2)
		return
	for i in range(128):
		file.store_line(JSON.stringify({
			"kind": "fact",
			"content": "%s record_%d shared canonical content" % [MARKER, i]
		}))
	file.close()
	var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(ORIGINAL), ProjectSettings.globalize_path(ALIAS))
	if copy_error != OK:
		_emit({"ok": false, "error": "cannot create alias copy", "code": copy_error}, 2)
		return

	var store = KnowledgeStoreScript.new()
	var txn = KnowledgeImportTransactionScript.new()
	var first = txn.call("import_file", store, ORIGINAL, {"imported_by": "alias_removal_probe"})
	var duplicate = txn.call("import_file", store, ALIAS, {"imported_by": "alias_removal_probe"})
	var before = store.call("search", MARKER, 8)
	var registry = KnowledgeSourceRegistryScript.new()
	var canonical_before = registry.call("record_for_source", ORIGINAL)
	var alias_before = registry.call("record_for_source", ALIAS)
	var removed = KnowledgeManagerScript.new().call("remove_source", ALIAS)
	var after_store = KnowledgeStoreScript.new()
	var after = after_store.call("search", MARKER, 8)
	var canonical_after = KnowledgeSourceRegistryScript.new().call("record_for_source", ORIGINAL)
	var alias_after = KnowledgeSourceRegistryScript.new().call("record_for_source", ALIAS)

	var duplicate_registered := bool(duplicate.get("ok", false)) and bool(duplicate.get("duplicate", false)) and bool(duplicate.get("skipped", false))
	var canonical_survived := not after.is_empty() and not canonical_after.is_empty()
	var alias_detached := alias_after.is_empty()
	var ok := bool(first.get("ok", false)) and duplicate_registered and not before.is_empty() and not canonical_before.is_empty() and not alias_before.is_empty()
	ok = ok and bool(removed.get("ok", false)) and canonical_survived and alias_detached
	_emit({
		"ok": ok,
		"first_import_ok": bool(first.get("ok", false)),
		"duplicate_registered": duplicate_registered,
		"pre_remove_searchable": not before.is_empty(),
		"canonical_registry_before": not canonical_before.is_empty(),
		"alias_registry_before": not alias_before.is_empty(),
		"remove_result": removed,
		"canonical_survived": canonical_survived,
		"alias_detached": alias_detached,
		"post_remove_searchable": not after.is_empty(),
		"canonical_registry_after": not canonical_after.is_empty(),
		"alias_registry_after": not alias_after.is_empty(),
		"expected_contract": "removing an alias/copy must not delete the canonical shared knowledge"
	}, 0 if ok else 3)

func _reset_state() -> void:
	for path in [
		"user://knowledge/knowledge.jsonl",
		"user://knowledge/structured.jsonl",
		"user://knowledge/sources.json",
		"user://knowledge/.knowledge_source.txn.jsonl",
		"user://knowledge/.structured_source.txn.jsonl",
		"user://knowledge/.sources.json.txn",
		ORIGINAL,
		ALIAS
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _emit(result: Dictionary, code: int) -> void:
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
