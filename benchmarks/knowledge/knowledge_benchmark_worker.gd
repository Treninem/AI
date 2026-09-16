extends SceneTree

const RESULT_PREFIX := "AURORA_KNOWLEDGE_BENCH_RESULT="
const KNOWLEDGE_DB := "user://knowledge/knowledge.jsonl"
const STRUCTURED_DB := "user://knowledge/structured.jsonl"
const MEMORY_PATH := "user://memory.json"
const MEMORY_KNOWLEDGE_PATH := "user://knowledge.json"
const MEMORY_VECTOR_PATH := "user://memory_vectors.json"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var phase := str(args.get("phase", "noop"))
	var result: Dictionary
	match phase:
		"noop":
			result = {"ok": true, "phase": phase, "platform": OS.get_name()}
		"knowledge_import":
			result = _knowledge_import(args)
		"knowledge_restart":
			result = _knowledge_restart(args)
		"knowledge_remove":
			result = _knowledge_remove(args)
		"source_scaling":
			result = _source_scaling(args)
		"dedup_rollback":
			result = _dedup_rollback(args)
		"memory_import":
			result = _memory_import(args)
		"memory_restart":
			result = _memory_restart(args)
		_:
			result = {"ok": false, "harness_error": true, "error": "unknown phase", "phase": phase}
	result["phase"] = phase
	result["platform"] = OS.get_name()
	result["engine"] = Engine.get_version_info()
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(0 if not bool(result.get("harness_error", false)) else 90)

func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < raw.size():
		var key := str(raw[i])
		if key.begins_with("--"):
			key = key.substr(2)
			if i + 1 < raw.size() and not str(raw[i + 1]).begins_with("--"):
				out[key] = str(raw[i + 1])
				i += 2
				continue
			out[key] = "true"
		i += 1
	return out

func _knowledge_import(args: Dictionary) -> Dictionary:
	var format := str(args.get("format", "jsonl")).to_lower()
	var size_mb := float(args.get("size_mb", "1"))
	var payload_bytes := maxi(64, int(args.get("payload_bytes", "768")))
	var marker := _marker(format, size_mb)
	var generated := _generate_dataset(format, size_mb, payload_bytes, marker)
	if not bool(generated.get("ok", false)):
		generated["harness_error"] = true
		return generated
	var path := str(generated.get("path", ""))
	var store := KnowledgeStore.new()
	var txn := KnowledgeImportTransaction.new()
	var start := Time.get_ticks_usec()
	var imported := txn.import_file(store, path, {"imported_by": "large_knowledge_perf", "untrusted_document": true})
	var import_ms := _elapsed_ms(start)
	var search := _search_metrics(store, marker)
	var result := {
		"ok": bool(imported.get("ok", false)) and bool(search.get("correct", false)),
		"format": format,
		"dataset_size_bytes": int(generated.get("bytes", 0)),
		"record_count": int(generated.get("records", 0)),
		"chunk_count": int(imported.get("chunks", 0)),
		"structured_record_count": int(imported.get("records", 0)),
		"import_duration_ms": import_ms,
		"records_per_sec": _rate(int(generated.get("records", 0)), import_ms),
		"mb_per_sec": _rate(float(generated.get("bytes", 0)) / 1048576.0, import_ms),
		"streaming": bool(imported.get("streaming", false)),
		"stream_parser": str(imported.get("stream_parser", "")),
		"transaction": str(imported.get("transaction", "")),
		"store_size_bytes": _knowledge_store_size(),
		"knowledge_rows": _count_jsonl(KNOWLEDGE_DB),
		"structured_rows": _count_jsonl(STRUCTURED_DB),
		"marker": marker,
		"source": path,
		"search": search,
		"import_result": _result_summary(imported)
	}
	return result

func _knowledge_restart(args: Dictionary) -> Dictionary:
	var format := str(args.get("format", "jsonl")).to_lower()
	var size_mb := float(args.get("size_mb", "1"))
	var marker := _marker(format, size_mb)
	var start := Time.get_ticks_usec()
	var store := KnowledgeStore.new()
	var manager := KnowledgeManager.new()
	var stats := manager.stats()
	var search := _search_metrics(store, marker)
	var load_ms := _elapsed_ms(start)
	return {
		"ok": bool(search.get("correct", false)) and int(stats.get("chunks", 0)) > 0,
		"restart_load_and_search_ms": load_ms,
		"marker": marker,
		"search": search,
		"stats": stats,
		"store_size_bytes": _knowledge_store_size()
	}

func _knowledge_remove(args: Dictionary) -> Dictionary:
	var format := str(args.get("format", "jsonl")).to_lower()
	var size_mb := float(args.get("size_mb", "1"))
	var marker := _marker(format, size_mb)
	var path := _dataset_path(format, size_mb)
	var manager := KnowledgeManager.new()
	var start := Time.get_ticks_usec()
	var removed := manager.remove_source(path)
	var removal_ms := _elapsed_ms(start)
	var store := KnowledgeStore.new()
	var stale := store.search(marker, 4)
	return {
		"ok": bool(removed.get("ok", false)) and stale.is_empty(),
		"source_removal_ms": removal_ms,
		"removed_chunks": int(removed.get("removed", 0)),
		"removed_structured_records": int(removed.get("structured_removed", 0)),
		"stale_results": stale.size(),
		"store_size_bytes": _knowledge_store_size()
	}

func _source_scaling(args: Dictionary) -> Dictionary:
	var sources := maxi(1, int(args.get("sources", "8")))
	var records_per_source := maxi(1, int(args.get("records_per_source", "24")))
	var payload_bytes := maxi(64, int(args.get("payload_bytes", "512")))
	var txn := KnowledgeImportTransaction.new()
	var store := KnowledgeStore.new()
	var durations: Array = []
	var total_records := 0
	var total_bytes := 0
	var ok := true
	var latest_marker := ""
	var suite_start := Time.get_ticks_usec()
	for source_index in range(sources):
		var path := "user://bench/sources/source_%05d.jsonl" % source_index
		var marker := "AURORA_SOURCE_SCALE_%05d" % source_index
		latest_marker = marker
		var generated := _generate_jsonl_records(path, records_per_source, payload_bytes, marker)
		if not bool(generated.get("ok", false)):
			return {"ok": false, "harness_error": true, "error": "source fixture generation failed", "detail": generated}
		total_records += int(generated.get("records", 0))
		total_bytes += int(generated.get("bytes", 0))
		var start := Time.get_ticks_usec()
		var imported := txn.import_file(store, path, {"imported_by": "source_scaling"})
		var elapsed := _elapsed_ms(start)
		durations.append(elapsed)
		if not bool(imported.get("ok", false)):
			ok = false
			break
	var total_ms := _elapsed_ms(suite_start)
	var latest_found := not store.search(latest_marker, 3).is_empty()
	return {
		"ok": ok and latest_found,
		"source_count": sources,
		"record_count": total_records,
		"dataset_size_bytes": total_bytes,
		"import_duration_ms": total_ms,
		"records_per_sec": _rate(total_records, total_ms),
		"mb_per_sec": _rate(float(total_bytes) / 1048576.0, total_ms),
		"per_source_ms": durations,
		"first_quarter_mean_ms": _mean_slice(durations, 0, maxi(1, durations.size() / 4)),
		"last_quarter_mean_ms": _mean_slice(durations, maxi(0, durations.size() - maxi(1, durations.size() / 4)), durations.size()),
		"store_size_bytes": _knowledge_store_size(),
		"latest_marker_found": latest_found
	}

func _dedup_rollback(_args: Dictionary) -> Dictionary:
	var store := KnowledgeStore.new()
	var txn := KnowledgeImportTransaction.new()
	var manager := KnowledgeManager.new()
	var path_a := "user://bench/dedup_a.jsonl"
	var path_b := "user://bench/dedup_copy.jsonl"
	var path_c := "user://bench/remove_c.jsonl"
	_generate_duplicate_fixture(path_a, "AURORA_DEDUP_OLD")
	var first := txn.import_file(store, path_a, {"imported_by": "dedup_rollback"})
	var second := txn.import_file(store, path_a, {"imported_by": "dedup_rollback"})
	_copy_file(path_a, path_b)
	var alias := txn.import_file(store, path_b, {"imported_by": "dedup_rollback"})
	var duplicate_ids_before_compact := _duplicate_id_count(KNOWLEDGE_DB)

	# A malformed replacement must restore the previously committed source.
	var bad := FileAccess.open(path_a, FileAccess.WRITE)
	if bad == null:
		return {"ok": false, "harness_error": true, "error": "cannot create rollback fixture"}
	for i in range(12):
		bad.store_line(JSON.stringify({"index": i, "content": "AURORA_NEW_PARTIAL_%d" % i}))
	bad.store_line("{malformed-json")
	bad.close()
	var rollback_start := Time.get_ticks_usec()
	var failed := txn.import_file(store, path_a, {"imported_by": "dedup_rollback"})
	var rollback_ms := _elapsed_ms(rollback_start)
	var old_survived := not store.search("AURORA_DEDUP_OLD", 5).is_empty()
	var partial_leaked := not store.search("AURORA_NEW_PARTIAL_11", 5).is_empty()

	# A+B+C removal contract: deleting B must leave A and C searchable.
	_generate_jsonl_records(path_c, 8, 256, "AURORA_REMOVE_C")
	var c_import := txn.import_file(store, path_c, {"imported_by": "dedup_rollback"})
	var removal_start := Time.get_ticks_usec()
	var removed_b := manager.remove_source(path_b)
	var removal_ms := _elapsed_ms(removal_start)
	var a_alive := not store.search("AURORA_DEDUP_OLD", 5).is_empty()
	var c_alive := not store.search("AURORA_REMOVE_C", 5).is_empty()
	var compact_start := Time.get_ticks_usec()
	var compacted := manager.compact()
	var compact_ms := _elapsed_ms(compact_start)
	var duplicate_ids_after_compact := _duplicate_id_count(KNOWLEDGE_DB)

	var source_duplicate_ok := bool(second.get("skipped", false)) or str(second.get("transaction", "")) == "skipped_duplicate"
	var alias_duplicate_ok := bool(alias.get("skipped", false)) or str(alias.get("transaction", "")) == "skipped_duplicate"
	var rollback_ok := not bool(failed.get("ok", true)) and str(failed.get("transaction", "")) == "rolled_back" and old_survived and not partial_leaked
	var removal_ok := bool(removed_b.get("ok", false)) and a_alive and c_alive
	return {
		"ok": bool(first.get("ok", false)) and bool(c_import.get("ok", false)) and source_duplicate_ok and alias_duplicate_ok and rollback_ok and removal_ok and duplicate_ids_after_compact == 0,
		"same_file_duplicate_suppressed": source_duplicate_ok,
		"copy_alias_duplicate_suppressed": alias_duplicate_ok,
		"duplicate_ids_before_compact": duplicate_ids_before_compact,
		"duplicate_ids_after_compact": duplicate_ids_after_compact,
		"compact_removed": int(compacted.get("duplicates_removed", 0)),
		"compact_ms": compact_ms,
		"rollback_ok": rollback_ok,
		"rollback_ms": rollback_ms,
		"old_state_survived": old_survived,
		"partial_state_leaked": partial_leaked,
		"remove_middle_source_ok": removal_ok,
		"source_removal_ms": removal_ms,
		"a_alive": a_alive,
		"c_alive": c_alive,
		"failed_import": _result_summary(failed)
	}

func _memory_import(args: Dictionary) -> Dictionary:
	var records := clampi(int(args.get("records", "200")), 1, 10000)
	var memory_store := MemoryStore.new()
	get_root().add_child(memory_store)
	memory_store.set_process(false)
	var marker := "AURORA_MEMORY_RARE_%d" % records
	var write_start := Time.get_ticks_usec()
	for i in range(records):
		var content := "memory benchmark record %d aurora_common knowledge performance" % i
		if i == records - 1:
			content += " " + marker + " производительность память"
		memory_store.learn(content, "large_knowledge_perf", 0.7, 0.9, "benchmark")
	var write_ms := _elapsed_ms(write_start)
	var index_start := Time.get_ticks_usec()
	var status := memory_store.reindex_semantic()
	var index_ms := _elapsed_ms(index_start)
	var search := _memory_search_metrics(memory_store, marker)
	var files_bytes := _file_size(MEMORY_PATH) + _file_size(MEMORY_KNOWLEDGE_PATH) + _file_size(MEMORY_VECTOR_PATH)
	var ok := bool(search.get("correct", false)) and not bool(status.get("network_required", true)) and not bool(status.get("external_runtime_required", true)) and not bool(status.get("ollama_required", true))
	return {
		"ok": ok,
		"record_count": records,
		"write_duration_ms": write_ms,
		"records_per_sec": _rate(records, write_ms),
		"semantic_index_ms": index_ms,
		"search": search,
		"store_size_bytes": files_bytes,
		"marker": marker,
		"semantic_status": status
	}

func _memory_restart(args: Dictionary) -> Dictionary:
	var records := clampi(int(args.get("records", "200")), 1, 10000)
	var marker := "AURORA_MEMORY_RARE_%d" % records
	var start := Time.get_ticks_usec()
	var memory_store := MemoryStore.new()
	get_root().add_child(memory_store)
	memory_store.set_process(false)
	var loaded_ms := _elapsed_ms(start)
	var search := _memory_search_metrics(memory_store, marker)
	var status := memory_store.semantic_status()
	return {
		"ok": bool(search.get("correct", false)) and int(status.get("knowledge_items", 0)) == records,
		"restart_load_ms": loaded_ms,
		"record_count": int(status.get("knowledge_items", 0)),
		"search": search,
		"semantic_status": status,
		"store_size_bytes": _file_size(MEMORY_PATH) + _file_size(MEMORY_KNOWLEDGE_PATH) + _file_size(MEMORY_VECTOR_PATH)
	}

func _generate_dataset(format: String, size_mb: float, payload_bytes: int, marker: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench"))
	var path := _dataset_path(format, size_mb)
	var target := maxi(1024, int(size_mb * 1048576.0))
	match format:
		"jsonl", "ndjson":
			return _generate_jsonl_bytes(path, target, payload_bytes, marker)
		"csv":
			return _generate_csv_bytes(path, target, payload_bytes, marker)
		"txt":
			return _generate_text_bytes(path, target, payload_bytes, marker)
		"json":
			return _generate_json_array_bytes(path, target, payload_bytes, marker)
		_:
			return {"ok": false, "error": "unsupported format", "format": format}

func _generate_jsonl_bytes(path: String, target: int, payload_bytes: int, marker: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot create jsonl", "path": path}
	var i := 0
	var filler := "x".repeat(payload_bytes)
	while file.get_position() < target:
		file.store_line(JSON.stringify({"index": i, "kind": "fact", "content": "aurora_common knowledge benchmark производительность память %s %s" % [str(i), filler]}))
		i += 1
	file.store_line(JSON.stringify({"index": i, "kind": "fact", "content": marker + " rare final record"}))
	i += 1
	var bytes := file.get_position()
	file.close()
	return {"ok": true, "path": path, "bytes": bytes, "records": i}

func _generate_jsonl_records(path: String, records: int, payload_bytes: int, marker: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot create jsonl records", "path": path}
	var filler := "r".repeat(payload_bytes)
	for i in range(records):
		var content := "aurora_common source scaling %d %s" % [i, filler]
		if i == records - 1:
			content += " " + marker
		file.store_line(JSON.stringify({"index": i, "content": content}))
	var bytes := file.get_position()
	file.close()
	return {"ok": true, "path": path, "bytes": bytes, "records": records}

func _generate_csv_bytes(path: String, target: int, payload_bytes: int, marker: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot create csv", "path": path}
	file.store_csv_line(PackedStringArray(["index", "kind", "content"]), ",")
	var i := 0
	var filler := "c".repeat(payload_bytes)
	while file.get_position() < target:
		file.store_csv_line(PackedStringArray([str(i), "fact", "aurora_common knowledge benchmark производительность память %s" % filler]), ",")
		i += 1
	file.store_csv_line(PackedStringArray([str(i), "fact", marker + " rare final record"]), ",")
	i += 1
	var bytes := file.get_position()
	file.close()
	return {"ok": true, "path": path, "bytes": bytes, "records": i}

func _generate_text_bytes(path: String, target: int, payload_bytes: int, marker: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot create text", "path": path}
	var i := 0
	var filler := "t".repeat(payload_bytes)
	while file.get_position() < target:
		file.store_string("paragraph %d aurora_common knowledge benchmark производительность память %s\n\n" % [i, filler])
		i += 1
	file.store_string(marker + " rare final paragraph\n")
	i += 1
	var bytes := file.get_position()
	file.close()
	return {"ok": true, "path": path, "bytes": bytes, "records": i}

func _generate_json_array_bytes(path: String, target: int, payload_bytes: int, marker: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot create json", "path": path}
	file.store_string("[\n")
	var i := 0
	var first := true
	var filler := "j".repeat(payload_bytes)
	while file.get_position() < target:
		if not first:
			file.store_string(",\n")
		file.store_string(JSON.stringify({"index": i, "kind": "fact", "content": "aurora_common knowledge benchmark производительность память %s" % filler}))
		first = false
		i += 1
	file.store_string(",\n" + JSON.stringify({"index": i, "kind": "fact", "content": marker + " rare final record"}) + "\n]\n")
	i += 1
	var bytes := file.get_position()
	file.close()
	return {"ok": true, "path": path, "bytes": bytes, "records": i}

func _generate_duplicate_fixture(path: String, marker: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	var duplicate := {"kind": "fact", "content": "identical record " + marker}
	file.store_line(JSON.stringify(duplicate))
	file.store_line(JSON.stringify(duplicate))
	file.store_line(JSON.stringify({"kind": "fact", "content": marker + " unique"}))
	file.close()

func _copy_file(source: String, target: String) -> bool:
	var input := FileAccess.open(source, FileAccess.READ)
	var output := FileAccess.open(target, FileAccess.WRITE)
	if input == null or output == null:
		if input != null: input.close()
		if output != null: output.close()
		return false
	while not input.eof_reached():
		var bytes := input.get_buffer(64 * 1024)
		if bytes.is_empty():
			break
		output.store_buffer(bytes)
	input.close()
	output.close()
	return true

func _search_metrics(store: KnowledgeStore, marker: String) -> Dictionary:
	var queries := [
		{"name": "rare", "query": marker, "must_find": marker},
		{"name": "common", "query": "aurora_common knowledge", "must_find": ""},
		{"name": "russian", "query": "производительность память", "must_find": ""},
		{"name": "mixed", "query": "Aurora память knowledge", "must_find": ""},
		{"name": "long", "query": ("knowledge aurora память ".repeat(32)).strip_edges(), "must_find": ""},
		{"name": "malformed", "query": "\u0000 !!! ((( ??? knowledge ]]]", "must_find": ""}
	]
	var rows: Array = []
	var all_latencies: Array = []
	var correct := true
	for query in queries:
		var latencies: Array = []
		var last: Array = []
		for _repeat in range(7):
			var start := Time.get_ticks_usec()
			last = store.search(str(query.get("query", "")), 6)
			var elapsed := _elapsed_ms(start)
			latencies.append(elapsed)
			all_latencies.append(elapsed)
		var must_find := str(query.get("must_find", ""))
		var found := true
		if not must_find.is_empty():
			found = _results_contain(last, must_find)
			correct = correct and found
		rows.append({
			"name": query.get("name", ""),
			"results": last.size(),
			"correct": found,
			"p50_ms": _percentile(latencies, 0.50),
			"p95_ms": _percentile(latencies, 0.95),
			"p99_ms": _percentile(latencies, 0.99)
		})
	var empty_start := Time.get_ticks_usec()
	var empty := store.search("", 6)
	var empty_ms := _elapsed_ms(empty_start)
	correct = correct and empty.is_empty()
	return {
		"correct": correct,
		"queries": rows,
		"empty_query_ms": empty_ms,
		"p50_ms": _percentile(all_latencies, 0.50),
		"p95_ms": _percentile(all_latencies, 0.95),
		"p99_ms": _percentile(all_latencies, 0.99)
	}

func _memory_search_metrics(store: MemoryStore, marker: String) -> Dictionary:
	var queries := [marker, "knowledge performance", "производительность память", "Aurora память knowledge"]
	var latencies: Array = []
	var rare_found := false
	for query in queries:
		for repeat in range(5):
			var start := Time.get_ticks_usec()
			var found := store.search_knowledge(str(query), 8)
			latencies.append(_elapsed_ms(start))
			if repeat == 4 and str(query) == marker:
				rare_found = _memory_results_contain(found, marker)
	return {
		"correct": rare_found,
		"p50_ms": _percentile(latencies, 0.50),
		"p95_ms": _percentile(latencies, 0.95),
		"p99_ms": _percentile(latencies, 0.99)
	}

func _results_contain(results: Array, needle: String) -> bool:
	for item in results:
		if item is Dictionary and (str(item.get("text", "")).contains(needle) or JSON.stringify(item).contains(needle)):
			return true
	return false

func _memory_results_contain(results: Array, needle: String) -> bool:
	for item in results:
		if item is Dictionary and str(item.get("content", "")).contains(needle):
			return true
	return false

func _dataset_path(format: String, size_mb: float) -> String:
	var safe := str(size_mb).replace(".", "p")
	var ext := "jsonl" if format == "ndjson" else format
	return "user://bench/dataset_%s_%s.%s" % [format, safe, ext]

func _marker(format: String, size_mb: float) -> String:
	return "AURORA_RARE_%s_%s" % [format.to_upper(), str(size_mb).replace(".", "P")]

func _knowledge_store_size() -> int:
	return _file_size(KNOWLEDGE_DB) + _file_size(STRUCTURED_DB) + _file_size(KnowledgeSourceRegistry.REGISTRY_PATH)

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size

func _count_jsonl(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var count := 0
	while not file.eof_reached():
		if not file.get_line().strip_edges().is_empty():
			count += 1
	file.close()
	return count

func _duplicate_id_count(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var seen := {}
	var duplicates := 0
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if not parsed is Dictionary:
			continue
		var id := str(parsed.get("id", ""))
		if id.is_empty():
			continue
		if seen.has(id):
			duplicates += 1
		else:
			seen[id] = true
	file.close()
	return duplicates

func _result_summary(value: Dictionary) -> Dictionary:
	var out := {}
	for key in ["ok", "error", "source", "format", "records", "chunks", "streaming", "stream_parser", "transaction", "revision", "fingerprint_sha256", "skipped", "duplicate", "alias_of"]:
		if value.has(key):
			out[key] = value[key]
	return out

func _rate(amount: Variant, duration_ms: float) -> float:
	if duration_ms <= 0.0:
		return 0.0
	return float(amount) / (duration_ms / 1000.0)

func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0

func _percentile(values: Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var copy := values.duplicate()
	copy.sort()
	var index := clampi(int(ceil((copy.size() - 1) * q)), 0, copy.size() - 1)
	return float(copy[index])

func _mean_slice(values: Array, start: int, end: int) -> float:
	if values.is_empty() or end <= start:
		return 0.0
	var total := 0.0
	var count := 0
	for i in range(start, mini(end, values.size())):
		total += float(values[i])
		count += 1
	return total / float(maxi(1, count))
