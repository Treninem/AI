extends SceneTree

func _init() -> void:
	var root := "user://knowledge_stream_monolithic_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var source := root.path_join("arbitrary_name.json")
	var file := FileAccess.open(source, FileAccess.WRITE)
	if file == null:
		_fail("cannot create monolithic JSON fixture", 2)
		return
	file.store_string("{\n  \"catalog\": {\n    \"templates\": [{\"name\":\"reply\",\"template\":\"AURORA_STREAM_MARKER {name}\"}],\n    \"algorithms\": [{\"title\":\"sort\",\"steps\":[\"read\",\"compare\",\"write\"]}],\n    \"escaped\": \"строка с \\\"кавычками\\\" и unicode ✓\",\n    \"flags\": [true, false, null, 42, 3.5]\n  }\n}")
	file.close()

	var store := KnowledgeStore.new()
	var importer := LargeJsonKnowledgeImporter.new()
	var result := importer.import_file(store, source, {"scope":"core_knowledge", "imported_by":"stream_smoke"})
	if not bool(result.get("ok", false)):
		_fail("stream importer failed: %s" % str(result), 3)
		return
	if str(result.get("stream_parser", "")) != "aurora_json_stream_v1":
		_fail("wrong stream parser marker", 4)
		return
	if int(result.get("stream_records", 0)) < 8:
		_fail("too few streamed records", 5)
		return
	if int(result.get("max_depth", 0)) < 3:
		_fail("nested JSON depth was not observed", 6)
		return
	var found := store.search("AURORA_STREAM_MARKER", 4)
	if found.is_empty():
		_fail("streamed knowledge was not searchable", 7)
		return
	var removed := store.remove_source(source)
	if not bool(removed.get("ok", false)) or int(removed.get("removed", 0)) <= 0:
		_fail("streamed source was not removable", 8)
		return

	var bad := root.path_join("broken.json")
	var broken := FileAccess.open(bad, FileAccess.WRITE)
	broken.store_string("{\"a\":[1,2,}")
	broken.close()
	var reader := AuroraJsonStreamReader.new()
	var bad_result := reader.parse_file(bad, func(_path: String, _value: Variant) -> bool: return true)
	if bool(bad_result.get("ok", false)):
		_fail("broken JSON was accepted", 9)
		return
	if int(bad_result.get("byte_offset", 0)) <= 0:
		_fail("broken JSON did not report byte offset", 10)
		return

	var threshold_path := root.path_join("threshold.json")
	var threshold := FileAccess.open(threshold_path, FileAccess.WRITE)
	if threshold == null:
		_fail("cannot create threshold fixture", 11)
		return
	var block := " ".repeat(1024 * 1024)
	for _i in range(9):
		threshold.store_string(block)
	threshold.store_string("{\"value\":1}")
	threshold.close()
	if not importer.should_stream(threshold_path):
		_fail("large monolithic JSON did not select streaming route", 12)
		return

	for path in [source, bad, threshold_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))
	print("MONOLITHIC_JSON_STREAM_SMOKE_OK records=%d" % int(result.get("stream_records", 0)))
	quit(0)

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
