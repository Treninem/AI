class_name AuroraEvolutionMetricsAdapter
extends RefCounted

func summarize(kind: String, result: Dictionary) -> Dictionary:
	var population := int(result.get("population_size", 0))
	var verified := int(result.get("verified_count", 0))
	var winner = result.get("winner", {})
	var final_review = result.get("final_review", {})
	var final_verification = result.get("final_verification", {})
	var verification_ratio := 0.0
	if population > 0:
		verification_ratio = float(verified) / float(population)

	var quality := {"available": false}
	if final_review is Dictionary and not final_review.is_empty():
		quality = {
			"available": true,
			"baseline": float(final_review.get("baseline_score", 0.0)),
			"candidate": float(final_review.get("candidate_score", 0.0)),
			"delta": float(final_review.get("delta", 0.0)),
			"minimum_delta": float(final_review.get("minimum_delta", 0.0))
		}
	elif winner is Dictionary and winner.has("score"):
		quality = {
			"available": true,
			"candidate": float(winner.get("score", 0.0)),
			"baseline": null,
			"delta": null
		}

	var benchmark: Dictionary = {}
	var speed := {"available": false}
	if final_verification is Dictionary:
		var raw_benchmark = final_verification.get("benchmark", {})
		if raw_benchmark is Dictionary:
			benchmark = _compact_benchmark(raw_benchmark)
			speed = _speed_metrics(raw_benchmark)

	var benchmark_ok := true
	if not benchmark.is_empty() and benchmark.has("ok"):
		benchmark_ok = bool(benchmark.get("ok", false))

	return {
		"kind": kind.substr(0, 120),
		"population_size": population,
		"verified_count": verified,
		"verification_ratio": verification_ratio,
		"quality": quality,
		"stability": {
			"available": true,
			"accepted": bool(result.get("ok", false)),
			"final_verified": bool(result.get("verified", false)) or (final_verification is Dictionary and bool(final_verification.get("ok", false))),
			"benchmark_no_regression": benchmark_ok
		},
		"speed": speed,
		"memory": {"available": false},
		"benchmark": benchmark
	}

func _speed_metrics(benchmark: Dictionary) -> Dictionary:
	var baseline = benchmark.get("baseline", {})
	var candidate = benchmark.get("candidate", {})
	if not baseline is Dictionary or not candidate is Dictionary:
		return {"available": false}
	var baseline_ms := _elapsed_total(baseline)
	var candidate_ms := _elapsed_total(candidate)
	if baseline_ms <= 0.0 or candidate_ms <= 0.0:
		return {"available": false}
	return {
		"available": true,
		"baseline_ms": baseline_ms,
		"candidate_ms": candidate_ms,
		"delta_ms": candidate_ms - baseline_ms,
		"ratio": candidate_ms / baseline_ms
	}

func _elapsed_total(summary: Dictionary) -> float:
	var evidence = summary.get("evidence", [])
	if not evidence is Array:
		return 0.0
	var total := 0.0
	for row in evidence:
		if row is Dictionary:
			total += maxf(0.0, float(row.get("elapsed_ms", 0.0)))
	return total

func _compact_benchmark(benchmark: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in ["ok", "baseline_ok", "candidate_ok", "baseline_passed", "candidate_passed", "no_regression", "passed", "failed", "total"]:
		if benchmark.has(key):
			out[key] = benchmark.get(key)
	for key in ["baseline", "candidate"]:
		var value = benchmark.get(key, {})
		if value is Dictionary:
			out[key] = {
				"ok": bool(value.get("ok", false)),
				"passed": int(value.get("passed", 0)),
				"failed": int(value.get("failed", 0)),
				"total": int(value.get("total", 0)),
				"evidence": _compact_evidence(value.get("evidence", []))
			}
	return out

func _compact_evidence(value: Variant) -> Array:
	var out: Array = []
	if not value is Array:
		return out
	for row in value:
		if not row is Dictionary:
			continue
		out.append({
			"ok": bool(row.get("ok", false)),
			"elapsed_ms": float(row.get("elapsed_ms", 0.0)),
			"code": int(row.get("code", -1))
		})
	return out
