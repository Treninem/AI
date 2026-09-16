extends SceneTree

const REPORT_PREFIX := "AURORA_KNOWLEDGE_BENCHMARK_JSON="
const BENCH_ROOT := "user://knowledge_benchmark"
const DB_PATH := "user://knowledge/knowledge.jsonl"
const STRUCTURED_PATH := "user://knowledge/structured.jsonl"
const REGISTRY_PATH := KnowledgeSourceRegistry.REGISTRY_PATH

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := _parse_args()
	var scenario := str(args.get("scenario", "import_search"))
	var report: Dictionary
	match scenario:
		"import_search":
			report = _scenario_import_search(args)
		"monolithic_json":
			report = _scenario_monolithic_json(args)
		"dedup_removal":
			report = _scenario_dedup_removal(args)
		"rollback":
			report = _scenario_rollback(args)
		"restart_prepare":
			report = _scenario_restart_prepare(args)
		"restart_verify":
			report = _scenario_restart_verify(args)
		_:
			report = _base_report(args, scenario)
			report["ok"] = false
			report["errors"] = ["unknown scenario: %s" % scenario]
	print(REPORT_PREFIX + JSON.stringify(report))
	quit(0 if bool(report.get("ok", false)) else 2)

func _parse_args() -> Dictionary:
	var out := {}
	for raw in OS.get_cmdline_user_args():
		var token := str(raw)
		if not token.begins_with("--"):
			continue
		var split := token.find("=")
		if split < 0:
			out[token.substr(2)] = true
			continue
		out[token.substr(2, split - 2)] = token.substr(split + 1)
	return out

func _int_arg(args: Dictionary, key: String, fallback: int) -> int:
	var value := str(args.get(key, fallback))
	return int(value) if value.is_valid_int() else fallback

func _bool_arg(args: Dictionary, key: String, fallback := false) -> bool:
	var value := str(args.get(key, str(fallback))).to_lower()
	return value in ["1", "true", "yes", "on"]

func _source_path(args: Dictionary, default_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BENCH_ROOT))
	var name := str(args.get("source-name", default_name)).get_file()
	if name.is_empty():
		name = default_name
	return BENCH_ROOT.path_join(name)

func _base_report(args: Dictionary, scenario: String) -> Dictionary:
	return {
		"schema_version": 1,
		"scenario": scenario,
		"case": str(args.get("case", scenario)),
		"ok": true,
		"errors": [],
		"format": str(args.get("format", "jsonl")),
		"record_count": _int_arg(args, "records", 0),
		"payload_bytes": _int_arg(args, "payload-bytes", 0),
		"target_mb": _int_arg(args, "target-mb", 0),
		"scaling_point": _bool_arg(args, "scaling-point", false),
		"platform": {
			"os": OS.get_name(),
			"engine": Engine.get_version_info(),
			"processor_count": OS.get_processor_count(),
			"locale": OS.get_locale(),
		},
		"self_reliance": _semantic_self_reliance(),
	}

func _semantic_self_reliance() -> Dictionary:
	var memory := MemoryStore.new()
	var status := memory.semantic_status()
	memory.free()
	return {
		"provider": str(status.get("provider", "")),
		"network_required": bool(status.get("network_required", true)),
		"external_runtime_required": bool(status.get("external_runtime_required", true)),
		"ollama_required": bool(status.get("ollama_required", true)),
		"local_fallback": str(status.get("local_fallback", "")),
	}

func _scenario_import_search(args: Dictionary) -> Dictionary:
	var report := _base_report(args, "import_search")
	var errors: Array = report["errors"]
	var records := maxi(1, _int_arg(args, "records", 1000))
	var payload_bytes := maxi(0, _int_arg(args, "payload-bytes", 512))
	var format := str(args.get("format", "jsonl")).to_lower()
	var source := _source_path(args, "dataset.%s" % format)
	var marker := _rare_marker(records)
	var generated := _generate_dataset(source, format, records, payload_bytes)
	if not bool(generated.get("ok", false)):
		return _fail_report(report, str(generated.get("error", "dataset generation failed")))
	report["dataset_size_bytes"] = _file_size(source)
	report["record_count"] = records

	var store := KnowledgeStore.new()
	var transaction := KnowledgeImportTransaction.new()
	var manager := KnowledgeManager.new()
	var registry := KnowledgeSourceRegistry.new()

	var import_started := Time.get_ticks_usec()
	var imported := transaction.import_file(store, source, {
		"scope": "core_knowledge",
		"imported_by": "large_knowledge_performance_benchmark"
	})
	var import_ms := _elapsed_ms(import_started)
	if not bool(imported.get("ok", false)):
		errors.append("import failed: %s" % JSON.stringify(imported))
		report["ok"] = false
	report["import_duration_ms"] = import_ms
	report["chunk_count"] = int(imported.get("chunks", 0))
	report["structured_record_count"] = int(imported.get("records", 0))
	report["streaming"] = bool(imported.get("streaming", false))
	report["transaction"] = str(imported.get("transaction", ""))
	report["fingerprint_sha256"] = str(imported.get("fingerprint_sha256", ""))
	report["records_per_sec"] = _throughput(float(records), import_ms)
	report["mb_per_sec"] = _throughput(float(report["dataset_size_bytes"]) / float(1024 * 1024), import_ms)

	if bool(imported.get("ok", false)):
		var duplicate_started := Time.get_ticks_usec()
		var duplicate := transaction.import_file(store, source, {
			"scope": "core_knowledge",
			"imported_by": "large_knowledge_performance_benchmark"
		})
		report["duplicate_import_duration_ms"] = _elapsed_ms(duplicate_started)
		report["duplicate_count"] = 1 if bool(duplicate.get("skipped", false)) and str(duplicate.get("transaction", "")) == "skipped_duplicate" else 0
		report["duplicate_result"] = {
			"ok": bool(duplicate.get("ok", false)),
			"skipped": bool(duplicate.get("skipped", false)),
			"transaction": str(duplicate.get("transaction", "")),
		}
		if int(report["duplicate_count"]) != 1:
			errors.append("identical reimport was not suppressed")
			report["ok"] = false

		var search_report := _measure_search(store, source, marker)
		report["search"] = search_report
		if not bool(search_report.get("correct", false)):
			errors.append("search correctness gate failed")
			report["ok"] = false

		var stats := manager.stats()
		report["resulting_store_size_bytes"] = int(stats.get("bytes", 0))
		report["knowledge_store_bytes"] = _file_size(DB_PATH)
		report["structured_store_bytes"] = _file_size(STRUCTURED_PATH)
		report["registry_size_bytes"] = _file_size(REGISTRY_PATH)
		report["registry_source_count"] = registry.sources().size()
		report["storage_amplification"] = _safe_div(float(report["resulting_store_size_bytes"]), float(maxi(1, int(report["dataset_size_bytes"]))))

		var remove_started := Time.get_ticks_usec()
		var removed := manager.remove_source(source)
		report["source_removal_time_ms"] = _elapsed_ms(remove_started)
		report["source_removal"] = removed
		if not bool(removed.get("ok", false)):
			errors.append("source removal failed")
			report["ok"] = false
		elif not store.search(marker, 5).is_empty():
			errors.append("removed source remains searchable")
			report["ok"] = false
	_cleanup_source_file(source)
	return report

func _scenario_monolithic_json(args: Dictionary) -> Dictionary:
	var report := _base_report(args, "monolithic_json")
	var errors: Array = report["errors"]
	var records := maxi(1, _int_arg(args, "records", 2300))
	var payload_bytes := maxi(1, _int_arg(args, "payload-bytes", 4096))
	var source := _source_path(args, "monolithic.json")
	var generated := _generate_monolithic_json(source, records, payload_bytes)
	if not bool(generated.get("ok", false)):
		return _fail_report(report, str(generated.get("error", "monolithic generation failed")))
	report["dataset_size_bytes"] = _file_size(source)
	report["record_count"] = records
	var store := KnowledgeStore.new()
	var transaction := KnowledgeImportTransaction.new()
	var started := Time.get_ticks_usec()
	var imported := transaction.import_file(store, source, {
		"scope": "core_knowledge",
		"imported_by": "large_knowledge_performance_benchmark"
	})
	report["import_duration_ms"] = _elapsed_ms(started)
	report["chunk_count"] = int(imported.get("chunks", 0))
	report["structured_record_count"] = int(imported.get("records", 0))
	report["streaming"] = bool(imported.get("streaming", false))
	report["stream_parser"] = str(imported.get("stream_parser", ""))
	report["memory_model"] = str(imported.get("memory_model", ""))
	report["bytes_read"] = int(imported.get("bytes_read", 0))
	report["records_per_sec"] = _throughput(float(records), float(report["import_duration_ms"]))
	report["mb_per_sec"] = _throughput(float(report["dataset_size_bytes"]) / float(1024 * 1024), float(report["import_duration_ms"]))
	if not bool(imported.get("ok", false)):
		errors.append("monolithic JSON import failed: %s" % JSON.stringify(imported))
	elif not bool(imported.get("streaming", false)) or str(imported.get("stream_parser", "")) != "aurora_json_stream_v1":
		errors.append("large monolithic JSON bypassed the streaming parser")
	elif store.search(_rare_marker(records), 5).is_empty():
		errors.append("late monolithic JSON marker is not searchable")
	var manager := KnowledgeManager.new()
	var stats := manager.stats()
	report["resulting_store_size_bytes"] = int(stats.get("bytes", 0))
	var remove_started := Time.get_ticks_usec()
	var removed := manager.remove_source(source)
	report["source_removal_time_ms"] = _elapsed_ms(remove_started)
	report["source_removal"] = removed
	if not bool(removed.get("ok", false)):
		errors.append("monolithic source removal failed")
	report["ok"] = errors.is_empty()
	_cleanup_source_file(source)
	return report

func _scenario_dedup_removal(args: Dictionary) -> Dictionary:
	var report := _base_report(args, "dedup_removal")
	var errors: Array = report["errors"]
	var records := maxi(10, _int_arg(args, "records", 400))
	var payload_bytes := maxi(0, _int_arg(args, "payload-bytes", 512))
	var store := KnowledgeStore.new()
	var transaction := KnowledgeImportTransaction.new()
	var manager := KnowledgeManager.new()
	var registry := KnowledgeSourceRegistry.new()
	var sources := [
		BENCH_ROOT.path_join("source_A.jsonl"),
		BENCH_ROOT.path_join("source_B.jsonl"),
		BENCH_ROOT.path_join("source_C.jsonl"),
	]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BENCH_ROOT))
	for i in range(sources.size()):
		var generated := _generate_dataset(str(sources[i]), "jsonl", records, payload_bytes, "SRC_%s" % char(65 + i))
		if not bool(generated.get("ok", false)):
			return _fail_report(report, "cannot generate dedup fixture")
		var imported := transaction.import_file(store, str(sources[i]), {"imported_by": "large_knowledge_performance_benchmark"})
		if not bool(imported.get("ok", false)):
			errors.append("source %d import failed" % i)

	var alias := BENCH_ROOT.path_join("source_B_copy.jsonl")
	var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(str(sources[1])), ProjectSettings.globalize_path(alias))
	if copy_error != OK:
		errors.append("cannot create byte-identical alias")
	else:
		var duplicate_started := Time.get_ticks_usec()
		var duplicate := transaction.import_file(store, alias, {"imported_by": "large_knowledge_performance_benchmark"})
		report["duplicate_import_duration_ms"] = _elapsed_ms(duplicate_started)
		report["duplicate_count"] = 1 if bool(duplicate.get("skipped", false)) else 0
		report["alias_registered"] = bool(duplicate.get("skipped", false)) and str(duplicate.get("alias", "")) == alias
		if int(report["duplicate_count"]) != 1:
			errors.append("byte-identical copy was not deduplicated")

	var b_marker := _rare_marker(records, "SRC_B")
	var a_marker := _rare_marker(records, "SRC_A")
	var c_marker := _rare_marker(records, "SRC_C")
	var removal_started := Time.get_ticks_usec()
	var removed := manager.remove_source(str(sources[1]))
	report["source_removal_time_ms"] = _elapsed_ms(removal_started)
	report["source_removal"] = removed
	if not bool(removed.get("ok", false)):
		errors.append("B removal failed")
	if not store.search(b_marker, 5).is_empty():
		errors.append("B data survived source removal")
	if store.search(a_marker, 5).is_empty():
		errors.append("A data was damaged by B removal")
	if store.search(c_marker, 5).is_empty():
		errors.append("C data was damaged by B removal")
	var stats := registry.stats()
	report["registry_after_removal"] = stats
	report["resulting_store_size_bytes"] = int(manager.stats().get("bytes", 0))
	report["ok"] = errors.is_empty()
	for source in sources:
		manager.remove_source(str(source))
		_cleanup_source_file(str(source))
	manager.remove_source(alias)
	_cleanup_source_file(alias)
	return report

func _scenario_rollback(args: Dictionary) -> Dictionary:
	var report := _base_report(args, "rollback")
	var errors: Array = report["errors"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BENCH_ROOT))
	var source := _source_path(args, "rollback.json")
	var store := KnowledgeStore.new()
	var transaction := KnowledgeImportTransaction.new()
	var registry := KnowledgeSourceRegistry.new()
	var stable := FileAccess.open(source, FileAccess.WRITE)
	if stable == null:
		return _fail_report(report, "cannot create rollback baseline")
	stable.store_string('{"fact":"AURORA_ROLLBACK_OLD_MARKER","description":"stable baseline"}')
	stable.close()
	var initial := transaction.import_file(store, source, {"imported_by": "large_knowledge_performance_benchmark"})
	if not bool(initial.get("ok", false)):
		return _fail_report(report, "cannot import rollback baseline")
	var old_fingerprint := str(initial.get("fingerprint_sha256", ""))
	var broken := FileAccess.open(source, FileAccess.WRITE)
	if broken == null:
		return _fail_report(report, "cannot overwrite rollback source")
	broken.store_string('{"fact":"AURORA_ROLLBACK_PARTIAL_MARKER","broken":[1,2,')
	var requested := maxi(9 * 1024 * 1024, _int_arg(args, "payload-bytes", 9 * 1024 * 1024))
	var block := " ".repeat(1024 * 1024)
	var remaining := requested
	while remaining > 0:
		var count := mini(remaining, block.length())
		broken.store_string(block.substr(0, count))
		remaining -= count
	broken.store_string("}")
	broken.close()
	report["dataset_size_bytes"] = _file_size(source)
	var started := Time.get_ticks_usec()
	var failed := transaction.import_file(store, source, {"imported_by": "large_knowledge_performance_benchmark"})
	report["rollback_time_ms"] = _elapsed_ms(started)
	report["transaction"] = str(failed.get("transaction", ""))
	report["transaction_mode"] = str(failed.get("transaction_mode", ""))
	if bool(failed.get("ok", false)):
		errors.append("malformed replacement unexpectedly committed")
	if str(failed.get("transaction", "")) != "rolled_back":
		errors.append("failed import did not roll back")
	if store.search("AURORA_ROLLBACK_OLD_MARKER", 5).is_empty():
		errors.append("old knowledge was not restored")
	if not store.search("AURORA_ROLLBACK_PARTIAL_MARKER", 5).is_empty():
		errors.append("partial knowledge leaked after rollback")
	var record := registry.record_for_source(source)
	if str(record.get("fingerprint_sha256", "")) != old_fingerprint:
		errors.append("registry fingerprint was not restored")
	for journal in [KnowledgeImportTransaction.DB_BACKUP, KnowledgeImportTransaction.STRUCTURED_BACKUP, KnowledgeImportTransaction.REGISTRY_BACKUP]:
		if FileAccess.file_exists(journal):
			errors.append("rollback journal leaked: %s" % journal)
	report["fingerprint_sha256"] = old_fingerprint
	report["resulting_store_size_bytes"] = int(KnowledgeManager.new().stats().get("bytes", 0))
	report["ok"] = errors.is_empty()
	KnowledgeManager.new().remove_source(source)
	_cleanup_source_file(source)
	return report

func _scenario_restart_prepare(args: Dictionary) -> Dictionary:
	var report := _base_report(args, "restart_prepare")
	var records := maxi(10, _int_arg(args, "records", 1000))
	var payload_bytes := maxi(0, _int_arg(args, "payload-bytes", 1024))
	var source := _source_path(args, "restart_source.jsonl")
	var generated := _generate_dataset(source, "jsonl", records, payload_bytes, "RESTART")
	if not bool(generated.get("ok", false)):
		return _fail_report(report, "cannot generate restart source")
	var store := KnowledgeStore.new()
	var transaction := KnowledgeImportTransaction.new()
	var started := Time.get_ticks_usec()
	var imported := transaction.import_file(store, source, {"imported_by": "large_knowledge_performance_benchmark"})
	report["import_duration_ms"] = _elapsed_ms(started)
	report["dataset_size_bytes"] = _file_size(source)
	report["chunk_count"] = int(imported.get("chunks", 0))
	report["fingerprint_sha256"] = str(imported.get("fingerprint_sha256", ""))
	report["source"] = source
	report["restart_marker"] = _rare_marker(records, "RESTART")
	report["resulting_store_size_bytes"] = int(KnowledgeManager.new().stats().get("bytes", 0))
	if not bool(imported.get("ok", false)):
		return _fail_report(report, "restart preparation import failed")
	return report

func _scenario_restart_verify(args: Dictionary) -> Dictionary:
	var report := _base_report(args, "restart_verify")
	var errors: Array = report["errors"]
	var records := maxi(10, _int_arg(args, "records", 1000))
	var source := _source_path(args, "restart_source.jsonl")
	var marker := _rare_marker(records, "RESTART")
	var started := Time.get_ticks_usec()
	var store := KnowledgeStore.new()
	var registry := KnowledgeSourceRegistry.new()
	var manager := KnowledgeManager.new()
	var found := store.search(marker, 5)
	var record := registry.record_for_source(source)
	var stats := manager.stats()
	report["restart_load_time_ms"] = _elapsed_ms(started)
	report["fingerprint_sha256"] = str(record.get("fingerprint_sha256", ""))
	report["chunk_count"] = int(record.get("chunks", 0))
	report["registry_source_count"] = int(registry.stats().get("sources", 0))
	report["resulting_store_size_bytes"] = int(stats.get("bytes", 0))
	if found.is_empty():
		errors.append("search after process restart did not find imported marker")
	if record.is_empty():
		errors.append("source registry did not survive process restart")
	if int(stats.get("chunks", 0)) <= 0:
		errors.append("knowledge count did not survive process restart")
	report["ok"] = errors.is_empty()
	return report

func _generate_dataset(path: String, format: String, records: int, payload_bytes: int, label := "DATA") -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot create %s" % path}
	var payload := "x".repeat(payload_bytes)
	if format == "csv":
		file.store_csv_line(PackedStringArray(["id", "common", "mixed", "marker", "content"]), ",")
	for i in range(records):
		var marker := _rare_marker(records, label) if i == records - 1 else "%s_RECORD_%d" % [label, i]
		match format:
			"jsonl", "ndjson":
				file.store_line(JSON.stringify({
					"id": i,
					"common": "AURORA_COMMON_TOKEN",
					"mixed": "русский english knowledge",
					"marker": marker,
					"content": "record_%d %s" % [i, payload],
				}))
			"csv":
				file.store_csv_line(PackedStringArray([
					str(i), "AURORA_COMMON_TOKEN", "русский english knowledge", marker,
					"record_%d %s" % [i, payload]
				]), ",")
			"txt":
				file.store_line("%s AURORA_COMMON_TOKEN русский english knowledge record_%d %s" % [marker, i, payload])
			_:
				file.close()
				return {"ok": false, "error": "unsupported generated format: %s" % format}
	file.close()
	return {"ok": true, "bytes": _file_size(path)}

func _generate_monolithic_json(path: String, records: int, payload_bytes: int) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot create monolithic JSON"}
	var payload := "m".repeat(payload_bytes)
	file.store_string("[\n")
	for i in range(records):
		if i > 0:
			file.store_string(",\n")
		file.store_string(JSON.stringify({
			"id": i,
			"common": "AURORA_COMMON_TOKEN",
			"mixed": "русский english knowledge",
			"marker": _rare_marker(records) if i == records - 1 else "MONO_%d" % i,
			"content": payload,
		}))
	file.store_string("\n]\n")
	file.close()
	return {"ok": true, "bytes": _file_size(path)}

func _measure_search(store: KnowledgeStore, source: String, marker: String) -> Dictionary:
	var long_query := "unlikely_" + "q".repeat(4096)
	var cases := [
		{"name": "empty", "query": "", "expect": "empty"},
		{"name": "exact_rare", "query": marker, "expect": "source"},
		{"name": "common", "query": "AURORA_COMMON_TOKEN", "expect": "nonempty"},
		{"name": "rare", "query": marker.to_lower(), "expect": "source"},
		{"name": "multiple_tokens", "query": "AURORA_COMMON_TOKEN english", "expect": "nonempty"},
		{"name": "mixed_ru_en", "query": "русский english", "expect": "nonempty"},
		{"name": "very_long", "query": long_query, "expect": "empty"},
		{"name": "malformed", "query": "[]{}\\/::@@@", "expect": "empty"},
	]
	var all_ms: Array = []
	var details: Array = []
	var correct := true
	for definition in cases:
		var latencies: Array = []
		var last_result: Array = []
		for _repeat in range(5):
			var started := Time.get_ticks_usec()
			last_result = store.search(str(definition.get("query", "")), 8)
			latencies.append(_elapsed_ms(started))
			all_ms.append(latencies[-1])
		var expectation := str(definition.get("expect", ""))
		var case_ok := true
		if expectation == "empty":
			case_ok = last_result.is_empty()
		elif expectation == "nonempty":
			case_ok = not last_result.is_empty()
		elif expectation == "source":
			case_ok = _results_include_source(last_result, source)
		correct = correct and case_ok
		details.append({
			"name": str(definition.get("name", "")),
			"correct": case_ok,
			"result_count": last_result.size(),
			"p50_ms": _percentile(latencies, 0.50),
			"p95_ms": _percentile(latencies, 0.95),
			"p99_ms": _percentile(latencies, 0.99),
		})
	return {
		"correct": correct,
		"p50_ms": _percentile(all_ms, 0.50),
		"p95_ms": _percentile(all_ms, 0.95),
		"p99_ms": _percentile(all_ms, 0.99),
		"samples": all_ms.size(),
		"cases": details,
	}

func _results_include_source(results: Array, source: String) -> bool:
	for value in results:
		if value is Dictionary and str(value.get("source", "")) == source:
			return true
	return false

func _percentile(values: Array, percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	var index := int(ceil(percentile * float(ordered.size() - 1)))
	index = clampi(index, 0, ordered.size() - 1)
	return snappedf(float(ordered[index]), 0.001)

func _elapsed_ms(start_usec: int) -> float:
	return snappedf(float(Time.get_ticks_usec() - start_usec) / 1000.0, 0.001)

func _throughput(amount: float, duration_ms: float) -> float:
	if duration_ms <= 0.0:
		return 0.0
	return snappedf(amount / (duration_ms / 1000.0), 0.001)

func _safe_div(numerator: float, denominator: float) -> float:
	if denominator <= 0.0:
		return 0.0
	return snappedf(numerator / denominator, 0.001)

func _rare_marker(records: int, label := "DATA") -> String:
	return "AURORA_RARE_%s_%d" % [label, maxi(0, records - 1)]

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size

func _cleanup_source_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _fail_report(report: Dictionary, message: String) -> Dictionary:
	report["ok"] = false
	var errors: Array = report.get("errors", [])
	errors.append(message)
	report["errors"] = errors
	return report
