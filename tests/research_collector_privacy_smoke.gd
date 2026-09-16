extends SceneTree

class FakeExternalCollector:
	extends AuroraResearchCollector

	func _collect_github(_query: String) -> Array:
		return [_item("github", "example/repo", "External repository observation for privacy smoke.", "https://github.com/example/repo", {"stars": 10})]

	func _collect_stackoverflow(_query: String) -> Array:
		return [_item("stackoverflow", "External QA", "score=3 answers=1", "https://stackoverflow.com/questions/1/example")]

	func _collect_reddit(subreddit: String) -> Array:
		return [_item("reddit/r/" + subreddit, "External discussion", "Public discussion observation.", "https://www.reddit.com/r/%s/comments/example" % subreddit)]

	func _collect_arxiv(_query: String) -> Array:
		return [_item("arxiv", "External paper", "Public research observation for bounded autonomous collection.", "https://arxiv.org/abs/2609.99999")]

func _fail(message: String, code: int) -> void:
	push_error(message)
	_cleanup()
	quit(code)

func _cleanup() -> void:
	for path in [AuroraResearchCollector.LOG_PATH, AuroraResearchCollector.LOG_BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_cleanup()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AuroraResearchCollector.LOG_PATH.get_base_dir()))
	var oversized := FileAccess.open(AuroraResearchCollector.LOG_PATH, FileAccess.WRITE)
	if oversized == null:
		_fail("Could not create oversized research audit log fixture", 2)
		return
	var filler := PackedByteArray()
	filler.resize(AuroraResearchCollector.MAX_LOG_BYTES)
	oversized.store_buffer(filler)
	oversized.close()

	var collector := FakeExternalCollector.new()
	root.add_child(collector)
	var report: Dictionary = await collector.collect("privacy boundary")
	if not bool(report.get("ok", false)):
		_fail("External-only collector returned failure", 3)
		return
	if str(report.get("research_scope", "")) != "external_observations_only":
		_fail("Research scope is not explicitly external-only", 4)
		return
	if bool(report.get("personal_files_scanned", true)):
		_fail("Collector reported personal file scanning", 5)
		return
	if not bool(report.get("curation_required", false)) or int(report.get("learned", -1)) != 0:
		_fail("Collector bypassed curator authority", 6)
		return
	if int(report.get("network_response_limit_bytes", 0)) != AuroraResearchCollector.MAX_RESPONSE_BYTES:
		_fail("Collector did not expose its bounded network response contract", 7)
		return
	if int(report.get("audit_log_limit_bytes", 0)) != AuroraResearchCollector.MAX_LOG_BYTES:
		_fail("Collector did not expose its bounded audit log contract", 8)
		return
	var items: Array = report.get("items", [])
	if items.size() != 5:
		_fail("Unexpected external observation count", 9)
		return
	for item in items:
		if not item is Dictionary:
			_fail("Collector returned malformed observation", 10)
			return
		if str(item.get("source", "")) == "local_documents":
			_fail("Autonomous collector returned a personal local-document observation", 11)
			return
	var counts: Dictionary = report.get("sources", {})
	if counts.has("local_documents"):
		_fail("Autonomous source counts contain local_documents", 12)
		return
	if not FileAccess.file_exists(AuroraResearchCollector.LOG_BACKUP_PATH):
		_fail("Oversized research audit log was not rotated", 13)
		return
	var active_size := _file_size(AuroraResearchCollector.LOG_PATH)
	if active_size <= 0 or active_size >= AuroraResearchCollector.MAX_LOG_BYTES:
		_fail("Active research audit log did not restart within its bound", 14)
		return
	if _file_size(AuroraResearchCollector.LOG_BACKUP_PATH) < AuroraResearchCollector.MAX_LOG_BYTES:
		_fail("Rotated research audit log did not preserve the previous segment", 15)
		return
	collector.queue_free()
	await process_frame
	_cleanup()
	print("AURORA_RESEARCH_COLLECTOR_PRIVACY_SMOKE_OK")
	quit(0)
