class_name KnowledgePackInstaller
extends RefCounted

const PACK_SCHEMA := "aurorafox.knowledge-pack.v1"
const RECORD_SCHEMA := "aurorafox.knowledge-record.v1"
const MIN_PRODUCTION_CONTENT_BYTES := 1024 * 1024 * 1024
const STATE_DIR := "user://knowledge/pack-installs"

var transaction := KnowledgeImportTransaction.new()

func inspect(pack_dir: String) -> Dictionary:
	var manifest_path := pack_dir.path_join("manifest.json")
	var manifest := _read_json(manifest_path)
	if not bool(manifest.get("ok", false)):
		return manifest
	var data: Dictionary = manifest.get("value", {})
	if str(data.get("schema", "")) != PACK_SCHEMA:
		return _fail("Unsupported Knowledge Pack schema")
	if str(data.get("record_schema", "")) != RECORD_SCHEMA:
		return _fail("Unsupported Knowledge record schema")
	var pack_id := str(data.get("pack_id", "")).strip_edges()
	var pack_version := str(data.get("pack_version", "")).strip_edges()
	if pack_id.is_empty() or pack_version.is_empty():
		return _fail("Knowledge Pack identity is incomplete")
	if bool(data.get("production", false)) and int(data.get("content_bytes", 0)) < MIN_PRODUCTION_CONTENT_BYTES:
		return _fail("Production Knowledge Pack content is below 1 GiB")
	var source = data.get("source", {})
	if not source is Dictionary or str(source.get("license", "")).is_empty() or str(source.get("attribution", "")).is_empty():
		return _fail("Knowledge Pack license/attribution is incomplete")
	var shards = data.get("shards", [])
	if not shards is Array or shards.is_empty():
		return _fail("Knowledge Pack has no shards")
	var seen := {}
	var checked: Array = []
	var total_bytes := 0
	var total_content_bytes := 0
	var total_records := 0
	var shard_limit := int(data.get("shard_limit_bytes", 0))
	if shard_limit <= 0:
		return _fail("Knowledge Pack shard limit is invalid")
	for value in shards:
		if not value is Dictionary:
			return _fail("Knowledge Pack shard declaration is invalid")
		var shard: Dictionary = value
		var relative := str(shard.get("path", ""))
		if not _safe_member_name(relative) or seen.has(relative):
			return _fail("Unsafe or duplicate Knowledge Pack shard: " + relative)
		seen[relative] = true
		var path := pack_dir.path_join(relative)
		if not FileAccess.file_exists(path):
			return _fail("Knowledge Pack shard is missing: " + relative)
		var size := _file_size(path)
		var expected_size := int(shard.get("bytes", -1))
		if size != expected_size or size > shard_limit:
			return _fail("Knowledge Pack shard size mismatch: " + relative)
		var expected_sha := str(shard.get("sha256", "")).to_lower()
		var actual_sha := FileAccess.get_sha256(path).to_lower()
		if expected_sha.length() != 64 or actual_sha != expected_sha:
			return _fail("Knowledge Pack shard SHA-256 mismatch: " + relative)
		total_bytes += size
		total_content_bytes += int(shard.get("content_bytes", 0))
		total_records += int(shard.get("records", 0))
		checked.append({"path": path, "relative_path": relative, "sha256": actual_sha, "bytes": size})
	if total_bytes != int(data.get("file_bytes", -1)):
		return _fail("Knowledge Pack aggregate file size mismatch")
	if total_content_bytes != int(data.get("content_bytes", -1)):
		return _fail("Knowledge Pack aggregate content size mismatch")
	if total_records != int(data.get("record_count", -1)):
		return _fail("Knowledge Pack aggregate record count mismatch")
	return {
		"ok": true,
		"pack_id": pack_id,
		"pack_version": pack_version,
		"manifest_path": manifest_path,
		"manifest_sha256": FileAccess.get_sha256(manifest_path).to_lower(),
		"manifest": data,
		"shards": checked,
		"shard_count": checked.size(),
		"file_bytes": total_bytes,
		"content_bytes": total_content_bytes,
		"record_count": total_records,
	}

func install(store: KnowledgeStore, pack_dir: String) -> Dictionary:
	var checked := inspect(pack_dir)
	if not bool(checked.get("ok", false)):
		return checked
	var state_path := _state_path(str(checked.get("pack_id", "")))
	var state := _load_state(state_path, checked)
	var completed: Array = state.get("completed_shards", []) if state.get("completed_shards", []) is Array else []
	var imported := 0
	var skipped := 0
	for value in checked.get("shards", []):
		var shard: Dictionary = value
		var sha := str(shard.get("sha256", ""))
		if sha in completed:
			skipped += 1
			continue
		var result := transaction.import_file(store, str(shard.get("path", "")), {
			"scope": "core_knowledge",
			"imported_by": "production_knowledge_pack",
			"pack_id": checked.get("pack_id", ""),
			"pack_version": checked.get("pack_version", ""),
			"pack_manifest_sha256": checked.get("manifest_sha256", ""),
			"shard_sha256": sha,
			"untrusted_external": true,
		})
		if not bool(result.get("ok", false)):
			return {
				"ok": false,
				"error": str(result.get("error", "Knowledge Pack shard import failed")),
				"failed_shard": shard.get("relative_path", ""),
				"completed_shards": completed.size(),
				"resumable": true,
				"import_result": result,
			}
		completed.append(sha)
		state["completed_shards"] = completed
		state["updated_at"] = Time.get_datetime_string_from_system(true)
		if not _write_json_atomic(state_path, state):
			return _fail("Could not persist Knowledge Pack install progress")
		imported += 1
	state["status"] = "ready"
	state["completed_at"] = Time.get_datetime_string_from_system(true)
	if not _write_json_atomic(state_path, state):
		return _fail("Could not persist completed Knowledge Pack state")
	return {
		"ok": true,
		"status": "ready",
		"pack_id": checked.get("pack_id", ""),
		"pack_version": checked.get("pack_version", ""),
		"shards": checked.get("shard_count", 0),
		"imported_shards": imported,
		"skipped_shards": skipped,
		"resumable": true,
		"offline": true,
		"external_ai_required": false,
	}

func _load_state(path: String, checked: Dictionary) -> Dictionary:
	var loaded := _read_json(path)
	var state: Dictionary = loaded.get("value", {}) if bool(loaded.get("ok", false)) else {}
	if (
		str(state.get("pack_id", "")) != str(checked.get("pack_id", ""))
		or str(state.get("pack_version", "")) != str(checked.get("pack_version", ""))
		or str(state.get("manifest_sha256", "")) != str(checked.get("manifest_sha256", ""))
	):
		state = {
			"schema": "aurorafox.knowledge-pack-install.v1",
			"pack_id": checked.get("pack_id", ""),
			"pack_version": checked.get("pack_version", ""),
			"manifest_sha256": checked.get("manifest_sha256", ""),
			"status": "installing",
			"completed_shards": [],
		}
	return state

func _state_path(pack_id: String) -> String:
	var safe := pack_id.to_lower()
	for character in ["/", "\\", ":", "..", " "]:
		safe = safe.replace(character, "_")
	return STATE_DIR.path_join(safe + ".json")

func _safe_member_name(value: String) -> bool:
	return (
		not value.is_empty()
		and value.get_file() == value
		and not value.begins_with(".")
		and value.get_extension().to_lower() in ["jsonl", "ndjson"]
	)

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("JSON file is missing: " + path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Could not open JSON file: " + path)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return _fail("Invalid JSON object: " + path)
	return {"ok": true, "value": parsed}

func _write_json_atomic(path: String, value: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  "))
	file.flush()
	file.close()
	var absolute := ProjectSettings.globalize_path(path)
	var temp_absolute := ProjectSettings.globalize_path(temp)
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(absolute) != OK:
		DirAccess.remove_absolute(temp_absolute)
		return false
	return DirAccess.rename_absolute(temp_absolute, absolute) == OK

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
