class_name AuroraResearchCollector
extends Node

signal research_completed(report: Dictionary)

const LOG_PATH := "user://agent/research.jsonl"
const MAX_ITEMS_PER_SOURCE := 5
const MAX_SUMMARY_CHARS := 1800
const MAX_RESPONSE_BYTES := 2 * 1024 * 1024
const REQUEST_TIMEOUT_SECONDS := 20.0

# Kept for setup/API compatibility with AutonomousCoordinator. The collector
# deliberately never writes to MemoryStore: durable automatic learning is owned
# by AuroraLearningCurator after quality/provenance/deduplication checks.
var memory: MemoryStore
var tools: ToolRegistry
var _busy := false

func setup(memory_store: MemoryStore, tool_registry: ToolRegistry) -> void:
	memory = memory_store
	tools = tool_registry
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_PATH.get_base_dir()))

func collect(query: String) -> Dictionary:
	if _busy:
		return {"ok": false, "error": "Research collector is already running"}
	_busy = true
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
	var report := {
		"ok": true,
		"query": clean_query,
		"items": items,
		"count": items.size(),
		"queued_for_curation": items.size(),
		"curation_required": true,
		"research_scope": "external_observations_only",
		"personal_files_scanned": false,
		# Backward-compatible field. Automatic promotion happens asynchronously in
		# LearningCurator after research_completed, so nothing is learned here.
		"learned": 0,
		"sources": _source_counts(items),
		"timestamp_unix": int(Time.get_unix_time_from_system())
	}
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
	if parser.open_buffer(xml.to_utf8_buffer()) != OK:
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
		return {"ok": false, "error": error_string(err), "url": url}
	var response: Array = await req.request_completed
	req.queue_free()
	var code := int(response[1])
	var body := (response[3] as PackedByteArray).get_string_from_utf8()
	if code < 200 or code >= 300:
		return {"ok": false, "http": code, "error": body.substr(0, 500), "url": url}
	return {"ok": true, "text": body.substr(0, MAX_RESPONSE_BYTES), "url": url}

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
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify(item))
	file.close()

func _source_counts(items: Array) -> Dictionary:
	var counts: Dictionary = {}
	for item in items:
		if item is Dictionary:
			var source := str(item.get("source", "unknown"))
			counts[source] = int(counts.get(source, 0)) + 1
	return counts
