extends SceneTree

const BuildServiceScript = preload("res://scripts/knowledge_index_build_service.gd")
const IndexClientScript = preload("res://scripts/knowledge_index_client.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := ProjectSettings.globalize_path(KnowledgeStore.DB_PATH)
	if not source.to_lower().contains("index-build-service-profile"):
		_fail("isolated synthetic profile required")
		return
	var store := KnowledgeStore.new()
	var imported := store.import_text("Mars has two moons named Phobos and Deimos.", "synthetic://mars")
	if not bool(imported.get("ok", false)):
		_fail("synthetic import failed")
		return
	var service = BuildServiceScript.new()
	root.add_child(service)
	if not service.request_rebuild():
		_fail("background build did not start")
		return
	if not service.request_rebuild():
		_fail("second request was not coalesced")
		return
	var deadline := Time.get_ticks_msec() + 15000
	while (service.is_building() or service._pending) and Time.get_ticks_msec() < deadline:
		await process_frame
	if service.is_building() or service._pending:
		_fail("background build exceeded synthetic deadline")
		return
	await process_frame
	var result: Dictionary = IndexClientScript.search("mars moons", 8)
	if not bool(result.get("ok", false)):
		_fail("background index was not published")
		return
	imported = store.import_text("Mars has a third synthetic note.", "synthetic://mars-2")
	if not bool(imported.get("ok", false)) or bool(IndexClientScript.search("mars moons", 8).get("ok", false)):
		_fail("source mutation did not stale index")
		return
	if not service.request_rebuild():
		_fail("second background build did not start")
		return
	var child_pid: int = service._pid
	service.queue_free()
	await process_frame
	if child_pid > 0 and OS.is_process_running(child_pid):
		_fail("service shutdown retained child process")
		return
	var index_dir := ProjectSettings.globalize_path(IndexClientScript.INDEX_PATH).get_base_dir()
	var folder := DirAccess.open(index_dir)
	if folder == null:
		_fail("index directory disappeared after shutdown")
		return
	for name in folder.get_files():
		if name.ends_with(".building") or name.ends_with(".cancel"):
			_fail("service shutdown left a temporary build file")
			return
	print("KNOWLEDGE_INDEX_BUILD_SERVICE_SMOKE_PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
