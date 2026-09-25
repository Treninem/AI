class_name AuroraCommunityLanguageCurator
extends RefCounted

const CONTRACT := "aurorafox.impuls.community.v1"
const SOURCE := "impuls_anonymous"
const MEMORY_SOURCE := "aurorafox_impuls_bridge"
const MEMORY_KIND := "community_language_experience"
const MIN_DIALOGUE_QUALITY := 0.72
const MIN_DIALOGUE_CONFIDENCE := 0.65
const MIN_DIALOGUE_DIVERSITY := 3
const MIN_MODERATION_QUALITY := 0.62
const MIN_MODERATION_DIVERSITY := 2
const MIN_TOPIC_DIVERSITY := 4

var memory

func bind(memory_value) -> void:
	memory = memory_value

func curate(envelope: Dictionary) -> Dictionary:
	var event_id := str(envelope.get("id", "")).strip_edges()
	var payload = envelope.get("payload", {})
	if not payload is Dictionary:
		return _decision(event_id, "quarantined", "invalid_schema")

	var event: Dictionary = payload
	if str(event.get("schema", "")) != CONTRACT or str(event.get("source", "")) != SOURCE:
		return _decision(event_id, "quarantined", "invalid_schema")

	var labels = event.get("labels", {})
	if not labels is Dictionary:
		return _decision(event_id, "quarantined", "invalid_schema")
	if bool(labels.get("pii_detected", false)):
		return _decision(event_id, "quarantined", "privacy_risk")

	var kind := str(event.get("kind", ""))
	var quality := clampf(float(event.get("quality", 0.0)), 0.0, 1.0)
	var confidence := clampf(float(event.get("confidence", 0.0)), 0.0, 1.0)
	var diversity := maxi(0, int(event.get("diversity_bucket", 0)))
	var observations := maxi(1, int(event.get("observations", 1)))

	if kind == "dialogue_pattern":
		if bool(labels.get("spam", false)) or bool(labels.get("advertising", false)):
			return _decision(event_id, "rejected", "spam_or_advertising")
		if quality < MIN_DIALOGUE_QUALITY or confidence < MIN_DIALOGUE_CONFIDENCE:
			return _decision(event_id, "rejected", "low_quality")
		if diversity < MIN_DIALOGUE_DIVERSITY:
			return _decision(event_id, "rejected", "insufficient_diversity")
	elif kind == "moderation_feedback":
		if quality < MIN_MODERATION_QUALITY:
			return _decision(event_id, "rejected", "low_quality")
		if diversity < MIN_MODERATION_DIVERSITY and not bool(labels.get("human_confirmed", false)):
			return _decision(event_id, "rejected", "insufficient_diversity")
	elif kind == "topic_trend":
		# Community discussion may tell AuroraFox what people are talking about,
		# never whether the discussed claim is true. Topic signals remain research
		# candidates and are not written as factual Knowledge here.
		if not bool(labels.get("requires_external_verification", false)):
			return _decision(event_id, "quarantined", "unverified_topic")
		if diversity < MIN_TOPIC_DIVERSITY:
			return _decision(event_id, "rejected", "insufficient_diversity")
	else:
		return _decision(event_id, "quarantined", "invalid_schema")

	var compact := {
		"contract": CONTRACT,
		"event_id": event_id.substr(0, 64),
		"kind": kind,
		"language": str(event.get("language", "")).substr(0, 16),
		"topic": str(event.get("topic", "")).substr(0, 160),
		"pattern": str(event.get("pattern", "")).substr(0, 600),
		"features": _compact_strings(event.get("features", []), 16, 80),
		"labels": _compact_labels(labels),
		"quality": quality,
		"confidence": confidence,
		"diversity_bucket": diversity,
		"observations": observations,
		"candidate_only": true,
		"stable_core_promotion": false,
		"weight_training": false,
		"raw_chat_retained": false,
		"curated_at": Time.get_datetime_string_from_system(true)
	}

	if memory != null and memory.has_method("remember"):
		memory.remember(
			MEMORY_KIND,
			JSON.stringify(compact),
			MEMORY_SOURCE,
			0.72 if kind == "dialogue_pattern" else 0.66,
			confidence
		)
	else:
		return _decision(event_id, "quarantined", "invalid_schema")

	var result := _decision(event_id, "accepted", "curated")
	result["experience"] = compact
	return result

func _decision(event_id: String, disposition: String, reason: String) -> Dictionary:
	return {
		"ok": disposition == "accepted",
		"event_id": event_id.substr(0, 64),
		"disposition": disposition,
		"reason": reason,
		"stable_core_promotion": false,
		"weight_training": false,
		"requires_evolution_verification": disposition == "accepted"
	}

func _compact_labels(labels: Dictionary) -> Dictionary:
	return {
		"intent": str(labels.get("intent", "")).substr(0, 80),
		"style": str(labels.get("style", "")).substr(0, 80),
		"moderation_category": str(labels.get("moderation_category", "")).substr(0, 80),
		"understand_only": bool(labels.get("understand_only", false)),
		"spam": bool(labels.get("spam", false)),
		"advertising": bool(labels.get("advertising", false)),
		"human_confirmed": bool(labels.get("human_confirmed", false)),
		"requires_external_verification": bool(labels.get("requires_external_verification", false))
	}

func _compact_strings(value: Variant, limit: int, max_len: int) -> Array:
	var out: Array = []
	if not value is Array:
		return out
	for raw in value:
		if out.size() >= limit:
			break
		var item := str(raw).replace("\n", " ").replace("\r", " ").strip_edges().substr(0, max_len)
		if not item.is_empty() and not item in out:
			out.append(item)
	return out
