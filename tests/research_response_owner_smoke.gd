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
	var slow_url := url.get_base_dir() + "/slow"
	OwnerResourcePolicy._cached.research_request_seconds = 1
	collector._collection_deadline_msec = 0
	var timed: Dictionary = await collector._request_text(slow_url, "fixture_request_timeout")
	assert(not timed.ok and timed.result == HTTPRequest.RESULT_TIMEOUT)
	OwnerResourcePolicy._cached.research_request_seconds = 0
	var no_deadline: Dictionary = await collector._request_text(slow_url, "fixture_no_timeout")
	assert(no_deadline.ok and str(no_deadline.text) == str(exact.text))
	collector._collection_deadline_msec = Time.get_ticks_msec() + 300
	var collection_timed: Dictionary = await collector._request_text(slow_url, "fixture_collection_timeout")
	assert(not collection_timed.ok and collection_timed.result == HTTPRequest.RESULT_TIMEOUT)
	collector._collection_deadline_msec = Time.get_ticks_msec() - 1
	var exhausted: Dictionary = await collector._request_text(slow_url, "fixture_exhausted")
	assert(not exhausted.ok and exhausted.error == "Collection budget exhausted")
	collector.queue_free()
	OwnerResourcePolicy._cached = original
	OwnerResourcePolicy.revision += 1
	await process_frame
	print("AURORA_RESEARCH_OWNER_HTTP_BYTES_OK bytes=2097153 timeouts=PASS")
	quit(0)
