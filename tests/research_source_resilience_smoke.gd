extends SceneTree

func _fail(message: String, code: int) -> void:
	push_error(message)
	_cleanup()
	quit(code)

func _cleanup() -> void:
	for path in [
		AuroraResearchCollector.SOURCE_HEALTH_PATH,
		AuroraResearchCollector.SOURCE_HEALTH_TEMP_PATH
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_cleanup()
	var collector := AuroraResearchCollector.new()
	root.add_child(collector)
	collector._source_health.clear()

	var scrubbed := collector._external_query("owner@example.com C:\\Users\\Owner\\secret.txt https://private.example/token=abc local AI retrieval Godot token=secret")
	if scrubbed.contains("@") or scrubbed.contains("private.example") or scrubbed.contains("secret.txt") or scrubbed.contains("token=secret"):
		_fail("External research query retained a high-risk local identifier", 2)
		return
	if not scrubbed.contains("local") or not scrubbed.contains("retrieval"):
		_fail("External query scrubbing removed ordinary research terms", 3)
		return
	if scrubbed.length() > AuroraResearchCollector.MAX_EXTERNAL_QUERY_CHARS:
		_fail("External query exceeded its hard character bound", 4)
		return

	var endpoint := collector._safe_endpoint("https://api.github.com/search/repositories?q=owner%40example.com")
	if endpoint != "api.github.com":
		_fail("Error endpoint sanitization retained path/query material", 5)
		return
	collector._request_errors.clear()
	collector._record_request_error("http", "github", "https://api.github.com/search/repositories?q=owner%40example.com", 503, 0, "temporary upstream failure")
	var serialized_errors := JSON.stringify(collector._request_errors)
	if serialized_errors.contains("owner") or serialized_errors.contains("repositories?q"):
		_fail("Research error telemetry leaked outbound query content", 6)
		return

	collector._record_source_failure("github", 503, "http")
	var first: Dictionary = collector._source_health.get("github", {})
	if int(first.get("failures", 0)) != 1 or int(first.get("next_retry_unix", 0)) <= int(Time.get_unix_time_from_system()):
		_fail("First source failure did not create bounded retry backoff", 7)
		return
	collector._record_source_failure("github", 503, "http")
	var second: Dictionary = collector._source_health.get("github", {})
	if int(second.get("failures", 0)) != 2:
		_fail("Repeated source failure did not accumulate health state", 8)
		return
	if int(second.get("next_retry_unix", 0)) <= int(first.get("next_retry_unix", 0)):
		_fail("Repeated source failure did not increase retry delay", 9)
		return
	if collector._can_request_source("github"):
		_fail("Backed-off source was immediately requestable", 10)
		return
	var health_report := collector._source_health_report()
	if not health_report.has("github") or int((health_report.get("github", {}) as Dictionary).get("failures", 0)) != 2:
		_fail("Source health was not exposed as non-sensitive diagnostics", 11)
		return

	var reloaded := AuroraResearchCollector.new()
	reloaded._load_source_health()
	if not reloaded._source_health.has("github") or int((reloaded._source_health.get("github", {}) as Dictionary).get("failures", 0)) != 2:
		_fail("Source retry state did not survive restart", 12)
		return
	reloaded._record_source_success("github")
	if reloaded._source_health.has("github"):
		_fail("Successful source recovery did not close the circuit", 13)
		return

	collector._collection_deadline_msec = Time.get_ticks_msec() - 1
	if collector._remaining_timeout_seconds() != 0.0:
		_fail("Expired global collection budget still allowed a network request", 14)
		return
	collector._collection_deadline_msec = Time.get_ticks_msec() + 5000
	var remaining := collector._remaining_timeout_seconds()
	if remaining <= 0.0 or remaining > 5.0 or remaining > AuroraResearchCollector.REQUEST_TIMEOUT_SECONDS:
		_fail("Per-request timeout did not respect the remaining global budget", 15)
		return

	collector.queue_free()
	reloaded.free()
	await process_frame
	_cleanup()
	print("AURORA_RESEARCH_SOURCE_RESILIENCE_SMOKE_OK")
	quit(0)
