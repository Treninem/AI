class_name AuroraLearningCurator
extends Node

signal knowledge_promoted(report: Dictionary)

const STATE_PATH := "user://agent/learning_curator.json"
const STATE_BACKUP_PATH := "user://agent/learning_curator.json.bak"
const STATE_TEMP_PATH := "user://agent/learning_curator.json.tmp"
const MAX_SEEN := 5000
const MAX_CLAIMS := 5000
const MAX_GAP_QUESTIONS := 500
const MAX_AUDIT_EVENTS := 2000
const MAX_TEXT_CHARS := 5000
const MIN_PROMOTION_SCORE := 0.48
const SINGLE_SOURCE_PROMOTION_SCORE := 0.78
const MIN_CORROBORATING_FAMILIES := 2
const DEFAULT_EVIDENCE_MAX_AGE_SECONDS := 180 * 24 * 60 * 60
const RESEARCH_EVIDENCE_MAX_AGE_SECONDS := 365 * 24 * 60 * 60
const COMMUNITY_EVIDENCE_MAX_AGE_SECONDS := 60 * 24 * 60 * 60
const GAP_BASE_RETRY_SECONDS := 5 * 60
const GAP_MAX_RETRY_SECONDS := 24 * 60 * 60

@export var enabled := true

var ai: AIClient
var coordinator: AuroraAutonomousCoordinator
var _seen: Dictionary = {}
var _seen_content: Dictionary = {}
var _claim_evidence: Dictionary = {}
var _gap_questions: Array = []
var _audit_events: Array = []
var _stats := {
	"considered": 0,
	"promoted": 0,
	"rejected": 0,
	"duplicates": 0,
	"invalid_provenance": 0,
	"deferred": 0,
	"corroborated": 0,
	"contradictions": 0,
	"invalidated": 0,
	"stale_evidence": 0,
	"superseded_evidence": 0,
	"retracted_evidence": 0,
	"gap_attempts": 0
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
	var lifecycle := _sweep_evidence_lifecycle()
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
	var now := int(Time.get_unix_time_from_system())

	# First pass validates provenance/quality and records independent evidence before
	# any promotion decision. The collector remains observation-only; this curator is
	# the single durable promotion/invalidation authority.
	for value in items:
		if not value is Dictionary:
			continue
		var item: Dictionary = value
		_stats["considered"] = int(_stats.get("considered", 0)) + 1
		var source := str(item.get("source", "unknown"))
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

		var claim_key := _claim_key(item)
		if claim_key.is_empty():
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1
			continue
		var score := _quality_score(item)
		if score < MIN_PROMOTION_SCORE:
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1
			_queue_gap(claim_key, "weak_evidence", item, _claim_evidence.get(claim_key, {}))
			continue

		var content_sha := _content_hash(item)
		var fingerprint := _fingerprint(item)
		if _seen.has(fingerprint):
			_touch_observation(claim_key, fingerprint, now)
			duplicates += 1
			_stats["duplicates"] = int(_stats.get("duplicates", 0)) + 1
			continue
		if not content_sha.is_empty() and _seen_content.has(content_sha):
			duplicates += 1
			_stats["duplicates"] = int(_stats.get("duplicates", 0)) + 1
			continue
		if not content_sha.is_empty() and batch_content_hashes.has(content_sha):
			# Identical syndicated/mirrored text does not become independent evidence.
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
			"claim_key": claim_key,
			"stance": _claim_stance(item),
			"source_family": _source_family(item),
			"observed_unix": now
		}
		candidates.append(candidate)
		_record_claim_evidence(candidate)

	# Second pass promotes at most one representative item per claim. A previously
	# promoted claim is invalidated before it can remain authoritative when later
	# evidence contradicts, supersedes or reverses its active stance.
	var processed_claims: Dictionary = {}
	for value in candidates:
		if not value is Dictionary:
			continue
		var candidate: Dictionary = value
		var claim_key := str(candidate.get("claim_key", ""))
		if processed_claims.has(claim_key):
			continue
		processed_claims[claim_key] = true
		var group := _candidates_for_claim(candidates, claim_key)
		var best := _best_candidate(group)
		if best.is_empty():
			continue
		var ledger: Dictionary = _refresh_ledger(_claim_evidence.get(claim_key, {}), now)
		_claim_evidence[claim_key] = ledger
		var support_count := _family_count(ledger, "support_families")
		var oppose_count := _family_count(ledger, "oppose_families")
		if support_count > 0 and oppose_count > 0:
			contradictions += 1
			deferred += group.size()
			_stats["contradictions"] = int(_stats.get("contradictions", 0)) + 1
			_stats["deferred"] = int(_stats.get("deferred", 0)) + group.size()
			ledger["status"] = "contradicted"
			ledger["updated_at"] = Time.get_datetime_string_from_system(true)
			ledger["updated_unix"] = now
			_claim_evidence[claim_key] = ledger
			if not str(ledger.get("promoted_source", "")).is_empty():
				_invalidate_promoted_claim(claim_key, "contradiction")
			ledger = _claim_evidence.get(claim_key, ledger)
			_queue_gap(claim_key, "contradiction", best.get("item", {}), ledger)
			_record_audit("contradiction", claim_key, {"support_families": support_count, "oppose_families": oppose_count})
			continue

		var stance := str(best.get("stance", "support"))
		var independent_count := support_count if stance == "support" else oppose_count
		var promoted_source := str(ledger.get("promoted_source", ""))
		var promoted_stance := str(ledger.get("promoted_stance", ""))
		if not promoted_source.is_empty() and not promoted_stance.is_empty() and promoted_stance != stance:
			if not _invalidate_promoted_claim(claim_key, "stance_reversed"):
				_queue_gap(claim_key, "invalidation_failed", best.get("item", {}), _claim_evidence.get(claim_key, ledger))
				continue
			ledger = _claim_evidence.get(claim_key, ledger)
			promoted_source = ""

		if not promoted_source.is_empty():
			corroborated += group.size()
			_stats["corroborated"] = int(_stats.get("corroborated", 0)) + group.size()
			ledger["status"] = "corroborated" if independent_count >= MIN_CORROBORATING_FAMILIES else "promoted"
			ledger["updated_at"] = Time.get_datetime_string_from_system(true)
			ledger["updated_unix"] = now
			_claim_evidence[claim_key] = ledger
			_resolve_gap(claim_key)
			_record_audit("corroborated", claim_key, {"families": independent_count, "stance": stance})
			continue

		var score := float(best.get("score", 0.0))
		var high_confidence_single := score >= SINGLE_SOURCE_PROMOTION_SCORE
		var enough_corroboration := independent_count >= MIN_CORROBORATING_FAMILIES
		if not high_confidence_single and not enough_corroboration:
			deferred += group.size()
			_stats["deferred"] = int(_stats.get("deferred", 0)) + group.size()
			ledger["status"] = "awaiting_corroboration"
			ledger["updated_at"] = Time.get_datetime_string_from_system(true)
			ledger["updated_unix"] = now
			_claim_evidence[claim_key] = ledger
			_queue_gap(claim_key, "needs_corroboration", best.get("item", {}), ledger)
			_record_audit("deferred", claim_key, {"reason": "needs_corroboration", "families": independent_count})
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
		var scoped_source := _promotion_source(source, claim_key)
		var imported := ai.import_knowledge_text(text, scoped_source, {
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
			"observed_at": str(item.get("observed_at", Time.get_datetime_string_from_system(true))),
			"observed_unix": int(best.get("observed_unix", now)),
			"evidence_max_age_seconds": _max_age_for_evidence(evidence, item.get("metadata", {}))
		})
		if bool(imported.get("ok", false)):
			var fingerprint := str(best.get("fingerprint", ""))
			var content_sha := str(best.get("content_sha256", ""))
			_seen[fingerprint] = {
				"time": Time.get_datetime_string_from_system(true),
				"time_unix": now,
				"source": source,
				"knowledge_source": scoped_source,
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
			ledger["promoted_source"] = scoped_source
			ledger["promoted_stance"] = stance
			ledger["promoted_at"] = Time.get_datetime_string_from_system(true)
			ledger["promoted_unix"] = now
			ledger["status"] = evidence_status
			ledger["updated_at"] = Time.get_datetime_string_from_system(true)
			ledger["updated_unix"] = now
			_claim_evidence[claim_key] = ledger
			promoted += 1
			_stats["promoted"] = int(_stats.get("promoted", 0)) + 1
			if enough_corroboration:
				corroborated += 1
				_stats["corroborated"] = int(_stats.get("corroborated", 0)) + 1
			_resolve_gap(claim_key)
			_record_audit("promoted", claim_key, {"source": scoped_source, "stance": stance, "families": independent_count, "fingerprint": fingerprint})
		else:
			rejected += 1
			_stats["rejected"] = int(_stats.get("rejected", 0)) + 1

	_trim_seen()
	_trim_claim_evidence()
	_trim_gap_questions()
	_trim_audit_events()
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
		"lifecycle": lifecycle,
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

func _max_age_for_evidence(evidence: Dictionary, metadata: Variant) -> int:
	var tier := str(evidence.get("tier", "web_observation"))
	var result := DEFAULT_EVIDENCE_MAX_AGE_SECONDS
	if tier in ["research_preprint", "source_repository"]:
		result = RESEARCH_EVIDENCE_MAX_AGE_SECONDS
	elif tier in ["community_qa", "community_discussion"]:
		result = COMMUNITY_EVIDENCE_MAX_AGE_SECONDS
	if metadata is Dictionary and metadata.has("evidence_max_age_seconds"):
		result = clampi(int(metadata.get("evidence_max_age_seconds", result)), 60 * 60, 2 * 365 * 24 * 60 * 60)
	return result

func _knowledge_text(item: Dictionary) -> String:
	var source := str(item.get("source", "unknown"))
	var title := _clean(str(item.get("title", "")), 500)
	var summary := _clean(str(item.get("summary", "")), 3600)
	var url := _canonical_url(str(item.get("url", ""))).substr(0, 1000)
	if title.is_empty() and summary.is_empty():
		return ""
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

func _promotion_source(source: String, claim_key: String) -> String:
	var safe_source := source.to_lower().replace("/", "_").replace(":", "_").replace(" ", "_")
	return "autonomous_research:%s:%s" % [safe_source, claim_key.substr(0, mini(24, claim_key.length()))]

func _record_claim_evidence(candidate: Dictionary) -> void:
	var claim_key := str(candidate.get("claim_key", ""))
	if claim_key.is_empty():
		return
	var now := int(Time.get_unix_time_from_system())
	var ledger: Dictionary = _claim_evidence.get(claim_key, {
		"support_families": {},
		"oppose_families": {},
		"content_hashes": {},
		"fingerprints": {},
		"observations": {},
		"promotion_history": [],
		"status": "observed",
		"first_seen": Time.get_datetime_string_from_system(true),
		"first_seen_unix": now
	})
	var item: Dictionary = candidate.get("item", {})
	var metadata: Dictionary = item.get("metadata", {})
	var observations: Dictionary = ledger.get("observations", {})
	var content_sha := str(candidate.get("content_sha256", ""))
	var fingerprint := str(candidate.get("fingerprint", ""))
	var canonical_url := str(candidate.get("canonical_url", ""))

	# A changed document at the same canonical URL supersedes the previous version.
	# Explicit retract/supersede metadata can target a prior fingerprint as well.
	var supersedes_fingerprint := str(metadata.get("supersedes_fingerprint", ""))
	var retracts_fingerprint := str(metadata.get("retracts_fingerprint", ""))
	var action := str(metadata.get("evidence_action", "")).to_lower().strip_edges()
	var retracting := bool(metadata.get("retracted", false)) or action in ["retract", "retracted", "withdraw", "withdrawn"]
	for old_key in observations.keys():
		var old: Dictionary = observations.get(old_key, {})
		if str(old.get("status", "active")) != "active":
			continue
		var same_url_changed := not canonical_url.is_empty() and str(old.get("canonical_url", "")) == canonical_url and str(old.get("content_sha256", "")) != content_sha
		var explicit_supersede := not supersedes_fingerprint.is_empty() and str(old_key) == supersedes_fingerprint
		var explicit_retract := not retracts_fingerprint.is_empty() and str(old_key) == retracts_fingerprint
		if explicit_retract or (retracting and same_url_changed):
			old["status"] = "retracted"
			old["ended_unix"] = now
			old["ended_by"] = fingerprint
			observations[old_key] = old
			_stats["retracted_evidence"] = int(_stats.get("retracted_evidence", 0)) + 1
			_record_audit("evidence_retracted", claim_key, {"fingerprint": str(old_key), "by": fingerprint})
		elif same_url_changed or explicit_supersede:
			old["status"] = "superseded"
			old["ended_unix"] = now
			old["ended_by"] = fingerprint
			observations[old_key] = old
			_stats["superseded_evidence"] = int(_stats.get("superseded_evidence", 0)) + 1
			_record_audit("evidence_superseded", claim_key, {"fingerprint": str(old_key), "by": fingerprint})

	var evidence: Dictionary = candidate.get("evidence", {})
	observations[fingerprint] = {
		"fingerprint": fingerprint,
		"content_sha256": content_sha,
		"canonical_url": canonical_url,
		"source": str(candidate.get("source", "unknown")),
		"source_family": str(candidate.get("source_family", "unknown")),
		"stance": str(candidate.get("stance", "support")),
		"score": float(candidate.get("score", 0.0)),
		"evidence_tier": str(evidence.get("tier", "unknown")),
		"status": "active",
		"observed_unix": int(candidate.get("observed_unix", now)),
		"last_seen_unix": now,
		"max_age_seconds": _max_age_for_evidence(evidence, metadata)
	}
	ledger["observations"] = observations
	ledger["claim_label"] = _clean(str(item.get("title", item.get("summary", ""))), 300)
	ledger["updated_at"] = Time.get_datetime_string_from_system(true)
	ledger["updated_unix"] = now
	_claim_evidence[claim_key] = _refresh_ledger(ledger, now)
	_record_audit("evidence_observed", claim_key, {"fingerprint": fingerprint, "family": str(candidate.get("source_family", "unknown")), "stance": str(candidate.get("stance", "support"))})

func _touch_observation(claim_key: String, fingerprint: String, now: int) -> void:
	if claim_key.is_empty() or fingerprint.is_empty() or not _claim_evidence.has(claim_key):
		return
	var ledger: Dictionary = _claim_evidence.get(claim_key, {})
	var observations: Dictionary = ledger.get("observations", {})
	if not observations.has(fingerprint):
		return
	var observation: Dictionary = observations.get(fingerprint, {})
	if str(observation.get("status", "active")) == "stale":
		observation["status"] = "active"
	observation["last_seen_unix"] = now
	observations[fingerprint] = observation
	ledger["observations"] = observations
	ledger["updated_unix"] = now
	ledger["updated_at"] = Time.get_datetime_string_from_system(true)
	_claim_evidence[claim_key] = _refresh_ledger(ledger, now)

func _refresh_ledger(ledger: Dictionary, now: int) -> Dictionary:
	var observations = ledger.get("observations", {})
	if not observations is Dictionary or observations.is_empty():
		# Backward-compatible state created before per-observation lifecycle data.
		if not ledger.has("support_families"):
			ledger["support_families"] = {}
		if not ledger.has("oppose_families"):
			ledger["oppose_families"] = {}
		ledger["legacy_evidence"] = true
		return ledger
	var support: Dictionary = {}
	var oppose: Dictionary = {}
	var active_count := 0
	var stale_count := 0
	var superseded_count := 0
	var retracted_count := 0
	for key in observations.keys():
		var observation: Dictionary = observations.get(key, {})
		var status := str(observation.get("status", "active"))
		if status == "active":
			var last_seen := int(observation.get("last_seen_unix", observation.get("observed_unix", now)))
			var max_age := maxi(60 * 60, int(observation.get("max_age_seconds", DEFAULT_EVIDENCE_MAX_AGE_SECONDS)))
			if now - last_seen > max_age:
				observation["status"] = "stale"
				observation["ended_unix"] = now
				observations[key] = observation
				status = "stale"
				_stats["stale_evidence"] = int(_stats.get("stale_evidence", 0)) + 1
				_record_audit("evidence_stale", str(ledger.get("claim_key", "")), {"fingerprint": str(key)})
		if status == "active":
			active_count += 1
			var family := str(observation.get("source_family", "unknown"))
			if str(observation.get("stance", "support")) == "oppose":
				oppose[family] = true
			else:
				support[family] = true
		elif status == "stale":
			stale_count += 1
		elif status == "superseded":
			superseded_count += 1
		elif status == "retracted":
			retracted_count += 1
	ledger["observations"] = observations
	ledger["support_families"] = support
	ledger["oppose_families"] = oppose
	ledger["active_evidence_count"] = active_count
	ledger["stale_evidence_count"] = stale_count
	ledger["superseded_evidence_count"] = superseded_count
	ledger["retracted_evidence_count"] = retracted_count
	ledger["legacy_evidence"] = false
	return ledger

func _sweep_evidence_lifecycle() -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var stale_claims := 0
	var invalidated := 0
	for raw_key in _claim_evidence.keys():
		var claim_key := str(raw_key)
		var ledger: Dictionary = _claim_evidence.get(claim_key, {})
		ledger["claim_key"] = claim_key
		ledger = _refresh_ledger(ledger, now)
		_claim_evidence[claim_key] = ledger
		var promoted_source := str(ledger.get("promoted_source", ""))
		if promoted_source.is_empty():
			continue
		var promoted_stance := str(ledger.get("promoted_stance", "support"))
		var active_for_stance := _family_count(ledger, "oppose_families" if promoted_stance == "oppose" else "support_families")
		if active_for_stance > 0:
			continue
		stale_claims += 1
		if _invalidate_promoted_claim(claim_key, "evidence_expired_or_superseded"):
			invalidated += 1
		_queue_gap(claim_key, "stale_evidence", {}, _claim_evidence.get(claim_key, ledger))
	return {"stale_claims": stale_claims, "invalidated": invalidated}

func _invalidate_promoted_claim(claim_key: String, reason: String) -> bool:
	if not _claim_evidence.has(claim_key):
		return true
	var ledger: Dictionary = _claim_evidence.get(claim_key, {})
	var source := str(ledger.get("promoted_source", ""))
	if source.is_empty():
		if not str(ledger.get("promoted_fingerprint", "")).is_empty():
			ledger["status"] = "legacy_invalidation_pending"
			ledger["invalidation_reason"] = reason
			_claim_evidence[claim_key] = ledger
			_record_audit("invalidation_pending", claim_key, {"reason": reason, "legacy": true})
			return false
		return true
	var result := ai.remove_knowledge_source(source) if ai != null else {"ok": false, "error": "AIClient unavailable"}
	if not bool(result.get("ok", false)):
		ledger["status"] = "invalidation_failed"
		ledger["invalidation_reason"] = reason
		ledger["invalidation_error"] = str(result.get("error", "remove_source_failed"))
		_claim_evidence[claim_key] = ledger
		_record_audit("invalidation_failed", claim_key, {"reason": reason, "source": source})
		return false
	var history: Array = ledger.get("promotion_history", []) if ledger.get("promotion_history", []) is Array else []
	history.append({
		"source": source,
		"fingerprint": str(ledger.get("promoted_fingerprint", "")),
		"content_sha256": str(ledger.get("promoted_content_sha256", "")),
		"stance": str(ledger.get("promoted_stance", "")),
		"promoted_at": str(ledger.get("promoted_at", "")),
		"invalidated_at": Time.get_datetime_string_from_system(true),
		"invalidated_unix": int(Time.get_unix_time_from_system()),
		"reason": reason
	})
	if history.size() > 50:
		history = history.slice(history.size() - 50, history.size())
	ledger["promotion_history"] = history
	ledger["promoted_source"] = ""
	ledger["promoted_fingerprint"] = ""
	ledger["promoted_content_sha256"] = ""
	ledger["promoted_stance"] = ""
	ledger["status"] = "invalidated"
	ledger["invalidation_reason"] = reason
	ledger["invalidated_at"] = Time.get_datetime_string_from_system(true)
	ledger["updated_at"] = ledger["invalidated_at"]
	ledger["updated_unix"] = int(Time.get_unix_time_from_system())
	_claim_evidence[claim_key] = ledger
	_stats["invalidated"] = int(_stats.get("invalidated", 0)) + 1
	_record_audit("invalidated", claim_key, {"reason": reason, "source": source})
	return true

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

func _gap_priority(reason: String) -> int:
	match reason:
		"contradiction": return 100
		"invalidation_failed": return 95
		"stale_evidence": return 90
		"needs_corroboration": return 70
		"weak_evidence": return 50
		_: return 40

func _queue_gap(claim_key: String, reason: String, item: Dictionary, ledger: Dictionary) -> void:
	if claim_key.is_empty():
		return
	var now := int(Time.get_unix_time_from_system())
	var gap_id := (claim_key + "|" + reason).sha256_text().to_lower()
	var title := _clean(str(item.get("title", "")), 300)
	if title.is_empty():
		title = _clean(str(item.get("summary", "")), 300)
	if title.is_empty():
		title = _clean(str(ledger.get("claim_label", claim_key.substr(0, 16))), 300)
	var question := "Найти более надёжный источник: " + title
	if reason == "needs_corroboration":
		question = "Найти независимый источник для подтверждения: " + title
	elif reason == "contradiction":
		question = "Разрешить противоречие независимыми источниками: " + title
	elif reason == "stale_evidence":
		question = "Перепроверить устаревшие доказательства: " + title
	elif reason == "invalidation_failed":
		question = "Проверить безопасное удаление недостоверного знания: " + title
	var support_count := _family_count(ledger, "support_families")
	var oppose_count := _family_count(ledger, "oppose_families")
	for i in range(_gap_questions.size()):
		var existing = _gap_questions[i]
		if existing is Dictionary and str(existing.get("id", "")) == gap_id:
			var updated: Dictionary = existing
			var was_resolved := str(updated.get("status", "open")) != "open"
			updated["status"] = "open"
			updated["question"] = question
			updated["priority"] = _gap_priority(reason)
			updated["support_families"] = support_count
			updated["oppose_families"] = oppose_count
			updated["updated_at"] = Time.get_datetime_string_from_system(true)
			updated["updated_unix"] = now
			if was_resolved:
				updated["next_retry_unix"] = now
			_gap_questions[i] = updated
			return
	_gap_questions.append({
		"id": gap_id,
		"claim_key": claim_key,
		"reason": reason,
		"question": question,
		"status": "open",
		"priority": _gap_priority(reason),
		"attempts": 0,
		"next_retry_unix": now,
		"support_families": support_count,
		"oppose_families": oppose_count,
		"created_at": Time.get_datetime_string_from_system(true),
		"created_unix": now,
		"updated_at": Time.get_datetime_string_from_system(true),
		"updated_unix": now
	})
	_record_audit("gap_opened", claim_key, {"reason": reason, "gap_id": gap_id})

func _resolve_gap(claim_key: String) -> void:
	var now := int(Time.get_unix_time_from_system())
	for i in range(_gap_questions.size()):
		var entry = _gap_questions[i]
		if not entry is Dictionary or str(entry.get("claim_key", "")) != claim_key:
			continue
		if str(entry.get("status", "open")) == "open":
			var updated: Dictionary = entry
			updated["status"] = "resolved"
			updated["resolved_at"] = Time.get_datetime_string_from_system(true)
			updated["resolved_unix"] = now
			updated["updated_at"] = updated["resolved_at"]
			updated["updated_unix"] = now
			_gap_questions[i] = updated
	_record_audit("gap_resolved", claim_key, {})

func open_questions(limit := 20) -> Array:
	var out: Array = []
	var bounded := maxi(1, int(limit))
	for entry in _gap_questions:
		if entry is Dictionary and str(entry.get("status", "open")) == "open":
			out.append(entry.duplicate(true))
	out.sort_custom(func(a, b):
		var pa := int(a.get("priority", 0))
		var pb := int(b.get("priority", 0))
		if pa != pb:
			return pa > pb
		return int(a.get("updated_unix", 0)) < int(b.get("updated_unix", 0))
	)
	return out.slice(0, mini(bounded, out.size()))

func next_question() -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	for question in open_questions(MAX_GAP_QUESTIONS):
		if question is Dictionary and int(question.get("next_retry_unix", 0)) <= now:
			return question
	return {}

func mark_question_attempt(gap_id: String, outcome := "attempted") -> Dictionary:
	var clean_id := gap_id.strip_edges()
	if clean_id.is_empty():
		return {"ok": false, "error": "gap_id is required"}
	var now := int(Time.get_unix_time_from_system())
	for i in range(_gap_questions.size()):
		var entry = _gap_questions[i]
		if not entry is Dictionary or str(entry.get("id", "")) != clean_id:
			continue
		var updated: Dictionary = entry
		var attempts := int(updated.get("attempts", 0)) + 1
		var exponent := mini(8, maxi(0, attempts - 1))
		var delay := mini(GAP_MAX_RETRY_SECONDS, GAP_BASE_RETRY_SECONDS * int(pow(2.0, float(exponent))))
		updated["attempts"] = attempts
		updated["last_outcome"] = str(outcome).substr(0, 120)
		updated["last_attempt_unix"] = now
		updated["next_retry_unix"] = now + delay
		updated["updated_unix"] = now
		updated["updated_at"] = Time.get_datetime_string_from_system(true)
		_gap_questions[i] = updated
		_stats["gap_attempts"] = int(_stats.get("gap_attempts", 0)) + 1
		_record_audit("gap_attempted", str(updated.get("claim_key", "")), {"gap_id": clean_id, "attempts": attempts, "next_retry_unix": now + delay})
		_save_state()
		return {"ok": true, "gap": updated.duplicate(true)}
	return {"ok": false, "error": "gap not found", "gap_id": clean_id}

func provenance_for_claim(claim_key: String) -> Dictionary:
	var ledger: Dictionary = _claim_evidence.get(claim_key, {}).duplicate(true)
	var events: Array = []
	for event in _audit_events:
		if event is Dictionary and str(event.get("claim_key", "")) == claim_key:
			events.append(event.duplicate(true))
	return {"claim_key": claim_key, "ledger": ledger, "events": events}

func _record_audit(event_name: String, claim_key: String, details: Dictionary) -> void:
	var now := int(Time.get_unix_time_from_system())
	_audit_events.append({
		"event": event_name,
		"claim_key": claim_key,
		"details": details.duplicate(true),
		"timestamp_unix": now,
		"timestamp": Time.get_datetime_string_from_system(true)
	})
	_trim_audit_events()

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
		"audit_events": _audit_events.size(),
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
	var rows: Array = []
	for key in _claim_evidence.keys():
		var ledger: Dictionary = _claim_evidence.get(key, {})
		rows.append({"key": str(key), "updated": int(ledger.get("updated_unix", ledger.get("first_seen_unix", 0))), "promoted": not str(ledger.get("promoted_source", "")).is_empty()})
	rows.sort_custom(func(a, b):
		if bool(a.get("promoted", false)) != bool(b.get("promoted", false)):
			return not bool(a.get("promoted", false))
		return int(a.get("updated", 0)) < int(b.get("updated", 0))
	)
	var remove_count := _claim_evidence.size() - MAX_CLAIMS
	for i in range(remove_count):
		_claim_evidence.erase(str((rows[i] as Dictionary).get("key", "")))

func _trim_gap_questions() -> void:
	if _gap_questions.size() <= MAX_GAP_QUESTIONS:
		return
	var resolved: Array = []
	var open: Array = []
	for entry in _gap_questions:
		if not entry is Dictionary:
			continue
		if str(entry.get("status", "open")) == "open":
			open.append(entry)
		else:
			resolved.append(entry)
	open.sort_custom(func(a, b):
		var pa := int(a.get("priority", 0))
		var pb := int(b.get("priority", 0))
		if pa != pb:
			return pa > pb
		return int(a.get("updated_unix", 0)) > int(b.get("updated_unix", 0))
	)
	resolved.sort_custom(func(a, b): return int(a.get("updated_unix", 0)) > int(b.get("updated_unix", 0)))
	var combined: Array = []
	combined.append_array(open)
	combined.append_array(resolved)
	_gap_questions = combined.slice(0, mini(MAX_GAP_QUESTIONS, combined.size()))

func _trim_audit_events() -> void:
	if _audit_events.size() > MAX_AUDIT_EVENTS:
		_audit_events = _audit_events.slice(_audit_events.size() - MAX_AUDIT_EVENTS, _audit_events.size())

func _read_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _load_state() -> void:
	var parsed := _read_state(STATE_PATH)
	if parsed.is_empty():
		parsed = _read_state(STATE_BACKUP_PATH)
	if parsed.is_empty():
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
	var audit_events = parsed.get("audit_events", [])
	if audit_events is Array:
		_audit_events = audit_events
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
	var now := int(Time.get_unix_time_from_system())
	for key in _claim_evidence.keys():
		var ledger: Dictionary = _claim_evidence.get(key, {})
		ledger["claim_key"] = str(key)
		_claim_evidence[key] = _refresh_ledger(ledger, now)
	for i in range(_gap_questions.size()):
		var gap = _gap_questions[i]
		if not gap is Dictionary:
			continue
		var migrated: Dictionary = gap
		if not migrated.has("priority"):
			migrated["priority"] = _gap_priority(str(migrated.get("reason", "")))
		if not migrated.has("attempts"):
			migrated["attempts"] = 0
		if not migrated.has("next_retry_unix"):
			migrated["next_retry_unix"] = 0
		_gap_questions[i] = migrated
	_trim_claim_evidence()
	_trim_gap_questions()
	_trim_audit_events()

func _save_state() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STATE_PATH.get_base_dir()))
	var payload := JSON.stringify({
		"version": 2,
		"seen": _seen,
		"seen_content": _seen_content,
		"claim_evidence": _claim_evidence,
		"gap_questions": _gap_questions,
		"audit_events": _audit_events,
		"stats": _stats,
		"updated_at": Time.get_datetime_string_from_system(true),
		"updated_unix": int(Time.get_unix_time_from_system())
	}, "  ")
	var temp := FileAccess.open(STATE_TEMP_PATH, FileAccess.WRITE)
	if temp == null:
		return
	temp.store_string(payload)
	temp.flush()
	temp.close()
	var target_abs := ProjectSettings.globalize_path(STATE_PATH)
	var backup_abs := ProjectSettings.globalize_path(STATE_BACKUP_PATH)
	var temp_abs := ProjectSettings.globalize_path(STATE_TEMP_PATH)
	if FileAccess.file_exists(STATE_BACKUP_PATH):
		DirAccess.remove_absolute(backup_abs)
	var had_target := FileAccess.file_exists(STATE_PATH)
	if had_target and DirAccess.rename_absolute(target_abs, backup_abs) != OK:
		DirAccess.remove_absolute(temp_abs)
		return
	if DirAccess.rename_absolute(temp_abs, target_abs) != OK:
		if had_target and FileAccess.file_exists(STATE_BACKUP_PATH):
			DirAccess.rename_absolute(backup_abs, target_abs)
		return
