extends SceneTree

const KnowledgeSourceRegistryScript: Variant = preload("res://scripts/knowledge_source_registry.gd")

const RESULT_PREFIX := "AURORA_KNOWLEDGE_REGISTRY_SCALING_RESULT="
const ROOT := "user://knowledge_registry_scaling_probe"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE") != "1":
		_emit({"ok": false, "error": "benchmark destructive sentinel missing"}, 90)
		return
	var count := maxi(1, int(OS.get_environment("AURORA_REGISTRY_SCALING_COUNT")))
	var source_kb := maxi(1, int(OS.get_environment("AURORA_REGISTRY_SCALING_SOURCE_KB")))
	_reset_state()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var registry: Variant = KnowledgeSourceRegistryScript.new()
	var started := Time.get_ticks_usec()
	for i in range(count):
		var path := ROOT.path_join("registry_%05d_данные file.txt" % i)
		if not _write_source(path, i, source_kb * 1024):
			_emit({"ok": false, "error": "source generation failed", "index": i}, 2)
			return
		var inspection: Variant = registry.call("inspect_file", path)
		if not (inspection is Dictionary and bool(inspection.get("ok", false))):
			_emit({"ok": false, "error": "registry inspection failed", "index": i, "inspection": inspection}, 3)
			return
		var marked: Variant = registry.call("mark_imported", path, inspection, {"chunks": 1, "records": 1, "routed": {"knowledge": 1}}, {"imported_by": "registry_scaling_probe", "parser_version": "1"})
		if not (marked is Dictionary and bool(marked.get("ok", false))):
			_emit({"ok": false, "error": "registry mark failed", "index": i, "marked": marked}, 4)
			return
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var stats: Variant = registry.call("stats")
	var restarted: Variant = KnowledgeSourceRegistryScript.new()
	var restart_started := Time.get_ticks_usec()
	var persisted: Variant = restarted.call("sources")
	var restart_ms := float(Time.get_ticks_usec() - restart_started) / 1000.0
	var ok := stats is Dictionary and int(stats.get("sources", -1)) == count
	ok = ok and persisted is Array and persisted.size() == count
	_emit({
		"ok": ok,
		"source_count": count,
		"source_size_kb": source_kb,
		"register_duration_ms": elapsed_ms,
		"sources_per_sec": float(count) / maxf(0.001, elapsed_ms / 1000.0),
		"registry_size_bytes": int(stats.get("bytes", 0)) if stats is Dictionary else 0,
		"restart_load_ms": restart_ms,
		"restart_source_count": persisted.size() if persisted is Array else -1,
		"network_required": false,
		"external_runtime_required": false,
		"ollama_required": false
	}, 0 if ok else 5)

func _write_source(path: String, index: int, target_bytes: int) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var line := "registry_%05d AuroraFox unique payload данные %s\n" % [index, "x".repeat(256)]
	while file.get_position() < target_bytes:
		file.store_string(line)
	file.close()
	return true

func _reset_state() -> void:
	var paths: Array[String] = [str(KnowledgeSourceRegistryScript.REGISTRY_PATH)]
	var constants: Dictionary = KnowledgeSourceRegistryScript.get_script_constant_map()
	for name in ["REGISTRY_TEMP", "REGISTRY_ORIGINAL"]:
		if constants.has(name):
			paths.append(str(constants.get(name, "")))
	for path in paths:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _emit(result: Dictionary, code: int) -> void:
	print(RESULT_PREFIX + JSON.stringify(result))
	quit(code)
