extends SceneTree

# Explicit dependency order keeps the headless benchmark independent from the
# editor-generated global class cache, which is not reliable on fresh Windows
# runners. These are benchmark-side aliases only; production scripts are not
# modified.
const KnowledgeDocumentImporterScript = preload("res://scripts/knowledge_document_importer.gd")
const AuroraJsonStreamReaderScript = preload("res://scripts/json_stream_reader.gd")
const KnowledgeSourceRegistryScript = preload("res://scripts/knowledge_source_registry.gd")
const KnowledgeStoreScript = preload("res://scripts/knowledge_store.gd")
const LargeJsonKnowledgeImporterScript = preload("res://scripts/large_json_knowledge_importer.gd")
const KnowledgeImportTransactionScript = preload("res://scripts/knowledge_import_transaction.gd")
const KnowledgeManagerScript = preload("res://scripts/knowledge_manager.gd")
const AuroraLocalSemanticVectorizerScript = preload("res://scripts/local_semantic_vectorizer.gd")
const MemoryStoreScript = preload("res://scripts/memory_store.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_BENCH_RESULT="
const BENCH_ROOT := "user://knowledge_bench"
const MB := 1024 * 1024

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	var scenario := OS.get_environment("AURORA_KNOWLEDGE_SCENARIO").strip_edges()
	var target_mb := maxi(1, int(OS.get_environment("AURORA_KNOWLEDGE_TARGET_MB")))
	var count := maxi(1, int(OS.get_environment("AURORA_KNOWLEDGE_COUNT")))
	var source_kb := maxi(4, int(OS.get_environment("AURORA_KNOWLEDGE_SOURCE_KB")))
	var result: Dictionary
	match scenario:
		"import_jsonl": result = _scenario_import("jsonl", target_mb)
		"import_csv": result = _scenario_import("csv", target_mb)
		"import_txt": result = _scenario_import("txt", target_mb)
		"import_json": result = _scenario_import("json", maxi(9, target_mb))
		"restart_check": result = _scenario_restart_check()
		"dedupe_seed": result = _scenario_dedupe_seed(target_mb)
		"dedupe_reimport": result = _scenario_dedupe_reimport()
		"source_lifecycle": result = _scenario_source_lifecycle(target_mb)
		"rollback": result = _scenario_rollback(maxi(9, target_mb))
		"scaling_many_sources": result = _scenario_scaling_many_sources(count, source_kb)
		"semantic_memory": result = await _scenario_semantic_memory(count)
		"unicode_long_path": result = _scenario_unicode_long_path()
		"concurrent_import": result = _scenario_concurrent_import(target_mb)
		_:
			result = {"ok": false, "error": "unknown scenario", "scenario": scenario}
	result["scenario"] = scenario
	result["target_mb"] = target_mb
	result["requested_count"] = count
	result["runtime"] = _runtime_identity()
	result["static_memory_peak_bytes"] = int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
	_emit(result, 0 if bool(result.get("ok", false)) else 2)

func _scenario_import(format: String, target_mb: int) -> Dictionary:
	_reset_state()
	var ext := format
	var path := BENCH_ROOT.path_join("dataset_%s.%s" % [format, ext])
	var generated := _generate_dataset(path, format, target_mb * MB)
	if not bool(generated.get("ok", false)):
		return generated
	var store := KnowledgeStoreScript.new()
	var txn := KnowledgeImportTransactionScript.new()
	var started := Time.get_ticks_usec()
	var imported := txn.import_file(store, path, {"scope": "core_knowledge", "imported_by": "knowledge_stress_benchmark"})
	var import_ms := _elapsed_ms(started)
	if not bool(imported.get("ok", false)):
		return {"ok": false, "error": "import failed", "import": imported, "dataset": generated, "import_duration_ms": import_ms}
	if format in ["jsonl", "csv", "txt", "json"] and not bool(imported.get("streaming", false)):
		return {"ok": false, "error": "expected streaming path was not used", "import": imported, "dataset": generated}
	var searches := _search_matrix(store, str(generated.get("late_marker", "")), path)
	if not bool(searches.get("correct", false)):
		return {"ok": false, "error": "search correctness failed", "search": searches, "import": imported, "dataset": generated}
	var manager := KnowledgeManagerScript.new()
	var stats := manager.stats()
	return {
		"ok": true,
		"dataset": generated,
		"records": int(imported.get("records", generated.get("records", 0))),
		"chunks": int(imported.get("chunks", 0)),
		"import_duration_ms": import_ms,
		"records_per_sec": _rate(float(generated.get("records", 0)), import_ms),
		"mb_per_sec": _rate(float(generated.get("bytes", 0)) / float(MB), import_ms),
		"streaming": bool(imported.get("streaming", false)),
		"stream_parser": str(imported.get("stream_parser", "")),
		"store": stats,
		"store_size_bytes": int(stats.get("bytes", 0)),
		"search": searches,
		"restart_contract": {"requires_new_process": true, "marker": generated.get("late_marker", ""), "source": path},
		"external_ai_required": false
	}

func _scenario_restart_check() -> Dictionary:
	var marker := OS.get_environment("AURORA_KNOWLEDGE_EXPECT_MARKER")
	var source := OS.get_environment("AURORA_KNOWLEDGE_EXPECT_SOURCE")
	if marker.is_empty():
		return {"ok": false, "error": "restart marker missing"}
	var started := Time.get_ticks_usec()
	var store := KnowledgeStoreScript.new()
	var manager := KnowledgeManagerScript.new()
	var registry := KnowledgeSourceRegistryScript.new()
	var found := store.search(marker, 8)
	var elapsed := _elapsed_ms(started)
	var matched := _contains_source(found, source)
	var row := registry.record_for_source(source) if not source.is_empty() else {}
	return {
		"ok": matched and (source.is_empty() or not row.is_empty()),
		"restart_load_search_ms": elapsed,
		"found": found.size(),
		"source_registry_present": source.is_empty() or not row.is_empty(),
		"fingerprint_sha256": str(row.get("fingerprint_sha256", "")),
		"revision": int(row.get("revision", 0)),
		"store": manager.stats(),
		"process_restart_proof": true
	}

func _scenario_dedupe_seed(target_mb: int) -> Dictionary:
	_reset_state()
	var path := BENCH_ROOT.path_join("dedupe_original.jsonl")
	var generated := _generate_dataset(path, "jsonl", target_mb * MB)
	if not bool(generated.get("ok", false)):
		return generated
	var txn := KnowledgeImportTransactionScript.new()
	var result := txn.import_file(KnowledgeStoreScript.new(), path, {"imported_by": "knowledge_stress_benchmark"})
	return {
		"ok": bool(result.get("ok", false)) and not bool(result.get("skipped", false)),
		"dataset": generated,
		"source": path,
		"late_marker": generated.get("late_marker", ""),
		"fingerprint_sha256": result.get("fingerprint_sha256", ""),
		"revision": result.get("revision", 0)
	}

func _scenario_dedupe_reimport() -> Dictionary:
	var path := BENCH_ROOT.path_join("dedupe_original.jsonl")
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "dedupe seed missing"}
	var store := KnowledgeStoreScript.new()
	var manager := KnowledgeManagerScript.new()
	var txn := KnowledgeImportTransactionScript.new()
	var before := manager.stats()
	var same := txn.import_file(store, path, {"imported_by": "knowledge_stress_benchmark"})
	var after_same := manager.stats()
	var copy := BENCH_ROOT.path_join("копия базы с пробелами.jsonl")
	var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(copy))
	if copy_error != OK:
		return {"ok": false, "error": "cannot make dedupe copy", "code": copy_error}
	var renamed := txn.import_file(store, copy, {"imported_by": "knowledge_stress_benchmark"})
	var after_copy := manager.stats()
	var append := FileAccess.open(path, FileAccess.READ_WRITE)
	if append == null:
		return {"ok": false, "error": "cannot mutate dedupe source"}
	append.seek_end()
	append.store_line(JSON.stringify({"kind": "fact", "content": "AURORA_DEDUPE_CHANGED_REVISION_MARKER"}))
	append.close()
	var changed := txn.import_file(store, path, {"imported_by": "knowledge_stress_benchmark"})
	var changed_search := store.search("AURORA_DEDUPE_CHANGED_REVISION_MARKER", 5)
	var chunks_before := int(before.get("chunks", 0))
	var chunks_same := int(after_same.get("chunks", 0))
	var chunks_copy := int(after_copy.get("chunks", 0))
	var correct := bool(same.get("skipped", false)) and bool(same.get("duplicate", false))
	correct = correct and bool(renamed.get("skipped", false)) and bool(renamed.get("duplicate", false))
	correct = correct and chunks_before == chunks_same and chunks_before == chunks_copy
	correct = correct and int(changed.get("revision", 0)) >= 2 and not changed_search.is_empty()
	return {
		"ok": correct,
		"restart_between_imports": true,
		"same_path_duplicate": same,
		"renamed_duplicate": renamed,
		"changed_revision": changed,
		"chunks_before": chunks_before,
		"chunks_after_same": chunks_same,
		"chunks_after_copy": chunks_copy,
		"duplicate_explosion": chunks_copy != chunks_before
	}

func _scenario_source_lifecycle(target_mb: int) -> Dictionary:
	_reset_state()
	var target_bytes := maxi(64 * 1024, int(float(target_mb * MB) / 3.0))
	var store := KnowledgeStoreScript.new()
	var txn := KnowledgeImportTransactionScript.new()
	var paths: Array[String] = []
	var markers: Array[String] = []
	for label in ["A", "B", "C"]:
		var path := BENCH_ROOT.path_join("source_%s.txt" % label)
		var generated := _generate_dataset(path, "txt", target_bytes, "LIFECYCLE_%s" % label)
		if not bool(generated.get("ok", false)):
			return generated
		var result := txn.import_file(store, path, {"imported_by": "knowledge_stress_benchmark"})
		if not bool(result.get("ok", false)):
			return {"ok": false, "error": "lifecycle import failed", "label": label, "result": result}
		paths.append(path)
		markers.append(str(generated.get("late_marker", "")))
	var manager := KnowledgeManagerScript.new()
	var started := Time.get_ticks_usec()
	var removed := manager.remove_source(paths[1])
	var removal_ms := _elapsed_ms(started)
	var a_ok := _contains_source(store.search(markers[0], 5), paths[0])
	var b_gone := store.search(markers[1], 5).is_empty()
	var c_ok := _contains_source(store.search(markers[2], 5), paths[2])
	return {
		"ok": bool(removed.get("ok", false)) and a_ok and b_gone and c_ok,
		"removal_duration_ms": removal_ms,
		"removed": removed,
		"source_a_preserved": a_ok,
		"source_b_removed": b_gone,
		"source_c_preserved": c_ok,
		"orphan_registry": not KnowledgeSourceRegistryScript.new().record_for_source(paths[1]).is_empty(),
		"store": manager.stats()
	}

func _scenario_rollback(target_mb: int) -> Dictionary:
	_reset_state()
	var path := BENCH_ROOT.path_join("rollback_source.json")
	_ensure_bench_dir()
	var first := FileAccess.open(path, FileAccess.WRITE)
	if first == null:
		return {"ok": false, "error": "cannot create rollback source"}
	first.store_string('{"fact":"AURORA_ROLLBACK_STABLE_MARKER","description":"stable before failure"}')
	first.close()
	var store := KnowledgeStoreScript.new()
	var txn := KnowledgeImportTransactionScript.new()
	var initial := txn.import_file(store, path, {"imported_by": "knowledge_stress_benchmark"})
	if not bool(initial.get("ok", false)):
		return {"ok": false, "error": "initial rollback seed failed", "result": initial}
	var old_fp := str(initial.get("fingerprint_sha256", ""))
	var broken := FileAccess.open(path, FileAccess.WRITE)
	if broken == null:
		return {"ok": false, "error": "cannot overwrite rollback source"}
	broken.store_string('{"value":"AURORA_ROLLBACK_PARTIAL_MARKER","broken":[1,2,')
	var block := " ".repeat(MB)
	for _i in range(target_mb):
		broken.store_string(block)
	broken.store_string('}')
	broken.close()
	var started := Time.get_ticks_usec()
	var failed := txn.import_file(store, path, {"imported_by": "knowledge_stress_benchmark"})
	var rollback_ms := _elapsed_ms(started)
	var stable := not store.search("AURORA_ROLLBACK_STABLE_MARKER", 5).is_empty()
	var partial_gone := store.search("AURORA_ROLLBACK_PARTIAL_MARKER", 5).is_empty()
	var row := KnowledgeSourceRegistryScript.new().record_for_source(path)
	var fp_restored := str(row.get("fingerprint_sha256", "")) == old_fp
	return {
		"ok": not bool(failed.get("ok", false)) and str(failed.get("transaction", "")) == "rolled_back" and stable and partial_gone and fp_restored,
		"rollback_duration_ms": rollback_ms,
		"transaction": failed.get("transaction", ""),
		"transaction_mode": failed.get("transaction_mode", ""),
		"old_state_restored": stable,
		"partial_state_removed": partial_gone,
		"fingerprint_restored": fp_restored,
		"restart_contract": {"requires_new_process": true, "marker": "AURORA_ROLLBACK_STABLE_MARKER", "source": path}
	}

func _scenario_scaling_many_sources(count: int, source_kb: int) -> Dictionary:
	_reset_state()
	var store := KnowledgeStoreScript.new()
	var txn := KnowledgeImportTransactionScript.new()
	var started := Time.get_ticks_usec()
	var chunks := 0
	for i in range(count):
		var path := BENCH_ROOT.path_join("scale/source_%05d.txt" % i)
		var generated := _generate_dataset(path, "txt", source_kb * 1024, "SCALE_%05d" % i)
		if not bool(generated.get("ok", false)):
			return generated
		var result := txn.import_file(store, path, {"imported_by": "knowledge_stress_benchmark"})
		if not bool(result.get("ok", false)):
			return {"ok": false, "error": "scaling source import failed", "index": i, "result": result}
		chunks += int(result.get("chunks", 0))
	var elapsed := _elapsed_ms(started)
	var stats := KnowledgeManagerScript.new().stats()
	return {
		"ok": int(stats.get("sources", 0)) == count,
		"source_count": count,
		"source_size_kb": source_kb,
		"chunks": chunks,
		"import_duration_ms": elapsed,
		"sources_per_sec": _rate(float(count), elapsed),
		"store_size_bytes": int(stats.get("bytes", 0)),
		"store": stats
	}

func _scenario_semantic_memory(count: int) -> Dictionary:
	_reset_state()
	var memory := MemoryStoreScript.new()
	root.add_child(memory)
	await process_frame
	var write_started := Time.get_ticks_usec()
	for i in range(count):
		var content := "AuroraFox memory benchmark record %d калибровка локальная память token_%d" % [i, i]
		memory.learn(content, "knowledge_memory_benchmark", 0.65, 0.85, "benchmark")
	var write_ms := _elapsed_ms(write_started)
	var index_started := Time.get_ticks_usec()
	var status := memory.reindex_semantic()
	var index_ms := _elapsed_ms(index_started)
	var query_started := Time.get_ticks_usec()
	var found := memory.search_knowledge("локальная калибровка token_%d" % (count - 1), 8)
	var query_ms := _elapsed_ms(query_started)
	var self_reliant := str(status.get("provider", "")) == "aurorafox_local_vector"
	self_reliant = self_reliant and not bool(status.get("network_required", true))
	self_reliant = self_reliant and not bool(status.get("external_runtime_required", true))
	self_reliant = self_reliant and not bool(status.get("ollama_required", true))
	memory.queue_free()
	await process_frame
	var restart_started := Time.get_ticks_usec()
	var restarted := MemoryStoreScript.new()
	root.add_child(restarted)
	await process_frame
	var restart_ms := _elapsed_ms(restart_started)
	var restart_found := restarted.search_knowledge("token_%d" % (count - 1), 8)
	var restart_status := restarted.semantic_status()
	var ok := self_reliant and not found.is_empty() and not restart_found.is_empty()
	ok = ok and int(restart_status.get("knowledge_items", 0)) == mini(count, MemoryStoreScript.MAX_KNOWLEDGE)
	restarted.queue_free()
	await process_frame
	return {
		"ok": ok,
		"records_requested": count,
		"records_persisted": int(restart_status.get("knowledge_items", 0)),
		"write_duration_ms": write_ms,
		"records_per_sec": _rate(float(count), write_ms),
		"semantic_index_build_ms": index_ms,
		"search_latency_ms": query_ms,
		"restart_load_ms": restart_ms,
		"semantic_status": status,
		"network_required": status.get("network_required", true),
		"external_runtime_required": status.get("external_runtime_required", true),
		"ollama_required": status.get("ollama_required", true),
		"restart_retrieval_ok": not restart_found.is_empty()
	}

func _scenario_unicode_long_path() -> Dictionary:
	_reset_state()
	var nested := BENCH_ROOT
	for i in range(7):
		nested = nested.path_join("длинная папка %02d с пробелами AuroraFox" % i)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(nested))
	var path := nested.path_join("База знаний — проверка Unicode 你好 данные.txt")
	var generated := _generate_dataset(path, "txt", 96 * 1024, "UNICODE_PATH")
	if not bool(generated.get("ok", false)):
		return generated
	var store := KnowledgeStoreScript.new()
	var txn := KnowledgeImportTransactionScript.new()
	var imported := txn.import_file(store, path, {"imported_by": "knowledge_stress_benchmark"})
	var found := store.search(str(generated.get("late_marker", "")), 5)
	var removed := KnowledgeManagerScript.new().remove_source(path)
	return {
		"ok": bool(imported.get("ok", false)) and _contains_source(found, path) and bool(removed.get("ok", false)),
		"path_chars": path.length(),
		"unicode": true,
		"spaces": true,
		"import": imported,
		"remove": removed
	}

func _scenario_concurrent_import(target_mb: int) -> Dictionary:
	_reset_state()
	var a := BENCH_ROOT.path_join("concurrent_A.jsonl")
	var b := BENCH_ROOT.path_join("concurrent_B.jsonl")
	var ga := _generate_dataset(a, "jsonl", maxi(128 * 1024, target_mb * MB), "CONCURRENT_A")
	var gb := _generate_dataset(b, "jsonl", maxi(128 * 1024, target_mb * MB), "CONCURRENT_B")
	if not bool(ga.get("ok", false)) or not bool(gb.get("ok", false)):
		return {"ok": false, "error": "concurrency fixtures failed"}
	var ta := Thread.new()
	var tb := Thread.new()
	var started := Time.get_ticks_usec()
	var ea := ta.start(func(): return KnowledgeImportTransactionScript.new().import_file(KnowledgeStoreScript.new(), a, {"imported_by": "knowledge_stress_concurrency"}))
	var eb := tb.start(func(): return KnowledgeImportTransactionScript.new().import_file(KnowledgeStoreScript.new(), b, {"imported_by": "knowledge_stress_concurrency"}))
	if ea != OK or eb != OK:
		return {"ok": false, "error": "thread start failed", "thread_a": ea, "thread_b": eb}
	var ra = ta.wait_to_finish()
	var rb = tb.wait_to_finish()
	var elapsed := _elapsed_ms(started)
	var store := KnowledgeStoreScript.new()
	var a_ok := _contains_source(store.search(str(ga.get("late_marker", "")), 8), a)
	var b_ok := _contains_source(store.search(str(gb.get("late_marker", "")), 8), b)
	return {
		"ok": ra is Dictionary and rb is Dictionary and bool(ra.get("ok", false)) and bool(rb.get("ok", false)) and a_ok and b_ok,
		"duration_ms": elapsed,
		"thread_a": ra,
		"thread_b": rb,
		"source_a_searchable": a_ok,
		"source_b_searchable": b_ok,
		"parallel_attempted": true
	}

func _generate_dataset(path: String, format: String, target_bytes: int, marker_prefix := "DATA") -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot create dataset", "path": path}
	var filler := "aurora benchmark local knowledge данные calibration memory retrieval " + "x".repeat(700)
	var count := 0
	var last_marker := ""
	if format == "csv":
		file.store_line("index,kind,title,content")
	elif format == "json":
		file.store_string("[\n")
	while file.get_position() < target_bytes:
		last_marker = "AURORA_%s_RARE_%08d" % [marker_prefix, count]
		if format == "jsonl":
			file.store_line(JSON.stringify({"index": count, "kind": "fact", "title": "Aurora benchmark %d" % count, "content": filler + " " + last_marker}))
		elif format == "csv":
			file.store_csv_line(PackedStringArray([str(count), "fact", "Aurora benchmark %d" % count, filler + " " + last_marker]), ",")
		elif format == "txt":
			file.store_string("Aurora benchmark paragraph %d %s %s\n\n" % [count, filler, last_marker])
		elif format == "json":
			if count > 0:
				file.store_string(",\n")
			file.store_string(JSON.stringify({"index": count, "kind": "fact", "title": "Aurora benchmark %d" % count, "content": filler + " " + last_marker}))
		else:
			file.close()
			return {"ok": false, "error": "unsupported generator format", "format": format}
		count += 1
	if format == "json":
		file.store_string("\n]\n")
	var size := file.get_position()
	file.close()
	return {"ok": true, "path": path, "format": format, "bytes": size, "size_mb": float(size) / float(MB), "records": count, "late_marker": last_marker, "deterministic": true}

func _search_matrix(store, marker: String, expected_source: String) -> Dictionary:
	var cases := [
		{"name": "empty", "query": "", "require": false},
		{"name": "exact_rare", "query": marker, "require": true},
		{"name": "common", "query": "aurora benchmark", "require": true},
		{"name": "multiple_tokens", "query": "local knowledge calibration", "require": true},
		{"name": "russian", "query": "данные память", "require": true},
		{"name": "mixed_ru_en", "query": "Aurora данные retrieval", "require": true},
		{"name": "very_long", "query": "aurora данные ".repeat(80), "require": false},
		{"name": "malformed", "query": "\\\"'[]{}()??? ***", "require": false}
	]
	var reports: Array = []
	var correct := true
	for case in cases:
		var samples: Array[float] = []
		var last: Array = []
		for _i in range(5):
			var started := Time.get_ticks_usec()
			last = store.search(str(case.get("query", "")), 8)
			samples.append(_elapsed_ms(started))
		var required := bool(case.get("require", false))
		var found_expected := not required or _contains_source(last, expected_source)
		if required and not found_expected:
			correct = false
		reports.append({
			"name": case.get("name", ""),
			"p50_ms": _percentile(samples, 0.50),
			"p95_ms": _percentile(samples, 0.95),
			"p99_ms": _percentile(samples, 0.99),
			"samples": samples.size(),
			"result_count": last.size(),
			"correct": found_expected
		})
	return {"correct": correct, "cases": reports}

func _contains_source(items: Array, source: String) -> bool:
	if source.is_empty():
		return not items.is_empty()
	for item in items:
		if item is Dictionary and str(item.get("source", "")) == source:
			return true
	return false

func _percentile(values: Array[float], p: float) -> float:
	if values.is_empty():
		return 0.0
	var copy := values.duplicate()
	copy.sort()
	var index := clampi(int(ceil(p * float(copy.size()))) - 1, 0, copy.size() - 1)
	return float(copy[index])

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

func _reset_state() -> void:
	for path in [
		KnowledgeStoreScript.DB_PATH,
		KnowledgeStoreScript.STRUCTURED_PATH,
		KnowledgeSourceRegistryScript.REGISTRY_PATH,
		KnowledgeImportTransactionScript.DB_BACKUP,
		KnowledgeImportTransactionScript.STRUCTURED_BACKUP,
		KnowledgeImportTransactionScript.REGISTRY_BACKUP,
		MemoryStoreScript.MEMORY_PATH,
		MemoryStoreScript.KNOWLEDGE_PATH,
		MemoryStoreScript.VECTOR_PATH,
		KnowledgeStoreScript.DB_PATH + ".filter.tmp",
		KnowledgeStoreScript.STRUCTURED_PATH + ".filter.tmp",
		KnowledgeStoreScript.DB_PATH + ".rollback.tmp",
		KnowledgeStoreScript.STRUCTURED_PATH + ".rollback.tmp"
	]:
		_remove_file(str(path))
	_ensure_bench_dir()

func _ensure_bench_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BENCH_ROOT))

func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _emit(result: Dictionary, code: int) -> void:
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
