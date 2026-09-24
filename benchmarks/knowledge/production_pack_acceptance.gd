extends SceneTree

const InstallerScript = preload("res://scripts/knowledge_pack_installer.gd")
const StoreScript = preload("res://scripts/knowledge_store.gd")
const REPORT_SCHEMA := "aurorafox.production-knowledge-acceptance.v1"
const RELEASE_CONTRACT_PATH := "res://knowledge_pack/production_pack.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started := Time.get_ticks_usec()
	var pack_dir := OS.get_environment("AURORAFOX_PRODUCTION_PACK_DIR").strip_edges()
	var report_path := OS.get_environment("AURORAFOX_PRODUCTION_PACK_REPORT").strip_edges()
	var report := {
		"schema": REPORT_SCHEMA,
		"passed": false,
		"offline": true,
		"external_ai_required": false,
		"pack_dir_sha256": pack_dir.sha256_text(),
	}
	if pack_dir.is_empty() or report_path.is_empty():
		_finish(report, report_path, started, "production pack directory/report is missing", 2)
		return

	var installer = InstallerScript.new()
	var inspected: Dictionary = installer.inspect(pack_dir)
	report["inspection"] = inspected
	if not bool(inspected.get("ok", false)):
		_finish(report, report_path, started, "production pack inspection failed", 3)
		return
	var manifest: Dictionary = inspected.get("manifest", {})
	if not bool(manifest.get("production", false)):
		_finish(report, report_path, started, "manifest is not production", 4)
		return
	var contract_check := _check_release_contract(manifest)
	report["release_contract"] = contract_check
	if not bool(contract_check.get("ok", false)):
		_finish(report, report_path, started, str(contract_check.get("error", "release contract mismatch")), 4)
		return
	var query_probe := _query_probe(inspected)
	if not bool(query_probe.get("ok", false)):
		_finish(report, report_path, started, str(query_probe.get("error", "query probe failed")), 5)
		return

	var installed := _install_pack(installer, pack_dir)
	report["install"] = installed
	if not bool(installed.get("ok", false)) or str(installed.get("status", "")) != "ready":
		_finish(report, report_path, started, "production pack installation failed", 6)
		return
	var resumed := _install_pack(installer, pack_dir)
	report["resume"] = resumed
	if not bool(resumed.get("ok", false)) or int(resumed.get("skipped_shards", -1)) != int(inspected.get("shard_count", 0)):
		_finish(report, report_path, started, "production pack resume failed", 7)
		return

	var query := str(query_probe.get("query", ""))
	var expected_source := str(query_probe.get("source", ""))
	var hits: Array = StoreScript.new().search(query, 64)
	var matched := false
	for value in hits:
		if not value is Dictionary:
			continue
		var item: Dictionary = value
		var metadata = item.get("metadata", {})
		if (
			metadata is Dictionary
			and str(metadata.get("pack_id", "")) == str(inspected.get("pack_id", ""))
			and str(item.get("source", "")) == expected_source
			and str(item.get("text", "")).to_lower().contains(query.to_lower())
		):
			matched = true
			break
	report["query"] = {
		"query_sha256": query.sha256_text(),
		"source_sha256": expected_source.sha256_text(),
		"result_count": hits.size(),
		"matched_pack_provenance": matched,
	}
	if not matched:
		_finish(report, report_path, started, "production pack query did not preserve pack provenance", 8)
		return

	report["passed"] = true
	report["pack_id"] = inspected.get("pack_id", "")
	report["pack_version"] = inspected.get("pack_version", "")
	report["manifest_sha256"] = inspected.get("manifest_sha256", "")
	report["shards"] = inspected.get("shard_count", 0)
	report["content_bytes"] = inspected.get("content_bytes", 0)
	report["record_count"] = inspected.get("record_count", 0)
	_finish(report, report_path, started, "", 0)


func _install_pack(installer: Object, pack_dir: String) -> Dictionary:
	if installer == null or not installer.has_method("install"):
		return {"ok": false, "error": "Knowledge Pack installer method is unavailable"}
	var value = installer.call("install", StoreScript.new(), pack_dir)
	if not value is Dictionary:
		return {"ok": false, "error": "Knowledge Pack installer returned an invalid result"}
	return value


func _query_probe(inspected: Dictionary) -> Dictionary:
	var shards = inspected.get("shards", [])
	if not shards is Array or shards.is_empty() or not shards[0] is Dictionary:
		return {"ok": false, "error": "production pack has no query-probe shard"}
	var path := str(shards[0].get("path", ""))
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot open query-probe shard"}
	var first_record: Dictionary = {}
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:
			first_record = parsed
		break
	file.close()
	var record_id := str(first_record.get("id", "")).strip_edges()
	if record_id.is_empty():
		return {"ok": false, "error": "query-probe record id is missing"}
	return {"ok": true, "query": record_id, "source": path}


func _check_release_contract(manifest: Dictionary) -> Dictionary:
	var file := FileAccess.open(RELEASE_CONTRACT_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "production release contract is missing"}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("manifest", {}) is Dictionary:
		return {"ok": false, "error": "production release contract is invalid"}
	var expected: Dictionary = parsed.get("manifest", {})
	for key in ["schema", "pack_id", "pack_version", "record_schema", "content_bytes", "file_bytes", "record_count", "shard_limit_bytes", "languages", "domains", "source"]:
		if manifest.get(key) != expected.get(key):
			return {"ok": false, "error": "production release contract mismatch: " + key}
	if int(manifest.get("shards", []).size()) != int(expected.get("shard_count", -1)):
		return {"ok": false, "error": "production release shard count mismatch"}
	var inputs = manifest.get("input_archives", [])
	if not inputs is Array or inputs.size() != 1 or inputs[0] != expected.get("input_archive", {}):
		return {"ok": false, "error": "production release input provenance mismatch"}
	return {
		"ok": true,
		"pack_id": manifest.get("pack_id", ""),
		"pack_version": manifest.get("pack_version", ""),
		"shards": manifest.get("shards", []).size(),
	}


func _finish(report: Dictionary, report_path: String, started: int, error: String, code: int) -> void:
	report["elapsed_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	report["static_memory_peak_bytes"] = int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
	if not error.is_empty():
		report["error"] = error
	if not report_path.is_empty() and not _write_json_atomic(report_path, report):
		push_error("cannot persist production Knowledge Pack report")
		code = 9
	print("AURORA_PRODUCTION_KNOWLEDGE_ACCEPTANCE ", JSON.stringify(report))
	quit(code)


func _write_json_atomic(path: String, value: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temporary := path + ".tmp-" + str(Time.get_ticks_usec())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  ") + "\n")
	file.flush()
	file.close()
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	return DirAccess.rename_absolute(temporary, path) == OK
