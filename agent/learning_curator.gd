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
var _stats := {"considered": 0, "promoted": 0, "rejected": 0, "duplicates": 0}
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
	for item in items:
		if not item is Dictionary:
			continue
		_stats["considered"] = int(_stats.get("considered", 0)) + 1
		var source := str(item.get("source", "unknown"))
		# Local files belong in the explicit Knowledge Base import flow. Automatic
		# internet learning must never silently turn personal documents into shared
		# core knowledge.
		if source == "local_documents":
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1
			continue
		var score := _quality_score(item)
		if score < MIN_PROMOTION_SCORE:
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1
			continue
		var fingerprint := _fingerprint(item)
		if _seen.has(fingerprint):
			duplicates += 1
			_stats["duplicates"] = int(_stats.get("duplicates", 0)) + 1
			continue
		var text := _knowledge_text(item)
		if text.is_empty():
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1
			continue
		var imported := ai.import_knowledge_text(text, "autonomous_research:" + source, {
			"scope": "core_knowledge",
			"kind": "research_knowledge",
			"untrusted_external": true,
			"source_type": source,
			"source_url": str(item.get("url", "")),
			"quality_score": score,
			"observed_at": str(item.get("observed_at", Time.get_datetime_string_from_system(true)))
		})
		if bool(imported.get("ok", false)):
			_seen[fingerprint] = {
				"time": Time.get_datetime_string_from_system(true),
				"source": source,
				"url": str(item.get("url", "")),
				"score": score
			}
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
		# The collector stores score/answer information in the summary; keep a
		# conservative confidence because the full accepted answer is not fetched.
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
	return clampf(score, 0.0, 0.95)

func _knowledge_text(item: Dictionary) -> String:
	var source := str(item.get("source", "unknown"))
	var title := _clean(str(item.get("title", "")), 500)
	var summary := _clean(str(item.get("summary", "")), 3600)
	var url := str(item.get("url", "")).strip_edges().substr(0, 1000)
	if title.is_empty() and summary.is_empty():
		return ""
	# Explicitly mark internet content as data so later retrieval cannot grant it
	# instruction/system authority merely because it was learned automatically.
	return ("[UNTRUSTED_EXTERNAL_RESEARCH_DATA]\nИсточник: %s\nЗаголовок: %s\nURL: %s\nДанные: %s" % [source, title, url, summary]).substr(0, MAX_TEXT_CHARS)

func _fingerprint(item: Dictionary) -> String:
	var raw := "%s|%s|%s|%s" % [
		str(item.get("source", "")),
		str(item.get("url", "")),
		str(item.get("title", "")),
		str(item.get("summary", ""))
	]
	return raw.sha256_text().to_lower()

func _clean(text: String, limit: int) -> String:
	return " ".join(text.split(" ", false)).strip_edges().substr(0, limit)

func status() -> Dictionary:
	return {
		"enabled": enabled,
		"bound": _bound,
		"seen": _seen.size(),
		"minimum_promotion_score": MIN_PROMOTION_SCORE,
		"stats": _stats.duplicate(true)
	}

func _trim_seen() -> void:
	if _seen.size() <= MAX_SEEN:
		return
	var keys: Array = _seen.keys()
	var remove_count := _seen.size() - MAX_SEEN
	for i in range(remove_count):
		_seen.erase(keys[i])

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
		"stats": _stats,
		"updated_at": Time.get_datetime_string_from_system(true)
	}, "  "))
	file.close()
