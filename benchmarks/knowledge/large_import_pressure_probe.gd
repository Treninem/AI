extends SceneTree

const KnowledgeDocumentImporterScript = preload("res://scripts/knowledge_document_importer.gd")
const AuroraJsonStreamReaderScript = preload("res://scripts/json_stream_reader.gd")
const KnowledgeSourceRegistryScript = preload("res://scripts/knowledge_source_registry.gd")
const KnowledgeStoreScript = preload("res://scripts/knowledge_store.gd")
const LargeJsonKnowledgeImporterScript = preload("res://scripts/large_json_knowledge_importer.gd")
const KnowledgeImportTransactionScript = preload("res://scripts/knowledge_import_transaction.gd")
const KnowledgeManagerScript = preload("res://scripts/knowledge_manager.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_PRESSURE_IMPORT_RESULT="
const BENCH_ROOT := "user://knowledge_pressure"
const MB := 1024 * 1024

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	var target_mb := maxi(1, int(OS.get_environment("AURORA_KNOWLEDGE_TARGET_MB")))
	var path := BENCH_ROOT.path_join("pressure_%dmb.jsonl" % target_mb)
	var generated := _generate_jsonl(path, target_mb * MB)
	if not bool(generated.get("ok", false)):
		_emit(generated, 2)
		return

	var store := KnowledgeStoreScript.new()
	var txn := KnowledgeImportTransactionScript.new()
	var import_started := Time.get_ticks_usec()
	var imported := txn.import_file(store, path, {
		"scope": "core_knowledge",
		"imported_by": "knowledge_large_pressure"
	})
	var import_ms := _elapsed_ms(import_started)
	if not bool(imported.get("ok", false)):
		_emit({
			"ok": false,
			"error": "pressure import failed",
			"dataset": generated,
			"import": imported,
			"import_duration_ms": import_ms,
			"runtime": _runtime_identity()
		}, 2)
		return

	var marker := str(generated.get("late_marker", ""))
	var search_started := Time.get_ticks_usec()
	var found := store.search(marker, 8)
	var search_ms := _elapsed_ms(search_started)
	var searchable := _contains_source(found, path)
	var registry := KnowledgeSourceRegistryScript.new()
	var registry_row := registry.record_for_source(path)
	var stats := KnowledgeManagerScript.new().stats()
	var dataset_bytes := int(generated.get("bytes", 0))
	var store_bytes := int(stats.get("bytes", 0))
	var streaming_ok := bool(imported.get("streaming", false))

	_emit({
		"ok": streaming_ok and searchable and not registry_row.is_empty(),
		"scenario": "large_import_pressure",
		"dataset": generated,
		"records": int(imported.get("records", generated.get("records", 0))),
		"chunks": int(imported.get("chunks", 0)),
		"streaming": streaming_ok,
		"stream_parser": str(imported.get("stream_parser", "")),
		"import_duration_ms": import_ms,
		"records_per_sec": _rate(float(generated.get("records", 0)), import_ms),
		"mb_per_sec": _rate(float(dataset_bytes) / float(MB), import_ms),
		"search_correctness_samples": 1,
		"search_once_ms": search_ms,
		"search_found": searchable,
		"store": stats,
		"store_size_bytes": store_bytes,
		"storage_amplification": (float(store_bytes) / float(dataset_bytes)) if dataset_bytes > 0 else 0.0,
		"source_registry_present": not registry_row.is_empty(),
		"fingerprint_sha256": str(registry_row.get("fingerprint_sha256", "")),
		"revision": int(registry_row.get("revision", 0)),
		"restart_contract": {
			"requires_new_process": true,
			"marker": marker,
			"source": path
		},
		"runtime": _runtime_identity()
	}, 0 if streaming_ok and searchable and not registry_row.is_empty() else 2)

func _generate_jsonl(path: String, target_bytes: int) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot create pressure dataset", "path": path}
	var filler := "aurora pressure local knowledge данные bounded memory retrieval " + "x".repeat(700)
	var count := 0
	var last_marker := ""
	while file.get_position() < target_bytes:
		last_marker = "AURORA_PRESSURE_RARE_%08d" % count
		file.store_line(JSON.stringify({
			"index": count,
			"kind": "fact",
			"title": "Aurora pressure %d" % count,
			"content": filler + " " + last_marker
		}))
		count += 1
	var size := file.get_position()
	file.close()
	return {
		"ok": true,
		"path": path,
		"format": "jsonl",
		"bytes": size,
		"size_mb": float(size) / float(MB),
		"records": count,
		"late_marker": last_marker,
		"deterministic": true
	}

func _contains_source(items: Array, source: String) -> bool:
	for item in items:
		if item is Dictionary and str(item.get("source", "")) == source:
			return true
	return false

func _rate(units: float, duration_ms: float) -> float:
	return units / maxf(0.001, duration_ms / 1000.0)

func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0

func _runtime_identity() -> Dictionary:
	return {
		"os": OS.get_name(),
		"godot": Engine.get_version_info(),
		"processor_count": OS.get_processor_count(),
		"processor_name": OS.get_processor_name(),
		"architecture": Engine.get_architecture_name(),
		"network_required": false,
		"external_runtime_required": false,
		"ollama_required": false,
		"physical_android_device": OS.get_name() == "Android"
	}

func _emit(result: Dictionary, code: int) -> void:
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
