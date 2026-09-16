class_name AuroraResearchCollector
extends Node

signal research_completed(report: Dictionary)

const LOG_PATH := "user://agent/research.jsonl"
const LOG_BACKUP_PATH := "user://agent/research.jsonl.1"
const MAX_ITEMS_PER_SOURCE := 5
const MAX_SUMMARY_CHARS := 1800
const MAX_RESPONSE_BYTES := 2 * 1024 * 1024
const MAX_LOG_BYTES := 8 * 1024 * 1024
const MAX_SOURCE_ERRORS := 16
const REQUEST_TIMEOUT_SECONDS := 20.0

# Kept for setup/API compatibility with AutonomousCoordinator. The collector
# deliberately never writes to MemoryStore: durable automatic learning is owned
# by AuroraLearningCurator after quality/provenance/deduplication checks.
var memory: MemoryStore
var tools: ToolRegistry
var _busy := false
var _request_errors: Array = []

func setup(memory_store: MemoryStore, tool_registry: ToolRegistry) -> void:
	memory = memory_store
	tools = tool_registry
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_PATH.get_base_dir()))

func collect(query: String) -> Dictionary:
	if _busy:
		return {"ok": false, "error": "Research collector is already running"}
	_busy = true
	_request_errors.clear()
	var clean_query := query.strip_edges()
	if clean_query.is_empty():
		clean_query = "local AI Godot LLM context optimization"
	var items: Array = []

	# Autonomous research is external-observation only. Personal/local documents
	# are never scanned implicitly here; they enter AuroraFox only through the
	# explicit user-controlled Knowledge/import flow.
	items.append_array(await _collect_github(clean_query))
	items.append_array(await _collect_stackoverflow(clean_query))
	items.append_array(await _collect_reddit("LocalLLaMA"))
	items.append_array(await _collect_reddit("MachineLearning"))
	items.append_array(await _collect_arxiv(clean_query))

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
		"network_response_limit_bytes": MAX_RESPONSE_BYTES,
		"audit_log_limit_bytes": MAX_LOG_BYTES,
		"source_error_count": source_errors.size(),
		"source_errors": source_errors,
		# Backward-compatible field. Automatic promotion happens asynchronously in
		# LearningCurator after research_completed, so nothing is learned here.
		"learned": 0,
		"sources": _source_counts(items),
		"timestamp_unix": int(Time.get_unix_time_from_system())
	}
	if complete_failure:
		report["error"] = "All autonomous research sources failed"
	_busy = false
	research_completed.emit(report)
	return report

func _collect_github(query: String) -> Array:
	var encoded := query.uri_encode()
	var result := await _request_json("https://api.github.com/search/repositories?q=%s&sort=updated&order=desc&per_page=%d" % [encoded, MAX_ITEMS_PER_SOURCE])
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
	var result := await _request_json("https://api.stackexchange.com/2.3/search/advanced?site=stackoverflow&order=desc&sort=activity&q=%s&pagesize=%d" % [encoded, MAX_ITEMS_PER_SOURCE])
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
	var result := await _request_json("https://www.reddit.com/r/%s/hot.json?limit=%d&raw_json=1" % [subreddit.uri_encode(), MAX_ITEMS_PER_SOURCE])
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
	var result := await _request_text("https://export.arxiv.org/api/query?search_query=all:%s&start=0&max_results=%d&sortBy=submittedDate&sortOrder=descending" % [encoded, MAX_ITEMS_PER_SOURCE])
	var out: Array = []
	if not result.get("ok", false):
		return out
	var xml := str(result.get("text", ""))
	var parser := XMLParser.new()
	var parse_error := parser.open_buffer(xml.to_utf8_buffer())
	if parse_error != OK:
		_record_request_error("arxiv_xml", "", 0, parse_error, "Invalid arXiv XML")
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
	return out

func _request_json(url: String) -> Dictionary:
	var result := await _request_text(url)
	if not result.get("ok", false):
		return result
	var parsed = JSON.parse_string(str(result.get("text", "")))
	if not parsed is Dictionary:
		_record_request_error("json_parse", url, 0, 0, "Invalid JSON")
		return {"ok": false, "error": "Invalid JSON", "url": url}
	return {"ok": true, "data": parsed}

func _request_text(url: String) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = REQUEST_TIMEOUT_SECONDS
	req.body_size_limit = MAX_RESPONSE_BYTES
	add_child(req)
	var headers := PackedStringArray(["User-Agent: AuroraFox-Learning/1.3", "Accept: application/json, application/atom+xml, text/xml, text/plain;q=0.9"])
	var err := req.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		req.queue_free()
		_record_request_error("request_start", url, 0, err, error_string(err))
		return {"ok": false, "error": error_string(err), "url": url}
	var response: Array = await req.request_completed
	req.queue_free()
	var request_result := int(response[0])
	var code := int(response[1])
	var body := (response[3] as PackedByteArray).get_string_from_utf8()
	if request_result != HTTPRequest.RESULT_SUCCESS:
		_record_request_error("request_result", url, code, request_result, "Research request did not complete successfully")
		return {"ok": false, "result": request_result, "http": code, "error": "Research request did not complete successfully", "url": url}
	if code < 200 or code >= 300:
		_record_request_error("http", url, code, request_result, body.substr(0, 240))
		return {"ok": false, "http": code, "error": body.substr(0, 500), "url": url}
	return {"ok": true, "text": body.substr(0, MAX_RESPONSE_BYTES), "url": url}

func _record_request_error(stage: String, url: String, http_code: int, result_code: int, message: String) -> void:
	if _request_errors.size() >= MAX_SOURCE_ERRORS:
		return
	_request_errors.append({
		"stage": stage.substr(0, 64),
		"url": url.substr(0, 500),
		"http": http_code,
		"result": result_code,
		"error": _clean(message, 240)
	})

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
