extends SceneTree

# Runtime proof for two Knowledge races that the generic benchmark did not cover:
# 1) two byte-identical sources imported at the same time must serialize into
#    one canonical source plus one alias without duplicate store growth;
# 2) search racing canonical source removal must not corrupt committed state and
#    must preserve an unrelated control source.
const KnowledgeStoreScript: Variant = preload("res://scripts/knowledge_store.gd")
const KnowledgeImportTransactionScript: Variant = preload("res://scripts/knowledge_import_transaction.gd")
const KnowledgeSourceRegistryScript: Variant = preload("res://scripts/knowledge_source_registry.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_CONCURRENCY_RESULT="
const ROOT := "user://knowledge_concurrency_probe"
const DUP_A := ROOT + "/duplicate_A.jsonl"
const DUP_B := ROOT + "/duplicate_B.jsonl"
const RACE_SOURCE := ROOT + "/race_source.jsonl"
const CONTROL_SOURCE := ROOT + "/control_source.jsonl"
const DUP_MARKER := "AURORA_CONCURRENT_DUPLICATE_314159"
const RACE_MARKER := "AURORA_SEARCH_REMOVE_RACE_271828"
const CONTROL_MARKER := "AURORA_SEARCH_REMOVE_CONTROL_161803"
const MB := 1024 * 1024

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	var duplicate_result := _concurrent_duplicate_import()
	var search_remove_result := _search_remove_race()
	var ok := bool(duplicate_result.get("ok", false)) and bool(search_remove_result.get("ok", false))
	_emit({
		"ok": ok,
		"concurrent_duplicate_import": duplicate_result,
		"search_remove_race": search_remove_result,
		"network_required": false,
		"external_runtime_required": false,
		"ollama_required": false,
		"runtime": {
			"os": OS.get_name(),
			"godot": Engine.get_version_info(),
			"architecture": Engine.get_architecture_name()
		}
	}, 0 if ok else 5)

func _concurrent_duplicate_import() -> Dictionary:
	_reset_state()
	if not _write_jsonl(DUP_A, DUP_MARKER, MB):
		return {"ok": false, "error": "cannot create duplicate source A"}
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(DUP_A), ProjectSettings.globalize_path(DUP_B)) != OK:
		return {"ok": false, "error": "cannot create byte-identical duplicate source B"}

	var start_gate := Semaphore.new()
	var thread_a := Thread.new()
	var thread_b := Thread.new()
	var start_a := thread_a.start(func():
		start_gate.wait()
		return KnowledgeImportTransactionScript.new().call("import_file", KnowledgeStoreScript.new(), DUP_A, {"imported_by": "knowledge_concurrency_probe"})
	)
	var start_b := thread_b.start(func():
		start_gate.wait()
		return KnowledgeImportTransactionScript.new().call("import_file", KnowledgeStoreScript.new(), DUP_B, {"imported_by": "knowledge_concurrency_probe"})
	)
	if start_a != OK or start_b != OK:
		start_gate.post()
		start_gate.post()
		if start_a == OK:
			thread_a.wait_to_finish()
		if start_b == OK:
			thread_b.wait_to_finish()
		return {"ok": false, "error": "duplicate-import thread start failed", "thread_a": start_a, "thread_b": start_b}
	start_gate.post()
	start_gate.post()
	var result_a: Variant = thread_a.wait_to_finish()
	var result_b: Variant = thread_b.wait_to_finish()

	var registry: Variant = KnowledgeSourceRegistryScript.new()
	var row_a: Variant = registry.call("record_for_source", DUP_A)
	var row_b: Variant = registry.call("record_for_source", DUP_B)
	var stats: Variant = registry.call("stats")
	var canonical_a := str(row_a.get("source", "")) if row_a is Dictionary else ""
	var canonical_b := str(row_b.get("source", "")) if row_b is Dictionary else ""
	var fingerprint_a := str(row_a.get("fingerprint_sha256", "")) if row_a is Dictionary else ""
	var fingerprint_b := str(row_b.get("fingerprint_sha256", "")) if row_b is Dictionary else ""
	var searchable: Variant = KnowledgeStoreScript.new().call("search", DUP_MARKER, 32)
	var searchable_sources := _source_set(searchable)
	var a_skipped := result_a is Dictionary and bool(result_a.get("skipped", false)) and bool(result_a.get("duplicate", false))
	var b_skipped := result_b is Dictionary and bool(result_b.get("skipped", false)) and bool(result_b.get("duplicate", false))
	var serialized := result_a is Dictionary and result_b is Dictionary
	serialized = serialized and bool(result_a.get("transaction_serialized", false)) and bool(result_b.get("transaction_serialized", false))
	var one_import_one_alias := a_skipped != b_skipped
	var registry_ok := row_a is Dictionary and row_b is Dictionary and stats is Dictionary
	registry_ok = registry_ok and not canonical_a.is_empty() and canonical_a == canonical_b
	registry_ok = registry_ok and not fingerprint_a.is_empty() and fingerprint_a == fingerprint_b
	registry_ok = registry_ok and int(stats.get("sources", -1)) == 1 and int(stats.get("aliases", -1)) == 1
	var store_ok := searchable is Array and not searchable.is_empty() and searchable_sources.size() == 1
	store_ok = store_ok and searchable_sources.has(canonical_a)
	var clean := _transaction_residue().is_empty()
	var ok := result_a is Dictionary and result_b is Dictionary
	ok = ok and bool(result_a.get("ok", false)) and bool(result_b.get("ok", false))
	ok = ok and serialized and one_import_one_alias and registry_ok and store_ok and clean
	return {
		"ok": ok,
		"thread_a": result_a,
		"thread_b": result_b,
		"transaction_serialized": serialized,
		"one_import_one_duplicate_alias": one_import_one_alias,
		"canonical_source": canonical_a,
		"same_fingerprint": not fingerprint_a.is_empty() and fingerprint_a == fingerprint_b,
		"registry_stats": stats,
		"searchable_sources": searchable_sources,
		"transaction_residue": _transaction_residue()
	}

func _search_remove_race() -> Dictionary:
	_reset_state()
	if not _write_jsonl(RACE_SOURCE, RACE_MARKER, MB):
		return {"ok": false, "error": "cannot create race source"}
	if not _write_jsonl(CONTROL_SOURCE, CONTROL_MARKER, 128 * 1024):
		return {"ok": false, "error": "cannot create control source"}
	var txn: Variant = KnowledgeImportTransactionScript.new()
	var imported_race: Variant = txn.call("import_file", KnowledgeStoreScript.new(), RACE_SOURCE, {"imported_by": "knowledge_concurrency_probe"})
	var imported_control: Variant = txn.call("import_file", KnowledgeStoreScript.new(), CONTROL_SOURCE, {"imported_by": "knowledge_concurrency_probe"})
	if not (imported_race is Dictionary and bool(imported_race.get("ok", false)) and imported_control is Dictionary and bool(imported_control.get("ok", false))):
		return {"ok": false, "error": "race fixture import failed", "race_import": imported_race, "control_import": imported_control}

	var search_ready := Semaphore.new()
	var removal_done := Semaphore.new()
	var search_thread := Thread.new()
	var remove_thread := Thread.new()
	var search_start := search_thread.start(func():
		var local_store: Variant = KnowledgeStoreScript.new()
		var first: Variant = local_store.call("search", RACE_MARKER, 8)
		var first_hit := _contains_source(first, RACE_SOURCE)
		search_ready.post()
		var hits := 0
		var misses := 0
		var invalid := 0
		for _i in range(64):
			var rows: Variant = local_store.call("search", RACE_MARKER, 8)
			if not rows is Array:
				invalid += 1
			elif _contains_source(rows, RACE_SOURCE):
				hits += 1
			else:
				misses += 1
		removal_done.wait()
		var after: Variant = local_store.call("search", RACE_MARKER, 8)
		return {
			"first_hit": first_hit,
			"concurrent_iterations": 64,
			"concurrent_hits": hits,
			"concurrent_misses": misses,
			"invalid_results": invalid,
			"post_remove_empty": after is Array and after.is_empty()
		}
	)
	var remove_start := remove_thread.start(func():
		search_ready.wait()
		var result: Variant = KnowledgeImportTransactionScript.new().call("remove_source", KnowledgeStoreScript.new(), RACE_SOURCE)
		removal_done.post()
		return result
	)
	if search_start != OK or remove_start != OK:
		search_ready.post()
		removal_done.post()
		if search_start == OK:
			search_thread.wait_to_finish()
		if remove_start == OK:
			remove_thread.wait_to_finish()
		return {"ok": false, "error": "search-remove thread start failed", "search_thread": search_start, "remove_thread": remove_start}

	var search_result: Variant = search_thread.wait_to_finish()
	var remove_result: Variant = remove_thread.wait_to_finish()
	var final_store: Variant = KnowledgeStoreScript.new()
	var final_race: Variant = final_store.call("search", RACE_MARKER, 8)
	var final_control: Variant = final_store.call("search", CONTROL_MARKER, 8)
	var registry: Variant = KnowledgeSourceRegistryScript.new()
	var race_row: Variant = registry.call("record_for_source", RACE_SOURCE)
	var control_row: Variant = registry.call("record_for_source", CONTROL_SOURCE)
	var search_ok := search_result is Dictionary and bool(search_result.get("first_hit", false))
	search_ok = search_ok and int(search_result.get("invalid_results", 1)) == 0 and bool(search_result.get("post_remove_empty", false))
	var removal_ok := remove_result is Dictionary and bool(remove_result.get("ok", false)) and bool(remove_result.get("transaction_serialized", false))
	var final_ok := final_race is Array and final_race.is_empty()
	final_ok = final_ok and _contains_source(final_control, CONTROL_SOURCE)
	final_ok = final_ok and race_row is Dictionary and race_row.is_empty()
	final_ok = final_ok and control_row is Dictionary and not control_row.is_empty()
	var clean := _transaction_residue().is_empty()
	return {
		"ok": search_ok and removal_ok and final_ok and clean,
		"search": search_result,
		"remove": remove_result,
		"final_removed_source_empty": final_race is Array and final_race.is_empty(),
		"control_source_preserved": _contains_source(final_control, CONTROL_SOURCE),
		"removed_registry_absent": race_row is Dictionary and race_row.is_empty(),
		"control_registry_present": control_row is Dictionary and not control_row.is_empty(),
		"transaction_residue": _transaction_residue()
	}

func _write_jsonl(path: String, marker: String, target_bytes: int) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var filler := "aurora concurrency local knowledge данные " + "x".repeat(720)
	var index := 0
	while file.get_position() < target_bytes:
		file.store_line(JSON.stringify({"kind": "fact", "index": index, "content": "%s %s row_%06d" % [marker, filler, index]}))
		index += 1
	file.close()
	return true

static func _contains_source(items: Variant, source: String) -> bool:
	if not items is Array:
		return false
	for item in items:
		if item is Dictionary and str(item.get("source", "")) == source:
			return true
	return false

static func _source_set(items: Variant) -> Dictionary:
	var out := {}
	if not items is Array:
		return out
	for item in items:
		if item is Dictionary:
			out[str(item.get("source", ""))] = true
	return out

func _transaction_residue() -> Array[String]:
	var paths: Array[String] = [
		str(KnowledgeImportTransactionScript.DB_BACKUP),
		str(KnowledgeImportTransactionScript.STRUCTURED_BACKUP),
		str(KnowledgeImportTransactionScript.REGISTRY_BACKUP),
		str(KnowledgeStoreScript.DB_PATH) + ".filter.tmp",
		str(KnowledgeStoreScript.STRUCTURED_PATH) + ".filter.tmp"
	]
	var transaction_constants: Dictionary = KnowledgeImportTransactionScript.get_script_constant_map()
	for name in ["TXN_MANIFEST", "TXN_MANIFEST_TMP", "TXN_SNAPSHOT_MARKER", "TXN_SNAPSHOT_MARKER_TMP", "TXN_COMMIT_MARKER", "TXN_COMMIT_MARKER_TMP"]:
		if transaction_constants.has(name):
			paths.append(str(transaction_constants.get(name, "")))
	var registry_constants: Dictionary = KnowledgeSourceRegistryScript.get_script_constant_map()
	for name in ["REGISTRY_TEMP", "REGISTRY_ORIGINAL"]:
		if registry_constants.has(name):
			paths.append(str(registry_constants.get(name, "")))
	var present: Array[String] = []
	for path in paths:
		if not path.is_empty() and FileAccess.file_exists(path):
			present.append(path)
	return present

func _reset_state() -> void:
	var paths: Array[String] = [
		str(KnowledgeStoreScript.DB_PATH),
		str(KnowledgeStoreScript.STRUCTURED_PATH),
		str(KnowledgeSourceRegistryScript.REGISTRY_PATH),
		str(KnowledgeImportTransactionScript.DB_BACKUP),
		str(KnowledgeImportTransactionScript.STRUCTURED_BACKUP),
		str(KnowledgeImportTransactionScript.REGISTRY_BACKUP),
		str(KnowledgeStoreScript.DB_PATH) + ".filter.tmp",
		str(KnowledgeStoreScript.STRUCTURED_PATH) + ".filter.tmp",
		DUP_A,
		DUP_B,
		RACE_SOURCE,
		CONTROL_SOURCE
	]
	var transaction_constants: Dictionary = KnowledgeImportTransactionScript.get_script_constant_map()
	for name in ["TXN_MANIFEST", "TXN_MANIFEST_TMP", "TXN_SNAPSHOT_MARKER", "TXN_SNAPSHOT_MARKER_TMP", "TXN_COMMIT_MARKER", "TXN_COMMIT_MARKER_TMP"]:
		if transaction_constants.has(name):
			paths.append(str(transaction_constants.get(name, "")))
	var registry_constants: Dictionary = KnowledgeSourceRegistryScript.get_script_constant_map()
	for name in ["REGISTRY_TEMP", "REGISTRY_ORIGINAL"]:
		if registry_constants.has(name):
			paths.append(str(registry_constants.get(name, "")))
	for path in paths:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	KnowledgeSourceRegistryScript.call("invalidate_runtime_cache")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))

func _emit(result: Dictionary, code: int) -> void:
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
