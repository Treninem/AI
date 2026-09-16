extends SceneTree

# Keep this diagnostic independent from editor-generated class caches, matching
# the canonical Knowledge performance harness. Production scripts are read-only.
const KnowledgeDocumentImporterScript = preload("res://scripts/knowledge_document_importer.gd")
const AuroraJsonStreamReaderScript = preload("res://scripts/json_stream_reader.gd")
const KnowledgeSourceRegistryScript = preload("res://scripts/knowledge_source_registry.gd")
const KnowledgeStoreScript = preload("res://scripts/knowledge_store.gd")
const LargeJsonKnowledgeImporterScript = preload("res://scripts/large_json_knowledge_importer.gd")
const KnowledgeImportTransactionScript = preload("res://scripts/knowledge_import_transaction.gd")
const KnowledgeManagerScript = preload("res://scripts/knowledge_manager.gd")

const RESULT_PREFIX := "AURORA_RECORD_DEDUP_PROBE="
const BENCH_ROOT := "user://knowledge_record_dedup_probe"
const SHARED_MARKER := "AURORA_RECORD_DEDUP_SHARED_MARKER"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	_reset_state()
	var within := _probe_within_source_duplicates(96)
	_reset_state()
	var cross := _probe_cross_source_duplicates(64)
	var passed := bool(within.get("dedupe_contract_passed", false)) and bool(cross.get("dedupe_contract_passed", false))
	_emit({
		"ok": true,
		"diagnostic_completed": true,
		"dedupe_contract_passed": passed,
		"expected_semantics": {
			"identical_records_within_one_source": "single physical content record with source/path provenance references",
			"identical_records_across_sources": "single physical content record with multi-source provenance/reference accounting",
			"source_removal_must_preserve_shared_content": true
		},
		"within_source": within,
		"cross_source": cross,
		"production_files_modified": false
	}, 0)

func _probe_within_source_duplicates(count: int) -> Dictionary:
	var path := BENCH_ROOT.path_join("duplicates_inside_one_source.jsonl")
	_ensure_dir()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot create same-source fixture", "dedupe_contract_passed": false}
	for _i in range(count):
		file.store_line(JSON.stringify({"fact": SHARED_MARKER, "value": 42, "language": "ru-en"}))
	file.close()
	var store := KnowledgeStoreScript.new()
	var txn := KnowledgeImportTransactionScript.new()
	var started := Time.get_ticks_usec()
	var imported := txn.import_file(store, path, {"imported_by": "record_dedup_diagnostic"})
	var elapsed := _elapsed_ms(started)
	if not bool(imported.get("ok", false)):
		return {"ok": false, "error": "same-source import failed", "result": imported, "dedupe_contract_passed": false}
	var physical := _count_marker_occurrences(path, SHARED_MARKER)
	var manager := KnowledgeManagerScript.new()
	return {
		"ok": true,
		"input_records": count,
		"reported_records": int(imported.get("records", 0)),
		"reported_chunks": int(imported.get("chunks", 0)),
		"structured_marker_records": int(physical.get("structured", 0)),
		"knowledge_marker_chunks": int(physical.get("knowledge", 0)),
		"duplicate_physical_records": maxi(0, int(physical.get("structured", 0)) - 1),
		"duplicate_physical_chunks": maxi(0, int(physical.get("knowledge", 0)) - 1),
		"import_duration_ms": elapsed,
		"store": manager.stats(),
		"dedupe_contract_passed": int(physical.get("structured", 0)) <= 1 and int(physical.get("knowledge", 0)) <= 1
	}

func _probe_cross_source_duplicates(shared_count: int) -> Dictionary:
	var a := BENCH_ROOT.path_join("source_A.jsonl")
	var b := BENCH_ROOT.path_join("source_B.jsonl")
	_ensure_dir()
	var fa := FileAccess.open(a, FileAccess.WRITE)
	var fb := FileAccess.open(b, FileAccess.WRITE)
	if fa == null or fb == null:
		if fa != null: fa.close()
		if fb != null: fb.close()
		return {"ok": false, "error": "cannot create cross-source fixtures", "dedupe_contract_passed": false}
	for _i in range(shared_count):
		var shared := JSON.stringify({"fact": SHARED_MARKER, "value": 42, "language": "ru-en"})
		fa.store_line(shared)
		fb.store_line(shared)
	# Keep whole-file fingerprints different so file-level alias dedupe cannot
	# hide record-level behavior.
	fa.store_line(JSON.stringify({"fact": "AURORA_RECORD_DEDUP_UNIQUE_A", "value": "A"}))
	fb.store_line(JSON.stringify({"fact": "AURORA_RECORD_DEDUP_UNIQUE_B", "value": "B"}))
	fa.close()
	fb.close()

	var store := KnowledgeStoreScript.new()
	var txn := KnowledgeImportTransactionScript.new()
	var first := txn.import_file(store, a, {"imported_by": "record_dedup_diagnostic"})
	if not bool(first.get("ok", false)):
		return {"ok": false, "error": "source A import failed", "result": first, "dedupe_contract_passed": false}
	var after_a := _count_marker_occurrences("", SHARED_MARKER)
	var started := Time.get_ticks_usec()
	var second := txn.import_file(store, b, {"imported_by": "record_dedup_diagnostic"})
	var second_ms := _elapsed_ms(started)
	if not bool(second.get("ok", false)):
		return {"ok": false, "error": "source B import failed", "result": second, "dedupe_contract_passed": false}
	var after_b := _count_marker_occurrences("", SHARED_MARKER)
	var manager := KnowledgeManagerScript.new()
	var remove_started := Time.get_ticks_usec()
	var removed_a := manager.remove_source(a)
	var removal_ms := _elapsed_ms(remove_started)
	var after_remove_a := _count_marker_occurrences("", SHARED_MARKER)
	var b_survives := not store.search(SHARED_MARKER, 8).is_empty()
	return {
		"ok": true,
		"shared_records_per_source": shared_count,
		"source_a": {
			"records": int(first.get("records", 0)),
			"chunks": int(first.get("chunks", 0)),
			"fingerprint_sha256": str(first.get("fingerprint_sha256", ""))
		},
		"source_b": {
			"records": int(second.get("records", 0)),
			"chunks": int(second.get("chunks", 0)),
			"fingerprint_sha256": str(second.get("fingerprint_sha256", "")),
			"import_duration_ms": second_ms,
			"whole_file_duplicate": bool(second.get("duplicate", false)) or bool(second.get("skipped", false))
		},
		"shared_physical_after_a": after_a,
		"shared_physical_after_b": after_b,
		"structured_growth_from_b": int(after_b.get("structured", 0)) - int(after_a.get("structured", 0)),
		"knowledge_growth_from_b": int(after_b.get("knowledge", 0)) - int(after_a.get("knowledge", 0)),
		"remove_a": removed_a,
		"remove_a_duration_ms": removal_ms,
		"shared_physical_after_remove_a": after_remove_a,
		"source_b_shared_content_survives_removal_of_a": b_survives,
		"dedupe_contract_passed": (
			int(after_b.get("structured", 0)) == int(after_a.get("structured", 0))
			and int(after_b.get("knowledge", 0)) == int(after_a.get("knowledge", 0))
			and b_survives
		)
	}

func _count_marker_occurrences(_source_filter: String, marker: String) -> Dictionary:
	return {
		"structured": _count_marker_in_jsonl(KnowledgeStoreScript.STRUCTURED_PATH, marker),
		"knowledge": _count_marker_in_jsonl(KnowledgeStoreScript.DB_PATH, marker)
	}

func _count_marker_in_jsonl(path: String, marker: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var count := 0
	while not file.eof_reached():
		var line := file.get_line()
		if line.contains(marker):
			count += 1
	file.close()
	return count

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
	_remove_tree(BENCH_ROOT)
	_ensure_dir()

func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BENCH_ROOT))

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

func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0

func _emit(result: Dictionary, code: int) -> void:
	result["runtime"] = {
		"os": OS.get_name(),
		"godot": Engine.get_version_info(),
		"network_required": false,
		"external_runtime_required": false,
		"ollama_required": false
	}
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
