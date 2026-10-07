extends SceneTree

class IsolatedResearch extends AuroraResearchCollector:
	func _save_source_health() -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var url := OS.get_environment("AURORAFOX_RESEARCH_FIXTURE_URL")
	assert(url.begins_with("http://127.0.0.1:"))
	var original := OwnerResourcePolicy._cached.duplicate()
	OwnerResourcePolicy._cached = OwnerResourcePolicy.DEFAULTS.duplicate()
	var collector := IsolatedResearch.new()
	root.add_child(collector)
	OwnerResourcePolicy._cached.research_response_bytes = 2 * 1024 * 1024
	var denied: Dictionary = await collector._request_text(url, "fixture_default")
	assert(not denied.ok and denied.result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED)
	OwnerResourcePolicy._cached.research_response_bytes = 2 * 1024 * 1024 + 1
	var exact: Dictionary = await collector._request_text(url, "fixture_exact")
	assert(exact.ok and str(exact.text).length() == 2 * 1024 * 1024 + 1)
	OwnerResourcePolicy._cached.research_response_bytes = 0
	var unlimited: Dictionary = await collector._request_text(url, "fixture_unlimited")
	assert(unlimited.ok and str(unlimited.text) == str(exact.text))
	assert(str(unlimited.text).sha256_text() == "x".repeat(2 * 1024 * 1024 + 1).sha256_text())
	collector.queue_free()
	OwnerResourcePolicy._cached = original
	OwnerResourcePolicy.revision += 1
	await process_frame
	print("AURORA_RESEARCH_OWNER_HTTP_BYTES_OK bytes=2097153")
	quit(0)
