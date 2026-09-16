extends SceneTree

const KnowledgeDocumentImporterScript = preload("res://scripts/knowledge_document_importer.gd")
const AuroraJsonStreamReaderScript = preload("res://scripts/json_stream_reader.gd")
const KnowledgeSourceRegistryScript = preload("res://scripts/knowledge_source_registry.gd")
const KnowledgeStoreScript = preload("res://scripts/knowledge_store.gd")
const LargeJsonKnowledgeImporterScript = preload("res://scripts/large_json_knowledge_importer.gd")
const KnowledgeImportTransactionScript = preload("res://scripts/knowledge_import_transaction.gd")
const KnowledgeManagerScript = preload("res://scripts/knowledge_manager.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_PRESSURE_REMOVE_RESULT="

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	var source := OS.get_environment("AURORA_KNOWLEDGE_EXPECT_SOURCE")
	var marker := OS.get_environment("AURORA_KNOWLEDGE_EXPECT_MARKER")
	if source.is_empty() or marker.is_empty():
		_emit({"ok": false, "error": "pressure removal source/marker missing"}, 2)
		return
	var manager := KnowledgeManagerScript.new()
	var started := Time.get_ticks_usec()
	var removed := manager.remove_source(source)
	var removal_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var store := KnowledgeStoreScript.new()
	var found := store.search(marker, 8)
	var registry_row := KnowledgeSourceRegistryScript.new().record_for_source(source)
	var ok := bool(removed.get("ok", false)) and found.is_empty() and registry_row.is_empty()
	_emit({
		"ok": ok,
		"scenario": "large_remove_pressure",
		"source": source,
		"removal_duration_ms": removal_ms,
		"removed": removed,
		"post_remove_searchable": not found.is_empty(),
		"source_registry_present": not registry_row.is_empty(),
		"store": manager.stats(),
		"runtime": _runtime_identity()
	}, 0 if ok else 2)

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
