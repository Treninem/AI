class_name AuroraResearchCollector
extends Node

signal research_completed(report: Dictionary)

const LOG_PATH := "user://agent/research.jsonl"
const LOG_BACKUP_PATH := "user://agent/research.jsonl.1"
const SOURCE_HEALTH_PATH := "user://agent/research_source_health.json"
const SOURCE_HEALTH_TEMP_PATH := "user://agent/research_source_health.json.tmp"
const MAX_ITEMS_PER_SOURCE := 5
const MAX_SUMMARY_CHARS := 1800
const MAX_RESPONSE_BYTES := 2 * 1024 * 1024
const MAX_LOG_BYTES := 8 * 1024 * 1024
const MAX_SOURCE_ERRORS := 16
const MAX_EXTERNAL_QUERY_CHARS := 240
const MAX_EXTERNAL_QUERY_WORDS := 24
const REQUEST_TIMEOUT_SECONDS := 20.0
const COLLECTION_BUDGET_SECONDS := 45.0
const SOURCE_BACKOFF_BASE_SECONDS := 5 * 60
const SOURCE_BACKOFF_MAX_SECONDS := 6 * 60 * 60
const SOURCE_BACKOFF_MAX_FAILURES := 8

# Kept for setup/API compatibility with AutonomousCoordinator. The collector
# deliberately never writes to MemoryStore: durable automatic learning is owned
# by AuroraLearningCurator after quality/provenance/deduplication checks.
var memory: MemoryStore
var tools: ToolRegistry
var _busy := false
var _request_errors: Array = []
var _source_health: Dictionary = {}
var _collection_deadline_msec := 0

func setup(memory_store: MemoryStore, tool_registry: ToolRegistry) -> void:
	memory = memory_store
	tools = tool_registry
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_PATH.get_base_dir()))
	_load_source_health()

func collect(query: String) -> Dictionary:
	if _busy:
		return {"ok": false, "error": "Research collector is already running"}
	_busy = true
	_request_errors.clear()
	var clean_query := query.strip_edges()
	if clean_query.is_empty():
		clean_query = "local AI Godot LLM context optimization"
	var external_query := _external_query(clean_query)
	_collection_deadline_msec = Time.get_ticks_msec() + int(COLLECTION_BUDGET_SECONDS * 1000.0)
	var items: Array = []

	# Autonomous research is external-observation only. Personal/local documents
	# are never scanned implicitly here; they enter AuroraFox only through the
	# explicit user-controlled Knowledge/import flow. Only the bounded, scrubbed
	# external query leaves the device; the original local query remains local.
	items.append_array(await _collect_github(external_query))
	items.append_array(await _collect_stackoverflow(external_query))
	items.append_array(await _collect_reddit("LocalLLaMA"))
	items.append_array(await _collect_reddit("MachineLearning"))
	items.append_array(await _collect_arxiv(external_query))

	# Observation-only boundary: every external item is logged for audit/curation,
	# but no item is allowed to reach long-term memory/Core Knowledge here. This
	# avoids bypassing LearningCurator with low-quality or duplicate web data.
	for item in items:
		if item is Dictionary:
			_append_log(item)
	var source_errors := _request_errors.duplicate(true)
	var complete_failure := items.is_empty() and not source_errors.is_empty()
	var partial := not items.is_empty() and not source_errors.is_empty()
	var report := {
		"ok": not complete_failure,
		"partial": partial,
		"query": clean_query,
		"items": items,
		"count": items.size(),
		"queued_for_curation": items.size(),
		"curation_required": true,
		"research_scope": "external_observations_only",
		"personal_files_scanned": false,
		"external_query_limited": true,
		"external_query_char_count": external_query.length(),
		"network_response_limit_bytes": MAX_RESPONSE_BYTES,
		"audit_log_limit_bytes": MAX_LOG_BYTES,
		"collection_budget_seconds": COLLECTION_BUDGET_SECONDS,
		"source_error_count": source_errors.size(),
		"source_errors": source_errors,
		"source_backoff": _source_health_report(),
		# Backward-compatible field. Automatic promotion happens asynchronously in
		# LearningCurator after research_completed, so nothing is learned here.
		"learned": 0,
		"sources": _source_counts(items),
		"timestamp_unix": int(Time.get_unix_time_from_system())
	}
	if complete_failure:
		report["error"] = "All autonomous research sources failed"
	_collection_deadline_msec = 0
	_busy = false
	research_completed.emit(report)
	return report

func _collect_github(query: String) -> Array:
	var encoded := query.uri_encode()
	var result := await _request_json("https://api.github.com/search/repositories?q=%s&sort=updated&order=desc&per_page=%d" % [encoded, MAX_ITEMS_PER_SOURCE], "github")
	var out: Array = []
	if not result.get("ok", false):
		return out
	var data: Dictionary = result.get("data", {})
	var rows: Array = data.get("items", [])
	for row in rows:
		if row is Dictionary:
			out.append(_item("github", str(row.get("full_name", "")), str(row.get("description", "")), str(row.get("html_url", "")), {"stars": int(row.get("stargazers_count", 0)), "language": str(row.get("language", ""))}))
	return out

func _collect_stackoverflow(query: String) -> Array:
	var encoded := query.uri_encode()
	var result := await _request_json("https://api.stackexchange.com/2.3/search/advanced?site=stackoverflow&order=desc&sort=activity&q=%s&pagesize=%d" % [encoded, MAX_ITEMS_PER_SOURCE], "stackoverflow")
	var out: Array = []
	if not result.get("ok", false):
		return out
	var data: Dictionary = result.get("data", {})
	var rows: Array = data.get("items", [])
	for row in rows:
		if row is Dictionary:
			out.append(_item("stackoverflow", str(row.get("title", "")), "score=%d answers=%d" % [int(row.get("score", 0)), int(row.get("answer_count", 0))], str(row.get("link", ""))))
	return out

func _collect_reddit(subreddit: String) -> Array:
	var source_id := "reddit:" + subreddit
	var result := await _request_json("https://www.reddit.com/r/%s/hot.json?limit=%d&raw_json=1" % [subreddit.uri_encode(), MAX_ITEMS_PER_SOURCE], source_id)
	var out: Array = []
	if not result.get("ok", false):
		return out
	var data: Dictionary = result.get("data", {})
	var children: Array = data.get("children", [])
	for child in children:
		if not child is Dictionary:
			continue
		var row: Dictionary = child.get("data", {})
		out.append(_item("reddit/r/" + subreddit, str(row.get("title", "")), str(row.get("selftext", "")), "https://www.reddit.com" + str(row.get("permalink", "")), {"score": int(row.get("score", 0)), "comments": int(row.get("num_comments", 0))}))
	return out

func _collect_arxiv(query: String) -> Array:
	var encoded := query.replace(" ", "+").uri_encode()
	var url := "https://export.arxiv.org/api/query?search_query=all:%s&start=0&max_results=%d&sortBy=submittedDate&sortOrder=descending" % [encoded, MAX_ITEMS_PER_SOURCE]
	var result := await _request_text(url, "arxiv", false)
	var out: Array = []
	if not result.get("ok", false):
		return out
	var xml := str(result.get("text", ""))
	var parser := XMLParser.new()
	var parse_error := parser.open_buffer(xml.to_utf8_buffer())
	if parse_error != OK:
		_record_request_error("arxiv_xml", "arxiv", url, 0, parse_error, "Invalid arXiv XML")
		_record_source_failure("arxiv", 0, "arxiv_xml")
		return out
	var current_title := ""
	var current_summary := ""
	var current_link := ""
	var inside_entry := false
	var current_tag := ""
	while parser.read() == OK and out.size() < MAX_ITEMS_PER_SOURCE:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				current_tag = parser.get_node_name()
				if current_tag == "entry":
					inside_entry = true
					current_title = ""
					current_summary = ""
					current_link = ""
				elif inside_entry and current_tag == "link":
					for i in range(parser.get_attribute_count()):
						if parser.get_attribute_name(i) == "href":
							current_link = parser.get_attribute_value(i)
			XMLParser.NODE_TEXT:
				if inside_entry:
					if current_tag == "title":
						current_title += parser.get_node_data()
					elif current_tag == "summary":
						current_summary += parser.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var ended := parser.get_node_name()
				if ended == "entry" and inside_entry:
					out.append(_item("arxiv", current_title, current_summary, current_link))
					inside_entry = false
				current_tag = ""
	_record_source_success("arxiv")
	return out

func _request_json(url: String, source_id: String) -> Dictionary:
	var result := await _request_text(url, source_id, false)
	if not result.get("ok", false):
		return result
	var parsed = JSON.parse_string(str(result.get("text", "")))
	if not parsed is Dictionary:
		_record_request_error("json_parse", source_id, url, 0, 0, "Invalid JSON")
		_record_source_failure(source_id, 0, "json_parse")
		return {"ok": false, "error": "Invalid JSON", "source": source_id}
	_record_source_success(source_id)
	return {"ok": true, "data": parsed}

func _request_text(url: String, source_id: String, mark_success := true) -> Dictionary:
	if not _can_request_source(source_id):
		_record_request_error("source_backoff", source_id, url, 0, 0, "Source temporarily backed off after repeated failures")
		return {"ok": false, "error": "Source temporarily backed off", "source": source_id}
	var remaining_timeout := _remaining_timeout_seconds()
	if remaining_timeout <= 0.0:
		_record_request_error("collection_budget", source_id, url, 0, 0, "Autonomous research collection budget exhausted")
		return {"ok": false, "error": "Collection budget exhausted", "source": source_id}
	var req := HTTPRequest.new()
	# Keep the normal hard cap explicit, then reduce it to the remaining global
	# collection budget when less time remains.
	req.timeout = REQUEST_TIMEOUT_SECONDS
	if remaining_timeout < REQUEST_TIMEOUT_SECONDS:
		req.timeout = remaining_timeout
	req.body_size_limit = MAX_RESPONSE_BYTES
	add_child(req)
	var headers := PackedStringArray(["User-Agent: AuroraFox-Learning/1.3", "Accept: application/json, application/atom+xml, text/xml, text/plain;q=0.9"])
	var err := req.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		req.queue_free()
		_record_request_error("request_start", source_id, url, 0, err, error_string(err))
		_record_source_failure(source_id, 0, "request_start")
		return {"ok": false, "error": error_string(err), "source": source_id}
	var response: Array = await req.request_completed
	req.queue_free()
	var request_result := int(response[0])
	var code := int(response[1])
	var body := (response[3] as PackedByteArray).get_string_from_utf8()
	if request_result != HTTPRequest.RESULT_SUCCESS:
		_record_request_error("request_result", source_id, url, code, request_result, "Research request did not complete successfully")
		_record_source_failure(source_id, code, "request_result")
		return {"ok": false, "result": request_result, "http": code, "error": "Research request did not complete successfully", "source": source_id}
	if code < 200 or code >= 300:
		_record_request_error("http", source_id, url, code, request_result, body.substr(0, 240))
		_record_source_failure(source_id, code, "http")
		return {"ok": false, "http": code, "error": body.substr(0, 500), "source": source_id}
	if mark_success:
		_record_source_success(source_id)
	return {"ok": true, "text": body.substr(0, MAX_RESPONSE_BYTES), "source": source_id}

func _record_request_error(stage: String, source_id: String, url: String, http_code: int, result_code: int, message: String) -> void:
	if _request_errors.size() >= MAX_SOURCE_ERRORS:
		return
	_request_errors.append({
		"stage": stage.substr(0, 64),
		"source": source_id.substr(0, 96),
		"endpoint": _safe_endpoint(url),
		"http": http_code,
		"result": result_code,
		"error": _clean(message, 240)
	})

func _can_request_source(source_id: String) -> bool:
	var state: Dictionary = _source_health.get(source_id, {})
	return int(state.get("next_retry_unix", 0)) <= int(Time.get_unix_time_from_system())

func _record_source_failure(source_id: String, http_code: int, stage: String) -> void:
	if source_id.is_empty():
		return
	var previous: Dictionary = _source_health.get(source_id, {})
	var failures := mini(SOURCE_BACKOFF_MAX_FAILURES, int(previous.get("failures", 0)) + 1)
	var exponent := maxi(0, failures - 1)
	var delay := mini(SOURCE_BACKOFF_MAX_SECONDS, SOURCE_BACKOFF_BASE_SECONDS * int(pow(2.0, exponent)))
	var now := int(Time.get_unix_time_from_system())
	_source_health[source_id] = {
		"failures": failures,
		"next_retry_unix": now + delay,
		"last_failure_unix": now,
		"last_http": http_code,
		"last_stage": stage.substr(0, 64)
	}
	_save_source_health()

func _record_source_success(source_id: String) -> void:
	if source_id.is_empty() or not _source_health.has(source_id):
		return
	_source_health.erase(source_id)
	_save_source_health()

func _remaining_timeout_seconds() -> float:
	if _collection_deadline_msec <= 0:
		return REQUEST_TIMEOUT_SECONDS
	var remaining_msec := _collection_deadline_msec - Time.get_ticks_msec()
	if remaining_msec < 1000:
		return 0.0
	return minf(REQUEST_TIMEOUT_SECONDS, float(remaining_msec) / 1000.0)

func _external_query(query: String) -> String:
	var normalized := query.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	var accepted: Array[String] = []
	for raw in normalized.split(" ", false):
		var token := str(raw).strip_edges()
		if token.is_empty() or token.length() > 64:
			continue
		var lowered := token.to_lower()
		if token.contains("@") or token.contains("=") or token.contains("\\"):
			continue
		if token.contains("://") or lowered.begins_with("file:"):
			continue
		if token.begins_with("/") or token.begins_with("~/"):
			continue
		accepted.append(token)
		if accepted.size() >= MAX_EXTERNAL_QUERY_WORDS:
			break
	var result := " ".join(accepted).strip_edges().substr(0, MAX_EXTERNAL_QUERY_CHARS)
	if result.is_empty():
		return "local AI Godot LLM context optimization"
	return result

func _safe_endpoint(url: String) -> String:
	if url.is_empty():
		return ""
	var scheme_pos := url.find("://")
	var start := scheme_pos + 3 if scheme_pos >= 0 else 0
	var rest := url.substr(start)
	var slash_pos := rest.find("/")
	var host := rest.substr(0, slash_pos) if slash_pos >= 0 else rest
	var query_pos := host.find("?")
	if query_pos >= 0:
		host = host.substr(0, query_pos)
	return host.substr(0, 200)

func _source_health_report() -> Dictionary:
	var report: Dictionary = {}
	var now := int(Time.get_unix_time_from_system())
	for source_id in _source_health.keys():
		var state: Dictionary = _source_health.get(source_id, {})
		report[str(source_id)] = {
			"failures": int(state.get("failures", 0)),
			"retry_in_seconds": maxi(0, int(state.get("next_retry_unix", 0)) - now),
			"last_http": int(state.get("last_http", 0)),
			"last_stage": str(state.get("last_stage", "")).substr(0, 64)
		}
	return report

func _load_source_health() -> void:
	_source_health.clear()
	if not FileAccess.file_exists(SOURCE_HEALTH_PATH):
		return
	var file := FileAccess.open(SOURCE_HEALTH_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		for key in parsed.keys():
			var source_id := str(key).substr(0, 96)
			var value = parsed.get(key, {})
			if not source_id.is_empty() and value is Dictionary:
				_source_health[source_id] = (value as Dictionary).duplicate(true)

func _save_source_health() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SOURCE_HEALTH_PATH.get_base_dir()))
	var file := FileAccess.open(SOURCE_HEALTH_TEMP_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_source_health))
	file.flush()
	file.close()
	var temp_abs := ProjectSettings.globalize_path(SOURCE_HEALTH_TEMP_PATH)
	var target_abs := ProjectSettings.globalize_path(SOURCE_HEALTH_PATH)
	if FileAccess.file_exists(SOURCE_HEALTH_PATH):
		DirAccess.remove_absolute(target_abs)
	DirAccess.rename_absolute(temp_abs, target_abs)

func _item(source: String, title: String, summary: String, url: String = "", metadata: Dictionary = {}) -> Dictionary:
	return {
		"source": source,
		"title": _clean(title, 300),
		"summary": _clean(summary, MAX_SUMMARY_CHARS),
		"url": url,
		"metadata": metadata,
		"observed_at": Time.get_datetime_string_from_system(true)
	}

func _clean(value: String, limit: int) -> String:
	return " ".join(value.split(" ", false)).strip_edges().substr(0, limit)

func _append_log(item: Dictionary) -> void:
	_rotate_log_if_needed()
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify(item))
	file.close()

func _rotate_log_if_needed() -> void:
	if not FileAccess.file_exists(LOG_PATH):
		return
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		return
	var size := file.get_length()
	file.close()
	if size < MAX_LOG_BYTES:
		return
	var log_abs := ProjectSettings.globalize_path(LOG_PATH)
	var backup_abs := ProjectSettings.globalize_path(LOG_BACKUP_PATH)
	if FileAccess.file_exists(LOG_BACKUP_PATH):
		DirAccess.remove_absolute(backup_abs)
	DirAccess.rename_absolute(log_abs, backup_abs)

func _source_counts(items: Array) -> Dictionary:
	var counts: Dictionary = {}
	for item in items:
		if item is Dictionary:
			var source := str(item.get("source", "unknown"))
			counts[source] = int(counts.get(source, 0)) + 1
	return counts
