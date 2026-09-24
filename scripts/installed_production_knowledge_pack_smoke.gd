extends RefCounted

const InstallerScript = preload("res://scripts/knowledge_pack_installer.gd")
const StoreScript = preload("res://scripts/knowledge_store.gd")
const RELEASE_CONTRACT_PATH := "res://knowledge_pack/production_pack.json"
const RESULT_SCHEMA := "aurorafox.installed-production-knowledge.v1"


func run(result_path: String, pack_dir: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	result_path = result_path.strip_edges()
	pack_dir = pack_dir.strip_edges()
	if result_path.is_empty():
		return _failure(result_path, started, "AURORAFOX_KNOWLEDGE_SMOKE_RESULT is missing", 2)
	if pack_dir.is_empty():
		return _failure(result_path, started, "AURORAFOX_PRODUCTION_PACK_DIR is missing", 3)

	var installer = InstallerScript.new()
	var inspected: Dictionary = installer.inspect(pack_dir)
	if not bool(inspected.get("ok", false)):
		return _failure(result_path, started, "production pack inspection failed: " + JSON.stringify(inspected), 4)
	var manifest: Dictionary = inspected.get("manifest", {})
	if not bool(manifest.get("production", false)):
		return _failure(result_path, started, "manifest is not production", 5)
	var contract := _check_release_contract(manifest)
	if not bool(contract.get("ok", false)):
		return _failure(result_path, started, str(contract.get("error", "release contract mismatch")), 6)
	var query_probe := _query_probe(inspected)
	if not bool(query_probe.get("ok", false)):
		return _failure(result_path, started, str(query_probe.get("error", "query probe failed")), 7)

	var installed := _install_pack(installer, pack_dir)
	if not bool(installed.get("ok", false)) or str(installed.get("status", "")) != "ready":
		return _failure(result_path, started, "production pack installation failed: " + JSON.stringify(installed), 8)

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
	if not matched:
		return _failure(result_path, started, "installed production query did not preserve pack provenance", 9)

	var state_path := "user://knowledge/pack-installs/%s.json" % _safe_pack_id(str(inspected.get("pack_id", "")))
	var proof := {
		"schema": RESULT_SCHEMA,
		"passed": true,
		"installed": true,
		"offline": true,
		"external_ai_required": false,
		"pack_id": inspected.get("pack_id", ""),
		"pack_version": inspected.get("pack_version", ""),
		"manifest_sha256": inspected.get("manifest_sha256", ""),
		"shards": inspected.get("shard_count", 0),
		"record_count": inspected.get("record_count", 0),
		"content_bytes": inspected.get("content_bytes", 0),
		"status": installed.get("status", ""),
		"imported_shards": installed.get("imported_shards", -1),
		"skipped_shards": installed.get("skipped_shards", -1),
		"resumable": installed.get("resumable", false),
		"query_match": matched,
		"query_result_count": hits.size(),
		"query_sha256": query.sha256_text(),
		"source_sha256": expected_source.sha256_text(),
		"state_path": ProjectSettings.globalize_path(state_path),
		"state_sha256": FileAccess.get_sha256(state_path).to_lower(),
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"static_memory_peak_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
	}
	if not _write_json_atomic(result_path, proof):
		return {"ok": false, "exit_code": 10, "error": "cannot persist installed production result"}
	print("AURORA_INSTALLED_PRODUCTION_KNOWLEDGE_OK ", JSON.stringify(proof))
	return {"ok": true, "exit_code": 0, "proof": proof}


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
	return {"ok": true}


func _safe_pack_id(pack_id: String) -> String:
	var safe := pack_id.to_lower()
	for character in ["/", "\\", ":", "..", " "]:
		safe = safe.replace(character, "_")
	return safe


func _failure(result_path: String, started: int, message: String, code: int) -> Dictionary:
	var proof := {
		"schema": RESULT_SCHEMA,
		"passed": false,
		"installed": true,
		"offline": true,
		"external_ai_required": false,
		"error": message,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
	}
	if not result_path.is_empty():
		_write_json_atomic(result_path, proof)
	return {"ok": false, "exit_code": code, "error": message, "proof": proof}


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
