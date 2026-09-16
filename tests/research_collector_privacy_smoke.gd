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
	if FileAccess.file_exists(AuroraResearchCollector.LOG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuroraResearchCollector.LOG_PATH))

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_cleanup()
	var collector := FakeExternalCollector.new()
	root.add_child(collector)
	var report: Dictionary = await collector.collect("privacy boundary")
	if not bool(report.get("ok", false)):
		_fail("External-only collector returned failure", 2)
		return
	if str(report.get("research_scope", "")) != "external_observations_only":
		_fail("Research scope is not explicitly external-only", 3)
		return
	if bool(report.get("personal_files_scanned", true)):
		_fail("Collector reported personal file scanning", 4)
		return
	if not bool(report.get("curation_required", false)) or int(report.get("learned", -1)) != 0:
		_fail("Collector bypassed curator authority", 5)
		return
	var items: Array = report.get("items", [])
	if items.size() != 5:
		_fail("Unexpected external observation count", 6)
		return
	for item in items:
		if not item is Dictionary:
			_fail("Collector returned malformed observation", 7)
			return
		if str(item.get("source", "")) == "local_documents":
			_fail("Autonomous collector returned a personal local-document observation", 8)
			return
	var counts: Dictionary = report.get("sources", {})
	if counts.has("local_documents"):
		_fail("Autonomous source counts contain local_documents", 9)
		return
	collector.queue_free()
	await process_frame
	_cleanup()
	print("AURORA_RESEARCH_COLLECTOR_PRIVACY_SMOKE_OK")
	quit(0)
