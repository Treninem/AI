extends SceneTree

class FakeResearchAI:
	extends AIClient
	var imports: Array = []
	var removals: Array = []

	func import_knowledge_text(text: String, source := "manual", metadata: Dictionary = {}) -> Dictionary:
		imports.append({"text": text, "source": source, "metadata": metadata.duplicate(true)})
		return {"ok": true, "source": source}

	func remove_knowledge_source(source: String) -> Dictionary:
		removals.append(source)
		return {"ok": true, "source": source, "removed": 1, "structured_removed": 0, "registry_removed": 0}

func _fail(message: String, code: int) -> void:
	push_error(message)
	_cleanup()
	quit(code)

func _cleanup() -> void:
	for path in [
		AuroraLearningCurator.STATE_PATH,
		AuroraLearningCurator.STATE_BACKUP_PATH,
		AuroraLearningCurator.STATE_TEMP_PATH
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _fresh_gate(fake_ai: FakeResearchAI) -> AuroraLearningCurator:
	var gate := AuroraLearningCurator.new()
	gate.ai = fake_ai
	gate.enabled = true
	gate._seen.clear()
	gate._seen_content.clear()
	gate._claim_evidence.clear()
	gate._gap_questions.clear()
	gate._audit_events.clear()
	return gate

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_cleanup()
	var fake_ai := FakeResearchAI.new()
	var gate := _fresh_gate(fake_ai)

	var strong_support := {
		"source": "arxiv",
		"title": "Durable recovery journal prevents duplicate destructive replay",
		"summary": "A detailed technical report states that durable acknowledgements and idempotent transition journals prevent destructive actions from being replayed after interrupted local-agent recovery.",
		"url": "https://arxiv.org/abs/2609.50001",
		"metadata": {"stance": "support"}
	}
	gate._on_research_completed({"query": "recovery journal", "items": [strong_support]})
	if fake_ai.imports.size() != 1:
		_fail("Strong evidence was not promoted", 2)
		return
	var promoted: Dictionary = fake_ai.imports[0]
	var promoted_source := str(promoted.get("source", ""))
	if not promoted_source.begins_with("autonomous_research:arxiv:"):
		_fail("Research promotion is not claim-scoped", 3)
		return
	var claim_key := str((promoted.get("metadata", {}) as Dictionary).get("claim_key", ""))
	if claim_key.is_empty():
		_fail("Promotion lost claim key", 4)
		return

	# A later independent contradiction must revoke the previously promoted source
	# before that stale fact can remain authoritative in Core Knowledge.
	var oppose := {
		"source": "github",
		"title": strong_support["title"],
		"summary": "An independent implementation report contradicts the claim and documents that its recovery snapshot is authoritative, so previously acknowledged transition records are not replayed after restart.",
		"url": "https://github.com/example/recovery-counterexample",
		"metadata": {"stars": 0, "stance": "oppose"}
	}
	gate._on_research_completed({"query": "recovery journal contradiction", "items": [oppose]})
	if promoted_source not in fake_ai.removals:
		_fail("Late contradiction did not invalidate previously promoted Core Knowledge", 5)
		return
	var ledger: Dictionary = gate.provenance_for_claim(claim_key).get("ledger", {})
	if str(ledger.get("promoted_source", "")) != "" or str(ledger.get("status", "")) not in ["invalidated", "contradicted"]:
		_fail("Contradicted claim retained active promotion authority", 6)
		return
	var questions := gate.open_questions(20)
	var found_contradiction := false
	for question in questions:
		if question is Dictionary and str(question.get("claim_key", "")) == claim_key and str(question.get("reason", "")) == "contradiction":
			found_contradiction = true
			break
	if not found_contradiction:
		_fail("Late contradiction did not create a resolution gap", 7)
		return

	# Same canonical URL with changed content supersedes the old observation rather
	# than counting old and new versions as independent evidence.
	var update_ai := FakeResearchAI.new()
	var update_gate := _fresh_gate(update_ai)
	var original := strong_support.duplicate(true)
	original["url"] = "https://arxiv.org/abs/2609.50002"
	update_gate._on_research_completed({"query": "source update", "items": [original]})
	var updated := original.duplicate(true)
	updated["summary"] = "The revised report now states the opposite conclusion after a reproduced failure: journal replay is unsafe for already acknowledged destructive operations and snapshots must remain authoritative."
	updated["metadata"] = {"stance": "oppose", "evidence_action": "supersede"}
	update_gate._on_research_completed({"query": "source update", "items": [updated]})
	var update_claim := update_gate._claim_key(updated)
	var update_ledger: Dictionary = update_gate.provenance_for_claim(update_claim).get("ledger", {})
	if int(update_ledger.get("superseded_evidence_count", 0)) < 1:
		_fail("Changed canonical source did not supersede its previous observation", 8)
		return
	if update_ai.removals.is_empty():
		_fail("Source stance reversal did not invalidate the old promotion", 9)
		return

	# A same-stance revision is still a replacement, not corroboration. The old
	# promoted text must be removed and the revised observation must be imported.
	var revision_ai := FakeResearchAI.new()
	var revision_gate := _fresh_gate(revision_ai)
	var revision_original := strong_support.duplicate(true)
	revision_original["url"] = "https://arxiv.org/abs/2609.50003"
	revision_gate._on_research_completed({"query": "same stance revision", "items": [revision_original]})
	var revision_old_source := str((revision_ai.imports[0] as Dictionary).get("source", ""))
	var revision := revision_original.duplicate(true)
	revision["summary"] = "A revised and expanded technical report still supports durable recovery journals, but updates the implementation guidance and evidence after a larger restart study."
	revision["metadata"] = {"stance": "support", "evidence_action": "supersede"}
	revision_gate._on_research_completed({"query": "same stance revision", "items": [revision]})
	if revision_old_source not in revision_ai.removals:
		_fail("Same-stance source revision left old promoted text authoritative", 18)
		return
	if revision_ai.imports.size() != 2 or not str((revision_ai.imports[1] as Dictionary).get("text", "")).contains("revised and expanded"):
		_fail("Same-stance source revision did not replace promoted knowledge", 19)
		return

	# A retraction is control evidence about the previous observation, not a new
	# supporting fact. It must revoke the old promotion and open a revalidation gap
	# without importing the retraction notice as authoritative claim content.
	var retract_ai := FakeResearchAI.new()
	var retract_gate := _fresh_gate(retract_ai)
	var retract_original := strong_support.duplicate(true)
	retract_original["url"] = "https://arxiv.org/abs/2609.50004"
	retract_gate._on_research_completed({"query": "retraction", "items": [retract_original]})
	var retract_old_source := str((retract_ai.imports[0] as Dictionary).get("source", ""))
	var retraction := retract_original.duplicate(true)
	retraction["summary"] = "This publication has been withdrawn after the authors found a material flaw in the recovery experiment. The prior conclusion must not be treated as current evidence."
	retraction["metadata"] = {"retracted": true, "evidence_action": "retract", "stance": "support"}
	retract_gate._on_research_completed({"query": "retraction", "items": [retraction]})
	if retract_old_source not in retract_ai.removals:
		_fail("Explicit retraction did not revoke prior promoted knowledge", 20)
		return
	if retract_ai.imports.size() != 1:
		_fail("Retraction notice was incorrectly promoted as fresh claim evidence", 21)
		return
	var retract_claim := retract_gate._claim_key(retraction)
	var retract_gap := false
	for question in retract_gate.open_questions(20):
		if question is Dictionary and str(question.get("claim_key", "")) == retract_claim and str(question.get("reason", "")) == "retracted_evidence":
			retract_gap = true
			break
	if not retract_gap:
		_fail("Explicit retraction did not open a revalidation gap", 22)
		return

	# Evidence that has exceeded its lifecycle must lose promotion authority and
	# open a revalidation gap. We force the timestamps old to keep this test fast.
	var stale_ai := FakeResearchAI.new()
	var stale_gate := _fresh_gate(stale_ai)
	stale_gate._on_research_completed({"query": "stale evidence", "items": [strong_support]})
	var stale_claim := stale_gate._claim_key(strong_support)
	var stale_ledger: Dictionary = stale_gate._claim_evidence.get(stale_claim, {})
	var observations: Dictionary = stale_ledger.get("observations", {})
	for fingerprint in observations.keys():
		var observation: Dictionary = observations.get(fingerprint, {})
		observation["last_seen_unix"] = 1
		observation["max_age_seconds"] = 3600
		observations[fingerprint] = observation
	stale_ledger["observations"] = observations
	stale_gate._claim_evidence[stale_claim] = stale_ledger
	var lifecycle := stale_gate._sweep_evidence_lifecycle()
	if int(lifecycle.get("invalidated", 0)) != 1 or stale_ai.removals.is_empty():
		_fail("Expired evidence did not invalidate active Core Knowledge", 10)
		return
	var stale_found := false
	for question in stale_gate.open_questions(20):
		if question is Dictionary and str(question.get("claim_key", "")) == stale_claim and str(question.get("reason", "")) == "stale_evidence":
			stale_found = true
			break
	if not stale_found:
		_fail("Expired evidence did not create a revalidation gap", 11)
		return

	# Gap retries are bounded by exponential backoff and the queue survives state
	# reload. A failed attempt cannot hot-loop every autonomous cycle.
	var next := stale_gate.next_question()
	if next.is_empty():
		_fail("Open gap was not schedulable", 12)
		return
	var gap_id := str(next.get("id", ""))
	var attempt := stale_gate.mark_question_attempt(gap_id, "no_new_evidence")
	if not bool(attempt.get("ok", false)):
		_fail("Gap attempt could not be recorded", 13)
		return
	var attempted_gap: Dictionary = attempt.get("gap", {})
	if int(attempted_gap.get("attempts", 0)) != 1 or int(attempted_gap.get("next_retry_unix", 0)) <= int(Time.get_unix_time_from_system()):
		_fail("Gap retry did not enter bounded backoff", 14)
		return
	if not stale_gate.next_question().is_empty():
		# There may be only this one gap in the fresh gate; it must be suppressed by backoff.
		_fail("Gap retry ignored its next_retry_unix backoff", 15)
		return
	stale_gate._save_state()
	var reloaded := AuroraLearningCurator.new()
	reloaded._load_state()
	var persisted := false
	for question in reloaded.open_questions(20):
		if question is Dictionary and str(question.get("id", "")) == gap_id and int(question.get("attempts", 0)) == 1:
			persisted = true
			break
	if not persisted:
		_fail("Gap retry/backoff state did not survive restart", 16)
		return
	var provenance := gate.provenance_for_claim(claim_key)
	var events: Array = provenance.get("events", [])
	var saw_promotion := false
	var saw_invalidation := false
	for event in events:
		if not event is Dictionary:
			continue
		if str(event.get("event", "")) == "promoted":
			saw_promotion = true
		elif str(event.get("event", "")) == "invalidated":
			saw_invalidation = true
	if not saw_promotion or not saw_invalidation:
		_fail("Provenance audit trail lost promotion/invalidation lifecycle", 17)
		return

	_cleanup()
	fake_ai.free()
	gate.free()
	update_ai.free()
	update_gate.free()
	revision_ai.free()
	revision_gate.free()
	retract_ai.free()
	retract_gate.free()
	stale_ai.free()
	stale_gate.free()
	reloaded.free()
	print("AURORA_RESEARCH_EVIDENCE_LIFECYCLE_SMOKE_OK")
	quit(0)
