class_name AuroraLearningCurator
extends Node

signal knowledge_promoted(report: Dictionary)

const STATE_PATH := "user://agent/learning_curator.json"
const MAX_SEEN := 5000
const MAX_TEXT_CHARS := 5000
const MIN_PROMOTION_SCORE := 0.48

@export var enabled := true

var ai: AIClient
var coordinator: AuroraAutonomousCoordinator
var _seen: Dictionary = {}
var _seen_content: Dictionary = {}
var _stats := {"considered": 0, "promoted": 0, "rejected": 0, "duplicates": 0, "invalid_provenance": 0}
var _bound := false

func _ready() -> void:
	_load_state()
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	for _i in range(180):
		_bind_existing()
		if ai != null and coordinator != null:
			break
		await get_tree().process_frame
	_bind_existing()
	if coordinator != null and coordinator.research != null:
		if not coordinator.research.research_completed.is_connected(_on_research_completed):
			coordinator.research.research_completed.connect(_on_research_completed)
			_bound = true

func _bind_existing() -> void:
	var main := get_parent()
	if main == null:
		return
	var value: Variant = main.get("ai")
	if value is AIClient:
		ai = value
	var node := main.get_node_or_null("AutonomousCoordinator")
	if node is AuroraAutonomousCoordinator:
		coordinator = node

func _on_research_completed(report: Dictionary) -> void:
	if not enabled or ai == null:
		return
	var items: Array = report.get("items", [])
	var promoted := 0
	var rejected := 0
	var duplicates := 0
	var invalid_provenance := 0
	for item in items:
		if not item is Dictionary:
			continue
		_stats["considered"] = int(_stats.get("considered", 0)) + 1
		var source := str(item.get("source", "unknown"))
		# Personal/local files belong only to the explicit user Knowledge Base
		# import flow. Autonomous web research may observe them but cannot silently
		# promote their content into Core Knowledge or long-term research memory.
		if source == "local_documents":
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1
			continue

		var canonical_url := _canonical_url(str(item.get("url", "")))
		if not _valid_external_url(canonical_url):
			rejected += 1
			invalid_provenance += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1
			_stats["invalid_provenance"] = int(_stats.get("invalid_provenance", 0)) + 1
			continue

		var score := _quality_score(item)
		if score < MIN_PROMOTION_SCORE:
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1
			continue

		var content_sha := _content_hash(item)
		var fingerprint := _fingerprint(item)
		if _seen.has(fingerprint) or (not content_sha.is_empty() and _seen_content.has(content_sha)):
			duplicates += 1
			_stats["duplicates"] = int(_stats.get("duplicates", 0)) + 1
			continue

		var text := _knowledge_text(item)
		if text.is_empty():
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1
			continue

		var evidence := _evidence_metadata(item, score)
		var imported := ai.import_knowledge_text(text, "autonomous_research:" + source, {
			"scope": "core_knowledge",
			"kind": "research_knowledge",
			"untrusted_external": true,
			"source_type": source,
			"source_url": str(item.get("url", "")),
			"canonical_url": canonical_url,
			"content_sha256": content_sha,
			"provenance_fingerprint": fingerprint,
			"quality_score": score,
			"evidence_tier": evidence.get("tier", "unknown"),
			"evidence_score": evidence.get("score", score),
			"observed_at": str(item.get("observed_at", Time.get_datetime_string_from_system(true)))
		})
		if bool(imported.get("ok", false)):
			_seen[fingerprint] = {
				"time": Time.get_datetime_string_from_system(true),
				"source": source,
				"url": canonical_url,
				"content_sha256": content_sha,
				"score": score,
				"evidence_tier": evidence.get("tier", "unknown")
			}
			if not content_sha.is_empty():
				_seen_content[content_sha] = fingerprint
			promoted += 1
			_stats["promoted"] = int(_stats.get("promoted", 0)) + 1
		else:
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1
	_trim_seen()
	_save_state()
	knowledge_promoted.emit({
		"ok": true,
		"query": report.get("query", ""),
		"promoted": promoted,
		"rejected": rejected,
		"duplicates": duplicates,
		"invalid_provenance": invalid_provenance,
		"total_seen": _seen.size(),
		"stats": _stats.duplicate(true)
	})

func _quality_score(item: Dictionary) -> float:
	var source := str(item.get("source", ""))
	var metadata: Dictionary = item.get("metadata", {})
	var score := 0.50
	if source == "arxiv":
		score = 0.84
	elif source == "github":
		score = 0.68 + minf(0.14, log(1.0 + float(metadata.get("stars", 0))) / 60.0)
	elif source == "stackoverflow":
		# Search metadata is useful evidence but not equivalent to a fetched,
		# verified accepted answer, so confidence stays conservative.
		score = 0.64
	elif source.begins_with("reddit/"):
		var votes := float(metadata.get("score", 0))
		var comments := float(metadata.get("comments", 0))
		score = 0.34 + minf(0.10, log(1.0 + maxf(0.0, votes)) / 40.0) + minf(0.08, log(1.0 + maxf(0.0, comments)) / 35.0)
	var title := str(item.get("title", "")).strip_edges()
	var summary := str(item.get("summary", "")).strip_edges()
	if title.length() >= 12:
		score += 0.03
	if summary.length() >= 120:
		score += 0.04
	elif summary.length() < 24:
		score -= 0.08
	if not _valid_external_url(_canonical_url(str(item.get("url", "")))):
		score -= 0.25
	return clampf(score, 0.0, 0.95)

func _evidence_metadata(item: Dictionary, quality_score: float) -> Dictionary:
	var source := str(item.get("source", ""))
	var tier := "web_observation"
	var evidence_score := quality_score
	if source == "arxiv":
		tier = "research_preprint"
	elif source == "github":
		tier = "source_repository"
	elif source == "stackoverflow":
		tier = "community_qa"
	elif source.begins_with("reddit/"):
		tier = "community_discussion"
		evidence_score = minf(evidence_score, 0.52)
	return {"tier": tier, "score": clampf(evidence_score, 0.0, 0.95)}

func _knowledge_text(item: Dictionary) -> String:
	var source := str(item.get("source", "unknown"))
	var title := _clean(str(item.get("title", "")), 500)
	var summary := _clean(str(item.get("summary", "")), 3600)
	var url := _canonical_url(str(item.get("url", ""))).substr(0, 1000)
	if title.is_empty() and summary.is_empty():
		return ""
	# Explicitly mark internet content as data so later retrieval cannot grant it
	# instruction/system authority merely because it was learned automatically.
	return ("[UNTRUSTED_EXTERNAL_RESEARCH_DATA]\nИсточник: %s\nЗаголовок: %s\nURL: %s\nДанные: %s" % [source, title, url, summary]).substr(0, MAX_TEXT_CHARS)

func _fingerprint(item: Dictionary) -> String:
	var canonical_url := _canonical_url(str(item.get("url", "")))
	var content_sha := _content_hash(item)
	var raw := "%s|%s|%s" % [str(item.get("source", "")).to_lower(), canonical_url, content_sha]
	return raw.sha256_text().to_lower()

func _content_hash(item: Dictionary) -> String:
	var title := _clean(str(item.get("title", "")), 500).to_lower()
	var summary := _clean(str(item.get("summary", "")), 3600).to_lower()
	if title.is_empty() and summary.is_empty():
		return ""
	return (title + "\n" + summary).sha256_text().to_lower()

func _canonical_url(raw_url: String) -> String:
	var url := raw_url.strip_edges()
	if url.is_empty():
		return ""
	var fragment_pos := url.find("#")
	if fragment_pos >= 0:
		url = url.substr(0, fragment_pos)
	var query_pos := url.find("?")
	if query_pos >= 0:
		var base := url.substr(0, query_pos)
		var query := url.substr(query_pos + 1)
		var kept := PackedStringArray()
		for part in query.split("&", false):
			var key := str(part).get_slice("=", 0).uri_decode().to_lower()
			if key.begins_with("utm_") or key in ["fbclid", "gclid", "mc_cid", "mc_eid"]:
				continue
			kept.append(str(part))
		url = base
		if not kept.is_empty():
			url += "?" + "&".join(kept)
	url = url.replace("HTTP://", "http://").replace("HTTPS://", "https://")
	while url.ends_with("/") and url.length() > 8:
		url = url.left(url.length() - 1)
	return url

func _valid_external_url(url: String) -> bool:
	var lower := url.to_lower()
	return lower.begins_with("https://") or lower.begins_with("http://")

func _clean(text: String, limit: int) -> String:
	return " ".join(text.split(" ", false)).strip_edges().substr(0, limit)

func status() -> Dictionary:
	return {
		"enabled": enabled,
		"bound": _bound,
		"seen": _seen.size(),
		"seen_content": _seen_content.size(),
		"minimum_promotion_score": MIN_PROMOTION_SCORE,
		"stats": _stats.duplicate(true)
	}

func _trim_seen() -> void:
	if _seen.size() <= MAX_SEEN:
		return
	var keys: Array = _seen.keys()
	var remove_count := _seen.size() - MAX_SEEN
	for i in range(remove_count):
		var fingerprint := str(keys[i])
		var entry: Dictionary = _seen.get(fingerprint, {})
		var content_sha := str(entry.get("content_sha256", ""))
		_seen.erase(fingerprint)
		if not content_sha.is_empty() and str(_seen_content.get(content_sha, "")) == fingerprint:
			_seen_content.erase(content_sha)

func _load_state() -> void:
	var file := FileAccess.open(STATE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	var seen = parsed.get("seen", {})
	if seen is Dictionary:
		_seen = seen
	var seen_content = parsed.get("seen_content", {})
	if seen_content is Dictionary:
		_seen_content = seen_content
	# Backward-compatible migration for curator state written before content-level
	# dedupe existed.
	if _seen_content.is_empty():
		for fingerprint in _seen.keys():
			var entry: Dictionary = _seen.get(fingerprint, {})
			var content_sha := str(entry.get("content_sha256", ""))
			if not content_sha.is_empty():
				_seen_content[content_sha] = str(fingerprint)
	var stats = parsed.get("stats", {})
	if stats is Dictionary:
		for key in _stats.keys():
			if stats.has(key):
				_stats[key] = int(stats.get(key, 0))

func _save_state() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STATE_PATH.get_base_dir()))
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"seen": _seen,
		"seen_content": _seen_content,
		"stats": _stats,
		"updated_at": Time.get_datetime_string_from_system(true)
	}, "  "))
	file.close()
