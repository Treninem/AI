class_name AuroraLearningCurator
extends Node

signal knowledge_promoted(report: Dictionary)

const STATE_PATH := "user://agent/learning_curator.json"
const MAX_SEEN := 5000
const MAX_CLAIMS := 5000
const MAX_GAP_QUESTIONS := 500
const MAX_TEXT_CHARS := 5000
const MIN_PROMOTION_SCORE := 0.48
const SINGLE_SOURCE_PROMOTION_SCORE := 0.78
const MIN_CORROBORATING_FAMILIES := 2

@export var enabled := true

var ai: AIClient
var coordinator: AuroraAutonomousCoordinator
var _seen: Dictionary = {}
var _seen_content: Dictionary = {}
var _claim_evidence: Dictionary = {}
var _gap_questions: Array = []
var _stats := {
	"considered": 0,
	"promoted": 0,
	"rejected": 0,
	"duplicates": 0,
	"invalid_provenance": 0,
	"deferred": 0,
	"corroborated": 0,
	"contradictions": 0
}
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
	var deferred := 0
	var corroborated := 0
	var contradictions := 0
	var candidates: Array = []
	var batch_content_hashes: Dictionary = {}

	# First pass validates provenance/quality and records independent evidence before
	# any promotion decision. This allows contradictions in the same research batch
	# to stop promotion instead of racing whichever source happened to arrive first.
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
			var weak_claim := _claim_key(item)
			if not weak_claim.is_empty():
				_queue_gap(weak_claim, "weak_evidence", item, {})
			continue

		var content_sha := _content_hash(item)
		var fingerprint := _fingerprint(item)
		if _seen.has(fingerprint) or (not content_sha.is_empty() and _seen_content.has(content_sha)):
			duplicates += 1
			_stats["duplicates"] = int(_stats.get("duplicates", 0)) + 1
			continue
		if not content_sha.is_empty() and batch_content_hashes.has(content_sha):
			# Identical syndicated/mirrored text does not count as independent
			# corroboration merely because it appears at another URL.
			duplicates += 1
			_stats["duplicates"] = int(_stats.get("duplicates", 0)) + 1
			continue
		if not content_sha.is_empty():
			batch_content_hashes[content_sha] = true

		var evidence := _evidence_metadata(item, score)
		var candidate := {
			"item": item,
			"source": source,
			"canonical_url": canonical_url,
			"score": score,
			"content_sha256": content_sha,
			"fingerprint": fingerprint,
			"evidence": evidence,
			"claim_key": _claim_key(item),
			"stance": _claim_stance(item),
			"source_family": _source_family(item)
		}
		if str(candidate.get("claim_key", "")).is_empty():
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1
			continue
		candidates.append(candidate)
		_record_claim_evidence(candidate)

	# Second pass promotes at most one representative item per claim. Medium
	# confidence evidence needs at least two independent source families. A single
	# source may promote only when its evidence score is high enough. Any observed
	# support/oppose split becomes a durable knowledge-gap question instead.
	var processed_claims: Dictionary = {}
	for candidate in candidates:
		if not candidate is Dictionary:
			continue
		var claim_key := str(candidate.get("claim_key", ""))
		if processed_claims.has(claim_key):
			continue
		processed_claims[claim_key] = true
		var group := _candidates_for_claim(candidates, claim_key)
		var best := _best_candidate(group)
		if best.is_empty():
			continue
		var ledger: Dictionary = _claim_evidence.get(claim_key, {})
		var support_count := _family_count(ledger, "support_families")
		var oppose_count := _family_count(ledger, "oppose_families")
		if support_count > 0 and oppose_count > 0:
			contradictions += 1
			deferred += group.size()
			_stats["contradictions"] = int(_stats.get("contradictions", 0)) + 1
			_stats["deferred"] = int(_stats.get("deferred", 0)) + group.size()
			ledger["status"] = "contradicted"
			ledger["updated_at"] = Time.get_datetime_string_from_system(true)
			_claim_evidence[claim_key] = ledger
			_queue_gap(claim_key, "contradiction", best.get("item", {}), ledger)
			continue

		var stance := str(best.get("stance", "support"))
		var independent_count := support_count if stance == "support" else oppose_count
		if not str(ledger.get("promoted_fingerprint", "")).is_empty():
			# The claim is already represented in Core Knowledge. New independent
			# observations strengthen its evidence ledger without creating near-
			# duplicate durable knowledge entries.
			corroborated += group.size()
			_stats["corroborated"] = int(_stats.get("corroborated", 0)) + group.size()
			ledger["status"] = "corroborated" if independent_count >= MIN_CORROBORATING_FAMILIES else "promoted"
			ledger["updated_at"] = Time.get_datetime_string_from_system(true)
			_claim_evidence[claim_key] = ledger
			_resolve_gap(claim_key)
			continue

		var score := float(best.get("score", 0.0))
		var high_confidence_single := score >= SINGLE_SOURCE_PROMOTION_SCORE
		var enough_corroboration := independent_count >= MIN_CORROBORATING_FAMILIES
		if not high_confidence_single and not enough_corroboration:
			deferred += group.size()
			_stats["deferred"] = int(_stats.get("deferred", 0)) + group.size()
			ledger["status"] = "awaiting_corroboration"
			ledger["updated_at"] = Time.get_datetime_string_from_system(true)
			_claim_evidence[claim_key] = ledger
			_queue_gap(claim_key, "needs_corroboration", best.get("item", {}), ledger)
			continue

		var item: Dictionary = best.get("item", {})
		var source := str(best.get("source", "unknown"))
		var text := _knowledge_text(item)
		if text.is_empty():
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1
			continue
		var evidence: Dictionary = best.get("evidence", {})
		var evidence_status := "corroborated" if enough_corroboration else "single_high_confidence"
		var source_families := _families_for_stance(ledger, stance)
		var imported := ai.import_knowledge_text(text, "autonomous_research:" + source, {
			"scope": "core_knowledge",
			"kind": "research_knowledge",
			"untrusted_external": true,
			"source_type": source,
			"source_url": str(item.get("url", "")),
			"canonical_url": str(best.get("canonical_url", "")),
			"content_sha256": str(best.get("content_sha256", "")),
			"provenance_fingerprint": str(best.get("fingerprint", "")),
			"quality_score": score,
			"evidence_tier": evidence.get("tier", "unknown"),
			"evidence_score": evidence.get("score", score),
			"evidence_status": evidence_status,
			"claim_key": claim_key,
			"claim_stance": stance,
			"corroboration_count": independent_count,
			"contradiction_count": 0,
			"source_families": source_families,
			"observed_at": str(item.get("observed_at", Time.get_datetime_string_from_system(true)))
		})
		if bool(imported.get("ok", false)):
			var fingerprint := str(best.get("fingerprint", ""))
			var content_sha := str(best.get("content_sha256", ""))
			_seen[fingerprint] = {
				"time": Time.get_datetime_string_from_system(true),
				"source": source,
				"url": str(best.get("canonical_url", "")),
				"content_sha256": content_sha,
				"score": score,
				"evidence_tier": evidence.get("tier", "unknown"),
				"evidence_status": evidence_status,
				"claim_key": claim_key,
				"corroboration_count": independent_count
			}
			if not content_sha.is_empty():
				_seen_content[content_sha] = fingerprint
			ledger["promoted_fingerprint"] = fingerprint
			ledger["promoted_content_sha256"] = content_sha
			ledger["promoted_at"] = Time.get_datetime_string_from_system(true)
			ledger["status"] = evidence_status
			ledger["updated_at"] = Time.get_datetime_string_from_system(true)
			_claim_evidence[claim_key] = ledger
			promoted += 1
			_stats["promoted"] = int(_stats.get("promoted", 0)) + 1
			if enough_corroboration:
				corroborated += 1
				_stats["corroborated"] = int(_stats.get("corroborated", 0)) + 1
			_resolve_gap(claim_key)
		else:
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1

	_trim_seen()
	_trim_claim_evidence()
	_trim_gap_questions()
	_save_state()
	knowledge_promoted.emit({
		"ok": true,
		"query": report.get("query", ""),
		"promoted": promoted,
		"rejected": rejected,
		"duplicates": duplicates,
		"invalid_provenance": invalid_provenance,
		"deferred": deferred,
		"corroborated": corroborated,
		"contradictions": contradictions,
		"open_questions": open_questions().size(),
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

func _claim_key(item: Dictionary) -> String:
	var base := _clean(str(item.get("title", "")), 500).to_lower()
	if base.length() < 8:
		base = _clean(str(item.get("summary", "")), 500).to_lower()
	if base.is_empty():
		return ""
	for separator in [".", ",", ":", ";", "!", "?", "(", ")", "[", "]", "{", "}", "\"", "'", "`", "_", "-", "/", "\\", "|", "+", "="]:
		base = base.replace(separator, " ")
	var stop_words := [
		"the", "a", "an", "is", "are", "was", "were", "be", "to", "of", "for", "and", "or", "that", "this",
		"not", "no", "never", "without", "cannot", "cant", "doesnt", "don't", "doesn't",
		"и", "или", "это", "как", "для", "что", "не", "нет", "без", "нельзя", "никогда"
	]
	var tokens := PackedStringArray()
	for raw_token in base.split(" ", false):
		var token := str(raw_token).strip_edges()
		if token.length() < 2 or token in stop_words:
			continue
		tokens.append(token)
		if tokens.size() >= 16:
			break
	if tokens.is_empty():
		return base.substr(0, 200).sha256_text().to_lower()
	return " ".join(tokens).sha256_text().to_lower()

func _claim_stance(item: Dictionary) -> String:
	var metadata: Dictionary = item.get("metadata", {})
	var explicit := str(metadata.get("stance", "")).to_lower().strip_edges()
	if explicit in ["oppose", "opposed", "negative", "contradict", "contradiction", "refute"]:
		return "oppose"
	if explicit in ["support", "supported", "positive", "confirm", "confirmation"]:
		return "support"
	var text := " " + (str(item.get("title", "")) + " " + str(item.get("summary", ""))).to_lower() + " "
	for marker in [" not ", " no ", " never ", " without ", " cannot ", " can't ", " doesn't ", " не ", " нет ", " никогда ", " нельзя ", " без "]:
		if text.contains(marker):
			return "oppose"
	return "support"

func _source_family(item: Dictionary) -> String:
	var source := str(item.get("source", "unknown")).to_lower().strip_edges()
	if source.begins_with("reddit/"):
		return "reddit"
	if source in ["arxiv", "github", "stackoverflow"]:
		return source
	var url := _canonical_url(str(item.get("url", ""))).to_lower()
	var scheme_pos := url.find("://")
	if scheme_pos >= 0:
		var host_and_path := url.substr(scheme_pos + 3)
		var slash := host_and_path.find("/")
		var host := host_and_path if slash < 0 else host_and_path.substr(0, slash)
		if host.begins_with("www."):
			host = host.substr(4)
		if not host.is_empty():
			return host
	return source if not source.is_empty() else "unknown"

func _record_claim_evidence(candidate: Dictionary) -> void:
	var claim_key := str(candidate.get("claim_key", ""))
	if claim_key.is_empty():
		return
	var ledger: Dictionary = _claim_evidence.get(claim_key, {
		"support_families": {},
		"oppose_families": {},
		"content_hashes": {},
		"fingerprints": {},
		"status": "observed",
		"first_seen": Time.get_datetime_string_from_system(true)
	})
	var content_sha := str(candidate.get("content_sha256", ""))
	var fingerprint := str(candidate.get("fingerprint", ""))
	var content_hashes: Dictionary = ledger.get("content_hashes", {})
	var fingerprints: Dictionary = ledger.get("fingerprints", {})
	var new_content := content_sha.is_empty() or not content_hashes.has(content_sha)
	if not content_sha.is_empty():
		content_hashes[content_sha] = true
	if not fingerprint.is_empty():
		fingerprints[fingerprint] = true
	ledger["content_hashes"] = content_hashes
	ledger["fingerprints"] = fingerprints
	if new_content:
		var stance := str(candidate.get("stance", "support"))
		var key := "oppose_families" if stance == "oppose" else "support_families"
		var families: Dictionary = ledger.get(key, {})
		families[str(candidate.get("source_family", "unknown"))] = true
		ledger[key] = families
	ledger["updated_at"] = Time.get_datetime_string_from_system(true)
	_claim_evidence[claim_key] = ledger

func _family_count(ledger: Dictionary, key: String) -> int:
	var families = ledger.get(key, {})
	return families.size() if families is Dictionary else 0

func _families_for_stance(ledger: Dictionary, stance: String) -> Array:
	var key := "oppose_families" if stance == "oppose" else "support_families"
	var families = ledger.get(key, {})
	return families.keys() if families is Dictionary else []

func _candidates_for_claim(candidates: Array, claim_key: String) -> Array:
	var out: Array = []
	for candidate in candidates:
		if candidate is Dictionary and str(candidate.get("claim_key", "")) == claim_key:
			out.append(candidate)
	return out

func _best_candidate(candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	for candidate in candidates:
		if not candidate is Dictionary:
			continue
		var score := float(candidate.get("score", 0.0))
		if best.is_empty() or score > best_score:
			best = candidate
			best_score = score
	return best

func _queue_gap(claim_key: String, reason: String, item: Dictionary, ledger: Dictionary) -> void:
	if claim_key.is_empty():
		return
	var gap_id := (claim_key + "|" + reason).sha256_text().to_lower()
	var title := _clean(str(item.get("title", "")), 300)
	if title.is_empty():
		title = _clean(str(item.get("summary", "")), 300)
	var question := "Найти более надёжный источник: " + title
	if reason == "needs_corroboration":
		question = "Найти независимый источник для подтверждения: " + title
	elif reason == "contradiction":
		question = "Разрешить противоречие независимыми источниками: " + title
	var support_count := _family_count(ledger, "support_families")
	var oppose_count := _family_count(ledger, "oppose_families")
	for i in range(_gap_questions.size()):
		var existing = _gap_questions[i]
		if existing is Dictionary and str(existing.get("id", "")) == gap_id:
			var updated: Dictionary = existing
			updated["status"] = "open"
			updated["question"] = question
			updated["support_families"] = support_count
			updated["oppose_families"] = oppose_count
			updated["updated_at"] = Time.get_datetime_string_from_system(true)
			_gap_questions[i] = updated
			return
	_gap_questions.append({
		"id": gap_id,
		"claim_key": claim_key,
		"reason": reason,
		"question": question,
		"status": "open",
		"support_families": support_count,
		"oppose_families": oppose_count,
		"created_at": Time.get_datetime_string_from_system(true),
		"updated_at": Time.get_datetime_string_from_system(true)
	})

func _resolve_gap(claim_key: String) -> void:
	for i in range(_gap_questions.size()):
		var entry = _gap_questions[i]
		if not entry is Dictionary or str(entry.get("claim_key", "")) != claim_key:
			continue
		if str(entry.get("status", "open")) == "open":
			var updated: Dictionary = entry
			updated["status"] = "resolved"
			updated["resolved_at"] = Time.get_datetime_string_from_system(true)
			updated["updated_at"] = updated["resolved_at"]
			_gap_questions[i] = updated

func open_questions(limit := 20) -> Array:
	var out: Array = []
	var bounded := maxi(1, int(limit))
	for entry in _gap_questions:
		if entry is Dictionary and str(entry.get("status", "open")) == "open":
			out.append(entry.duplicate(true))
			if out.size() >= bounded:
				break
	return out

func next_question() -> Dictionary:
	var questions := open_questions(1)
	return questions[0] if not questions.is_empty() else {}

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
		"claim_evidence": _claim_evidence.size(),
		"open_gap_questions": open_questions(MAX_GAP_QUESTIONS).size(),
		"minimum_promotion_score": MIN_PROMOTION_SCORE,
		"single_source_promotion_score": SINGLE_SOURCE_PROMOTION_SCORE,
		"minimum_corroborating_families": MIN_CORROBORATING_FAMILIES,
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

func _trim_claim_evidence() -> void:
	if _claim_evidence.size() <= MAX_CLAIMS:
		return
	var keys: Array = _claim_evidence.keys()
	var remove_count := _claim_evidence.size() - MAX_CLAIMS
	for i in range(remove_count):
		_claim_evidence.erase(str(keys[i]))

func _trim_gap_questions() -> void:
	if _gap_questions.size() <= MAX_GAP_QUESTIONS:
		return
	var i := 0
	while _gap_questions.size() > MAX_GAP_QUESTIONS and i < _gap_questions.size():
		var entry = _gap_questions[i]
		if entry is Dictionary and str(entry.get("status", "open")) != "open":
			_gap_questions.remove_at(i)
			continue
		i += 1
	while _gap_questions.size() > MAX_GAP_QUESTIONS:
		_gap_questions.pop_front()

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
	var claim_evidence = parsed.get("claim_evidence", {})
	if claim_evidence is Dictionary:
		_claim_evidence = claim_evidence
	var gap_questions = parsed.get("gap_questions", [])
	if gap_questions is Array:
		_gap_questions = gap_questions
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
	_trim_claim_evidence()
	_trim_gap_questions()

func _save_state() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STATE_PATH.get_base_dir()))
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"seen": _seen,
		"seen_content": _seen_content,
		"claim_evidence": _claim_evidence,
		"gap_questions": _gap_questions,
		"stats": _stats,
		"updated_at": Time.get_datetime_string_from_system(true)
	}, "  "))
	file.close()
