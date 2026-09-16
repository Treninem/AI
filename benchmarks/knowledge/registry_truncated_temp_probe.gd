extends SceneTree

# Dynamic handle keeps the durability probe independent from editor class cache.
const KnowledgeSourceRegistryScript: Variant = preload("res://scripts/knowledge_source_registry.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_TRUNCATED_REGISTRY_RESULT="
const PROBE_ROOT := "user://knowledge_registry_truncated_probe"
const SOURCE := PROBE_ROOT + "/source.txt"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	_cleanup_path(KnowledgeSourceRegistryScript.REGISTRY_TEMP)
	_cleanup_path(KnowledgeSourceRegistryScript.REGISTRY_ORIGINAL)
	_cleanup_path(KnowledgeSourceRegistryScript.REGISTRY_PATH)
	_cleanup_path(SOURCE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROBE_ROOT))

	var source_file := FileAccess.open(SOURCE, FileAccess.WRITE)
	if source_file == null:
		_emit({"ok": false, "error": "cannot create registry durability source"}, 2)
		return
	source_file.store_string("AuroraFox durable registry source marker")
	source_file.close()

	var registry: Variant = KnowledgeSourceRegistryScript.new()
	var inspection: Variant = registry.call("inspect_file", SOURCE)
	if not bool(inspection.get("ok", false)):
		_emit({"ok": false, "error": "initial registry inspection failed", "inspection": inspection}, 2)
		return
	var marked: Variant = registry.call("mark_imported", SOURCE, inspection, {"chunks": 1}, {"imported_by": "registry_truncated_temp_probe"})
	if not bool(marked.get("ok", false)):
		_emit({"ok": false, "error": "initial registry seed failed", "marked": marked}, 2)
		return
	var before: Variant = registry.call("record_for_source", SOURCE)
	var expected_fingerprint := str(before.get("fingerprint_sha256", ""))

	# Simulate a disk-full/interrupted registry write that left an existing but
	# truncated temporary JSON file. Replacement must reject it before moving the
	# last committed sources.json out of the way.
	var malformed := FileAccess.open(KnowledgeSourceRegistryScript.REGISTRY_TEMP, FileAccess.WRITE)
	if malformed == null:
		_emit({"ok": false, "error": "cannot create malformed registry temp"}, 2)
		return
	malformed.store_string('{"schema_version":1,"sources":[')
	malformed.close()

	var promoted := bool(registry.call("_replace_registry_file"))
	KnowledgeSourceRegistryScript.invalidate_runtime_cache()
	var restarted: Variant = KnowledgeSourceRegistryScript.new()
	var after: Variant = restarted.call("record_for_source", SOURCE)
	var target_valid := _registry_is_valid(KnowledgeSourceRegistryScript.REGISTRY_PATH)
	var temp_gone := not FileAccess.file_exists(KnowledgeSourceRegistryScript.REGISTRY_TEMP)
	var original_gone := not FileAccess.file_exists(KnowledgeSourceRegistryScript.REGISTRY_ORIGINAL)
	var fingerprint_preserved := not after.is_empty() and str(after.get("fingerprint_sha256", "")) == expected_fingerprint
	var ok := not promoted and target_valid and fingerprint_preserved and temp_gone and original_gone
	_emit({
		"ok": ok,
		"malformed_temp_promoted": promoted,
		"canonical_registry_valid": target_valid,
		"source_preserved_after_restart": not after.is_empty(),
		"fingerprint_preserved": fingerprint_preserved,
		"temp_removed": temp_gone,
		"stale_original_absent": original_gone,
		"expected_fingerprint": expected_fingerprint,
		"actual_fingerprint": str(after.get("fingerprint_sha256", ""))
	}, 0 if ok else 3)

func _registry_is_valid(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed is Dictionary and parsed.get("sources", null) is Array

func _cleanup_path(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _emit(payload: Dictionary, code: int) -> void:
	print(RESULT_PREFIX + JSON.stringify(payload))
	quit(code)
