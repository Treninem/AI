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
var _request_error_count := 0
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
	_request_error_count = 0
	var clean_query := query.strip_edges()
	if clean_query.is_empty():
		clean_query = "local AI Godot LLM context optimization"
	var external_query := _external_query(clean_query)
	_start_collection_budget()
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
	var complete_failure := items.is_empty() and _request_error_count > 0
	var partial := not items.is_empty() and _request_error_count > 0
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
		"network_response_limit_bytes": OwnerResourcePolicy.value("research_response_bytes"),
		"audit_log_limit_bytes": OwnerResourcePolicy.value("research_log_bytes"),
		"collection_budget_seconds": OwnerResourcePolicy.value("research_collection_seconds"),
		"source_error_count": _request_error_count,
		"source_errors_truncated": _request_error_count > source_errors.size(),
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
	if remaining_timeout < 0.0:
		_record_request_error("collection_budget", source_id, url, 0, 0, "Autonomous research collection budget exhausted")
		return {"ok": false, "error": "Collection budget exhausted", "source": source_id}
	var req := HTTPRequest.new()
	# Zero disables the request deadline; a finite collection budget still applies.
	req.timeout = remaining_timeout
	req.body_size_limit = _response_byte_limit()
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
		_record_request_error("http", source_id, url, code, request_result, OwnerResourcePolicy.clip(_redact_credentials(body), "research_error_chars"))
		_record_source_failure(source_id, code, "http")
		return {"ok": false, "http": code, "error": OwnerResourcePolicy.clip(_redact_credentials(body), "research_http_error_chars"), "source": source_id}
	if mark_success:
		_record_source_success(source_id)
	return {"ok": true, "text": body, "source": source_id} # Already byte-bounded by HTTPRequest.

func _record_request_error(stage: String, source_id: String, url: String, http_code: int, result_code: int, message: String) -> void:
	_request_error_count += 1
	var error_budget := OwnerResourcePolicy.value("research_error_items")
	if error_budget > 0 and _request_errors.size() >= error_budget:
		return
	_request_errors.append({
		"stage": OwnerResourcePolicy.clip(stage, "research_stage_chars"),
		"source": source_id,
		"endpoint": _safe_endpoint(url),
		"http": http_code,
		"result": result_code,
		"error": OwnerResourcePolicy.clip(_clean(_redact_credentials(message), 0), "research_error_chars")
	})

func _can_request_source(source_id: String) -> bool:
	var state: Dictionary = _source_health.get(source_id, {})
	return int(state.get("next_retry_unix", 0)) <= int(Time.get_unix_time_from_system())

func _record_source_failure(source_id: String, http_code: int, stage: String) -> void:
	if source_id.is_empty():
		return
	var previous: Dictionary = _source_health.get(source_id, {})
	var failures := maxi(0, int(previous.get("failures", 0)))
	if failures < 9223372036854775807: failures += 1
	var failure_cap := OwnerResourcePolicy.value("research_backoff_failure_cap")
	if failure_cap > 0: failures = mini(failure_cap, failures)
	var delay := _backoff_delay(failures)
	var now := int(Time.get_unix_time_from_system())
	_source_health[source_id] = {
		"failures": failures,
		"next_retry_unix": now + mini(delay, 9223372036854775807 - now),
		"last_failure_unix": now,
		"last_http": http_code,
		"last_stage": OwnerResourcePolicy.clip(stage, "research_stage_chars")
	}
	_save_source_health()

func _record_source_success(source_id: String) -> void:
	if source_id.is_empty() or not _source_health.has(source_id):
		return
	_source_health.erase(source_id)
	_save_source_health()

func _start_collection_budget() -> void:
	var seconds := OwnerResourcePolicy.value("research_collection_seconds")
	_collection_deadline_msec = 0 if seconds == 0 else Time.get_ticks_msec() + seconds * 1000

func _remaining_timeout_seconds() -> float:
	var request_seconds := float(OwnerResourcePolicy.value("research_request_seconds"))
	if _collection_deadline_msec <= 0:
		return request_seconds
	var remaining_msec := _collection_deadline_msec - Time.get_ticks_msec()
	if remaining_msec <= 0:
		return -1.0 # Exhausted; zero is the engine's unlimited timeout.
	var remaining_seconds := float(remaining_msec) / 1000.0
	return remaining_seconds if request_seconds == 0.0 else minf(request_seconds, remaining_seconds)

func _backoff_delay(failures: int) -> int:
	var delay := OwnerResourcePolicy.value("research_backoff_base_seconds")
	if delay == 0: return 0
	var maximum := OwnerResourcePolicy.value("research_backoff_max_seconds")
	var ceiling := maximum if maximum > 0 else 9223372036854775807
	delay = mini(delay, ceiling)
	var exponent := maxi(0, failures - 1)
	# Saturation bounds work by signed integer representation, even with no owner cap.
	while exponent > 0 and delay < ceiling:
		if delay > ceiling / 2: return ceiling
		delay *= 2
		exponent -= 1
	return delay

func _external_query(query: String) -> String:
	var normalized := _redact_credentials(query).replace("\n", " ").replace("\r", " ").replace("\t", " ")
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
	return OwnerResourcePolicy.clip(host, "research_endpoint_chars")

func _source_health_report() -> Dictionary:
	var report: Dictionary = {}
	var now := int(Time.get_unix_time_from_system())
	for source_id in _source_health.keys():
		var state: Dictionary = _source_health.get(source_id, {})
		report[str(source_id)] = {
			"failures": int(state.get("failures", 0)),
			"retry_in_seconds": maxi(0, int(state.get("next_retry_unix", 0)) - now),
			"last_http": int(state.get("last_http", 0)),
			"last_stage": OwnerResourcePolicy.clip(str(state.get("last_stage", "")), "research_stage_chars")
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
			var source_id := str(key)
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
		"title": OwnerResourcePolicy.clip(_clean(title, 0), "research_title_chars"),
		"summary": OwnerResourcePolicy.clip(_clean(summary, 0), "research_summary_chars"),
		"url": url,
		"metadata": metadata,
		"title_truncated": OwnerResourcePolicy.value("research_title_chars") > 0 and _clean(title, 0).length() > OwnerResourcePolicy.value("research_title_chars"),
		"summary_truncated": OwnerResourcePolicy.value("research_summary_chars") > 0 and _clean(summary, 0).length() > OwnerResourcePolicy.value("research_summary_chars"),
		"observed_at": Time.get_datetime_string_from_system(true)
	}

func _clean(value: String, limit: int) -> String:
	var normalized := " ".join(value.split(" ", false)).strip_edges()
	return normalized if limit == 0 else normalized.substr(0, limit)

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
	var log_budget := OwnerResourcePolicy.value("research_log_bytes")
	if log_budget == 0: return
	if not FileAccess.file_exists(LOG_PATH):
		return
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		return
	var size := file.get_length()
	file.close()
	if size < log_budget:
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

func _response_byte_limit() -> int:
	var budget := OwnerResourcePolicy.value("research_response_bytes")
	return -1 if budget == 0 else budget

func _redact_credentials(value: String) -> String:
	var credential := RegEx.new()
	# Recognize assignment, JSON-like and whitespace-separated marked values.
	# Redact before any output clipping; a low owner cap never bypasses privacy.
	var pattern := "(?i)\\b(password|passwd|secret|token|api[_ -]?key|authorization|cookie|private[_ -]?key)[\"']?\\s*(?:[:=]\\s*|\\s+)(?:Bearer\\s+)?[\"']?[^\\s,;\"']+"
	if credential.compile(pattern) != OK:
		return "Sensitive research details omitted"
	var clean := credential.sub(value, "$1=[REDACTED]", true)
	var bearer := RegEx.new()
	if bearer.compile("(?i)\\bbearer\\s+[^\\s,;]+") != OK:
		return "Sensitive research details omitted"
	return bearer.sub(clean, "Bearer=[REDACTED]", true)
