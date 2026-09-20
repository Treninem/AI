class_name AuroraEvolutionCoreTournamentAdapter
extends RefCounted

const MIN_MUTATIONS := 3
const MAX_MUTATIONS := 10
const MAX_GENERATION_ATTEMPTS := 24
const MAX_PENDING_WINNERS := 5
const STRATEGIES := [
	"minimal regression-first hardening",
	"edge-case and recovery robustness",
	"deterministic state consistency",
	"performance and allocation efficiency",
	"reasoning/retrieval quality without contract changes",
	"failure isolation and graceful degradation",
	"compatibility-preserving simplification",
	"bounded validation and input robustness"
]

var pipeline
var _pending_winners: Dictionary = {}
var _owns_pipeline_lock := false
var _pipeline_lock_acquired_at := 0

func bind(value) -> void:
	pipeline = value

func contract_status() -> Dictionary:
	if pipeline == null:
		return {"ok": false, "missing": ["pipeline:null"]}
	var missing: Array[String] = []
	for method in [
		"_bind_existing",
		"_signed_update_busy",
		"_select_target",
		"_read_res_source",
		"_propose",
		"_validate_candidate",
		"_verify_in_workspace",
		"_comparative_review",
		"_store_candidate",
		"status"
	]:
		if not pipeline.has_method(method):
			missing.append(method)
	if pipeline.get("_running") == null:
		missing.append("_running")
	return {"ok": missing.is_empty(), "missing": missing}

func run(goal: String, requested_target := "", requested_count := 5) -> Dictionary:
	var preflight := _preflight(requested_count)
	if not bool(preflight.get("ok", false)):
		return preflight
	var lock := _acquire_pipeline_lock()
	if not bool(lock.get("ok", false)):
		return lock
	var result: Dictionary = await _run_locked(goal, requested_target, requested_count)
	result["pipeline_lock_release"] = _release_pipeline_lock()
	return result

func prepare_winner(tournament_id: String) -> Dictionary:
	if not _pending_winners.has(tournament_id):
		return {"ok": false, "stage": "handoff", "error": "Unknown or expired Core tournament winner"}
	var preflight := _preflight(MIN_MUTATIONS)
	if not bool(preflight.get("ok", false)):
		return preflight
	var lock := _acquire_pipeline_lock()
	if not bool(lock.get("ok", false)):
		return lock
	var result: Dictionary = await _prepare_winner_locked(tournament_id)
	result["pipeline_lock_release"] = _release_pipeline_lock()
	return result

func lock_status() -> Dictionary:
	var held_seconds := 0
	if _owns_pipeline_lock and _pipeline_lock_acquired_at > 0:
		held_seconds = maxi(0, int(Time.get_unix_time_from_system()) - _pipeline_lock_acquired_at)
	return {
		"owned": _owns_pipeline_lock,
		"acquired_at": _pipeline_lock_acquired_at,
		"held_seconds": held_seconds
	}

func emergency_release_owned_lock(reason := "manual safety recovery") -> Dictionary:
	if not _owns_pipeline_lock:
		return {"ok": true, "released": false, "reason": reason}
	var release := _release_pipeline_lock()
	release["emergency"] = true
	release["reason"] = reason.substr(0, 500)
	return release

func _acquire_pipeline_lock() -> Dictionary:
	if pipeline == null:
		return {"ok": false, "stage": "core_lock", "error": "CoreImprovementPipeline is unavailable"}
	if _owns_pipeline_lock:
		return {"ok": false, "stage": "core_lock", "error": "Evolution already owns the Core pipeline lock"}
	if bool(pipeline.get("_running")):
		return {"ok": false, "stage": "busy", "error": "Existing CoreImprovementPipeline is already running"}
	pipeline.set("_running", true)
	_owns_pipeline_lock = true
	_pipeline_lock_acquired_at = int(Time.get_unix_time_from_system())
	return {"ok": true, "owned": true, "acquired_at": _pipeline_lock_acquired_at}

func _release_pipeline_lock() -> Dictionary:
	if not _owns_pipeline_lock:
		return {"ok": true, "released": false}
	if pipeline != null:
		pipeline.set("_running", false)
	var held_seconds := maxi(0, int(Time.get_unix_time_from_system()) - _pipeline_lock_acquired_at) if _pipeline_lock_acquired_at > 0 else 0
	_owns_pipeline_lock = false
	_pipeline_lock_acquired_at = 0
	return {"ok": true, "released": true, "held_seconds": held_seconds}

func _preflight(requested_count: int) -> Dictionary:
	var contract := contract_status()
	if not bool(contract.get("ok", false)):
		return {"ok": false, "stage": "core_contract", "error": "CoreImprovementPipeline contract is incomplete", "details": contract}
	if OS.get_name() != "Windows":
		return {"ok": false, "stage": "platform", "error": "Core source tournament verification currently requires Windows", "platform": OS.get_name()}
	if requested_count < MIN_MUTATIONS or requested_count > MAX_MUTATIONS:
		return {"ok": false, "stage": "population", "error": "Core mutation population must be within 3..10"}
	pipeline._bind_existing()
	if pipeline.get("ai") == null or pipeline.get("tools") == null:
		return {"ok": false, "stage": "setup", "error": "Existing CoreImprovementPipeline dependencies are not ready"}
	if bool(pipeline._signed_update_busy()):
		return {"ok": false, "stage": "update_guard", "error": "signed product update has priority", "deferred": true}
	return {"ok": true}

func _run_locked(goal: String, requested_target: String, requested_count: int) -> Dictionary:
	var clean_goal := goal.strip_edges()
	if clean_goal.is_empty():
		clean_goal = "Improve AuroraFox Core quality and robustness without regressions"
	var target := str(pipeline._select_target(clean_goal, requested_target))
	if target.is_empty():
		return {"ok": false, "stage": "target", "error": "Target is outside the existing Core allowlist"}
	var source_result = pipeline._read_res_source(target)
	if not source_result is Dictionary or not bool(source_result.get("ok", false)):
		return {"ok": false, "stage": "baseline", "error": "Cannot read stable Core baseline", "details": source_result}
	var original := str(source_result.get("content", ""))
	var baseline_sha := _sha256_text(original)

	var population: Array = []
	var finalists: Array = []
	var seen_hashes: Dictionary = {}
	var generation_errors: Array = []
	var attempt := 0

	while population.size() < requested_count and attempt < MAX_GENERATION_ATTEMPTS:
		var strategy := str(STRATEGIES[attempt % STRATEGIES.size()])
		var mutation_goal := "%s\nMutation %d strategy: %s. Produce a materially distinct candidate from other strategies while preserving all public contracts." % [
			clean_goal,
			attempt + 1,
			strategy
		]
		var proposal_result = await pipeline._propose(mutation_goal, target, original)
		attempt += 1
		if not proposal_result is Dictionary or not bool(proposal_result.get("ok", false)):
			generation_errors.append(_compact_error("proposal", proposal_result))
			continue
		var proposal: Dictionary = proposal_result.get("proposal", {})
		var content := str(proposal.get("content", ""))
		var candidate_sha := _sha256_text(content)
		if candidate_sha.is_empty() or seen_hashes.has(candidate_sha):
			generation_errors.append({"stage": "dedupe", "error": "duplicate Core mutation rejected", "sha256": candidate_sha})
			continue
		seen_hashes[candidate_sha] = true

		var validation = pipeline._validate_candidate(target, original, proposal)
		var candidate := {
			"index": population.size(),
			"strategy": strategy,
			"sha256": candidate_sha,
			"verified": false,
			"score": 0.0,
			"delta": 0.0,
			"proposal": proposal,
			"validation": validation if validation is Dictionary else {}
		}
		population.append(candidate)
		if not validation is Dictionary or not bool(validation.get("ok", false)):
			candidate["failure"] = _compact_error("validation", validation)
			population[population.size() - 1] = candidate
			continue

		var verification = await pipeline._verify_in_workspace(clean_goal, target, content)
		if not verification is Dictionary or not bool(verification.get("ok", false)):
			candidate["failure"] = _compact_error("verification", verification)
			population[population.size() - 1] = candidate
			continue
		verification["source_contract"] = validation.get("source_contract", {})

		var review = await pipeline._comparative_review(clean_goal, target, original, content, verification, proposal)
		if not review is Dictionary or not bool(review.get("ok", false)):
			candidate["failure"] = _compact_error("comparative_review", review)
			candidate["verification"] = _compact_verification(verification)
			population[population.size() - 1] = candidate
			continue

		candidate["verified"] = true
		candidate["score"] = float(review.get("candidate_score", 0.0))
		candidate["delta"] = float(review.get("delta", 0.0))
		candidate["verification"] = _compact_verification(verification)
		candidate["review"] = _compact_review(review)
		population[population.size() - 1] = candidate
		finalists.append(candidate)

	if population.size() < MIN_MUTATIONS:
		return {
			"ok": false,
			"stage": "population",
			"error": "Fewer than 3 distinct Core mutations were generated",
			"population_size": population.size(),
			"verified_count": finalists.size(),
			"generation_attempts": attempt,
			"generation_errors": generation_errors.slice(0, mini(generation_errors.size(), 20)),
			"scoreboard": _public_scoreboard(population)
		}
	if finalists.size() < MIN_MUTATIONS:
		return {
			"ok": false,
			"stage": "competition",
			"error": "Fewer than 3 Core mutations passed source, benchmark and comparative-review gates",
			"population_size": population.size(),
			"verified_count": finalists.size(),
			"generation_attempts": attempt,
			"scoreboard": _public_scoreboard(population)
		}

	finalists.sort_custom(func(a, b):
		var score_a := float(a.get("score", 0.0))
		var score_b := float(b.get("score", 0.0))
		if not is_equal_approx(score_a, score_b):
			return score_a > score_b
		var delta_a := float(a.get("delta", 0.0))
		var delta_b := float(b.get("delta", 0.0))
		if not is_equal_approx(delta_a, delta_b):
			return delta_a > delta_b
		return str(a.get("sha256", "")) < str(b.get("sha256", ""))
	)

	var winner: Dictionary = finalists[0]
	var winner_proposal: Dictionary = winner.get("proposal", {})
	var winner_content := str(winner_proposal.get("content", ""))
	var final_verification = await pipeline._verify_in_workspace(clean_goal, target, winner_content)
	if not final_verification is Dictionary or not bool(final_verification.get("ok", false)):
		return {
			"ok": false,
			"stage": "winner_final_verification",
			"error": "Winning Core mutation failed independent final benchmark verification",
			"details": _compact_error("winner_final_verification", final_verification),
			"scoreboard": _public_scoreboard(finalists)
		}
	var winner_validation = winner.get("validation", {})
	if winner_validation is Dictionary:
		final_verification["source_contract"] = winner_validation.get("source_contract", {})
	var final_review = await pipeline._comparative_review(clean_goal, target, original, winner_content, final_verification, winner_proposal)
	if not final_review is Dictionary or not bool(final_review.get("ok", false)):
		return {
			"ok": false,
			"stage": "winner_final_review",
			"error": "Winning Core mutation failed independent final comparative review",
			"details": _compact_error("winner_final_review", final_review),
			"scoreboard": _public_scoreboard(finalists)
		}
	final_verification["comparative_review"] = final_review

	var tournament_id := "%d_%s_%s" % [
		int(Time.get_unix_time_from_system()),
		baseline_sha.substr(0, 10),
		str(winner.get("sha256", "")).substr(0, 10)
	]
	_pending_winners[tournament_id] = {
		"created_unix": int(Time.get_unix_time_from_system()),
		"goal": clean_goal,
		"target": target,
		"baseline_sha256": baseline_sha,
		"winner": winner
	}
	_trim_pending()

	return {
		"ok": true,
		"tournament": true,
		"tournament_id": tournament_id,
		"goal": clean_goal,
		"target": target,
		"baseline_sha256": baseline_sha,
		"population_size": population.size(),
		"verified_count": finalists.size(),
		"generation_attempts": attempt,
		"winner": _public_candidate(winner),
		"scoreboard": _public_scoreboard(finalists),
		"final_verification": _compact_verification(final_verification),
		"final_review": _compact_review(final_review),
		"promotion_prepared": false,
		"applied_to_dev_checkout": false
	}

func _prepare_winner_locked(tournament_id: String) -> Dictionary:
	var pending: Dictionary = _pending_winners[tournament_id]
	var target := str(pending.get("target", ""))
	var source_result = pipeline._read_res_source(target)
	if not source_result is Dictionary or not bool(source_result.get("ok", false)):
		return {"ok": false, "stage": "baseline_recheck", "error": "Cannot reread Core baseline"}
	var original := str(source_result.get("content", ""))
	var expected_base := str(pending.get("baseline_sha256", ""))
	if _sha256_text(original) != expected_base:
		_pending_winners.erase(tournament_id)
		return {"ok": false, "stage": "baseline_recheck", "error": "Core baseline changed after tournament; rerun tournament"}

	var winner: Dictionary = pending.get("winner", {})
	var proposal: Dictionary = winner.get("proposal", {})
	var content := str(proposal.get("content", ""))
	if _sha256_text(content) != str(winner.get("sha256", "")):
		_pending_winners.erase(tournament_id)
		return {"ok": false, "stage": "winner_integrity", "error": "Pending Core winner content changed"}

	var validation = pipeline._validate_candidate(target, original, proposal)
	if not validation is Dictionary or not bool(validation.get("ok", false)):
		return {"ok": false, "stage": "handoff_validation", "error": "Core winner no longer passes source contract", "details": _compact_error("handoff_validation", validation)}

	var verification = await pipeline._verify_in_workspace(str(pending.get("goal", "")), target, content)
	if not verification is Dictionary or not bool(verification.get("ok", false)):
		return {"ok": false, "stage": "handoff_verification", "error": "Core winner failed clean handoff verification", "details": _compact_error("handoff_verification", verification)}
	verification["source_contract"] = validation.get("source_contract", {})

	var review = await pipeline._comparative_review(str(pending.get("goal", "")), target, original, content, verification, proposal)
	if not review is Dictionary or not bool(review.get("ok", false)):
		return {"ok": false, "stage": "handoff_review", "error": "Core winner failed clean handoff comparative review", "details": _compact_error("handoff_review", review)}
	verification["comparative_review"] = review

	var stored = pipeline._store_candidate(str(pending.get("goal", "")), target, original, proposal, verification)
	if not stored is Dictionary or not bool(stored.get("ok", false)):
		return {"ok": false, "stage": "handoff_store", "error": "Existing Core candidate storage rejected winner", "details": _compact_error("handoff_store", stored)}
	_pending_winners.erase(tournament_id)
	return {
		"ok": true,
		"stage": "promotion_handoff",
		"tournament_id": tournament_id,
		"target": target,
		"candidate_id": stored.get("candidate_id", ""),
		"candidate_path": stored.get("candidate_path", ""),
		"manifest_path": stored.get("manifest_path", ""),
		"base_sha256": expected_base,
		"candidate_sha256": _sha256_text(content),
		"verified": true,
		"benchmark_verified": true,
		"review_improved": true,
		"promotion": "signed_update",
		"applied_to_dev_checkout": false
	}

func _public_scoreboard(candidates: Array) -> Array:
	var out: Array = []
	for candidate in candidates:
		if candidate is Dictionary:
			out.append(_public_candidate(candidate))
	return out

func _public_candidate(candidate: Dictionary) -> Dictionary:
	return {
		"index": int(candidate.get("index", -1)),
		"strategy": str(candidate.get("strategy", "")).substr(0, 200),
		"sha256": str(candidate.get("sha256", "")).substr(0, 64),
		"verified": bool(candidate.get("verified", false)),
		"score": float(candidate.get("score", 0.0)),
		"delta": float(candidate.get("delta", 0.0)),
		"review": candidate.get("review", {}),
		"verification": candidate.get("verification", {}),
		"failure": candidate.get("failure", {})
	}

func _compact_review(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var row: Dictionary = value
	return {
		"ok": bool(row.get("ok", false)),
		"baseline_score": float(row.get("baseline_score", 0.0)),
		"candidate_score": float(row.get("candidate_score", 0.0)),
		"delta": float(row.get("delta", 0.0)),
		"minimum_delta": float(row.get("minimum_delta", 0.0)),
		"reasons": row.get("reasons", []),
		"risks": row.get("risks", [])
	}

func _compact_verification(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var row: Dictionary = value
	return {
		"ok": bool(row.get("ok", false)),
		"stage": str(row.get("stage", "")).substr(0, 120),
		"verification_mode": str(row.get("verification_mode", "")).substr(0, 200),
		"sandbox_path": str(row.get("sandbox_path", "")).substr(0, 500),
		"benchmark": row.get("benchmark", {}),
		"source_contract": row.get("source_contract", {})
	}

func _compact_error(stage: String, value: Variant) -> Dictionary:
	if value is Dictionary:
		return {
			"stage": str(value.get("stage", stage)).substr(0, 120),
			"error": str(value.get("error", "rejected")).substr(0, 1200)
		}
	return {"stage": stage, "error": "invalid result"}

func _trim_pending() -> void:
	while _pending_winners.size() > MAX_PENDING_WINNERS:
		var oldest_key := ""
		var oldest_time := 9223372036854775807
		for key in _pending_winners.keys():
			var row: Dictionary = _pending_winners[key]
			var created := int(row.get("created_unix", 0))
			if created < oldest_time:
				oldest_time = created
				oldest_key = str(key)
		if oldest_key.is_empty():
			break
		_pending_winners.erase(oldest_key)

func _sha256_text(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()
