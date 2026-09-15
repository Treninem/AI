extends SceneTree

var _paths: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	_cleanup_files()
	quit(code)

func _run() -> void:
	var store := KnowledgeStore.new()
	var txn := KnowledgeImportTransaction.new()
	var manager := KnowledgeManager.new()

	var jsonl := "user://aurora_streaming_knowledge_test.jsonl"
	_paths.append(jsonl)
	manager.remove_source(jsonl)
	var out := FileAccess.open(jsonl, FileAccess.WRITE)
	if out == null:
		_fail("Cannot create streaming JSONL fixture", 2)
		return
	for i in range(420):
		var row := {
			"kind": "fact" if i % 3 == 0 else "example",
			"index": i,
			"title": "Aurora streaming record %d" % i,
			"content": "streaming dataset value %d" % i
		}
		if i == 419:
			row["content"] = "AURORA_UNIQUE_LATE_STREAM_MARKER_419"
		out.store_line(JSON.stringify(row))
	out.close()

	var imported := txn.import_file(store, jsonl, {"imported_by": "large_streaming_smoke"})
	if not bool(imported.get("ok", false)):
		_fail("Streaming JSONL import failed: " + JSON.stringify(imported), 3)
		return
	if not bool(imported.get("streaming", false)):
		_fail("JSONL import did not use streaming path", 4)
		return
	if int(imported.get("records", 0)) != 420:
		_fail("Streaming JSONL record count mismatch: " + JSON.stringify(imported), 5)
		return
	var found := store.search("AURORA_UNIQUE_LATE_STREAM_MARKER_419", 5)
	if found.is_empty():
		_fail("Streaming search could not find a late JSONL record", 6)
		return
	var stats := manager.stats()
	if not bool(stats.get("streaming_index", false)):
		_fail("KnowledgeManager does not advertise streaming index scan", 7)
		return

	# Exercise the large-text streaming implementation directly without placing
	# an artificial multi-megabyte fixture into CI.
	var text_path := "user://aurora_streaming_large_text_test.txt"
	_paths.append(text_path)
	manager.remove_source(text_path)
	var text_file := FileAccess.open(text_path, FileAccess.WRITE)
	if text_file == null:
		_fail("Cannot create streaming text fixture", 8)
		return
	for i in range(900):
		var payload := "paragraph %d AuroraFox streaming text knowledge" % i
		if i == 899:
			payload += " AURORA_STREAM_TEXT_LAST_MARKER"
		text_file.store_line(payload)
	text_file.close()
	var text_import := store.import_large_text_file(text_path, {"imported_by": "large_streaming_smoke"})
	if not bool(text_import.get("ok", false)) or not bool(text_import.get("streaming", false)):
		_fail("Large text streaming path failed: " + JSON.stringify(text_import), 9)
		return
	if store.search("AURORA_STREAM_TEXT_LAST_MARKER", 5).is_empty():
		_fail("Streaming search could not find late text marker", 10)
		return

	var removed_jsonl := manager.remove_source(jsonl)
	if not bool(removed_jsonl.get("ok", false)) or int(removed_jsonl.get("removed", 0)) <= 0:
		_fail("Streaming JSONL source removal failed: " + JSON.stringify(removed_jsonl), 11)
		return
	var removed_text := manager.remove_source(text_path)
	if not bool(removed_text.get("ok", false)) or int(removed_text.get("removed", 0)) <= 0:
		_fail("Streaming text source removal failed: " + JSON.stringify(removed_text), 12)
		return
	if not store.search("AURORA_UNIQUE_LATE_STREAM_MARKER_419", 5).is_empty():
		_fail("Removed JSONL source is still searchable", 13)
		return
	if not store.search("AURORA_STREAM_TEXT_LAST_MARKER", 5).is_empty():
		_fail("Removed text source is still searchable", 14)
		return

	_cleanup_files()
	print("AURORA_LARGE_KNOWLEDGE_STREAMING_SMOKE_OK jsonl=420 streaming=true search=true remove=true")
	quit(0)

func _cleanup_files() -> void:
	for path in _paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
