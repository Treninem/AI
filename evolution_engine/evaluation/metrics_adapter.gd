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
	if final_verification is Dictionary:
		var raw_benchmark = final_verification.get("benchmark", {})
		if raw_benchmark is Dictionary:
			benchmark = _compact_benchmark(raw_benchmark)

	return {
		"kind": kind.substr(0, 120),
		"population_size": population,
		"verified_count": verified,
		"verification_ratio": verification_ratio,
		"quality": quality,
		"stability": {
			"available": true,
			"accepted": bool(result.get("ok", false)),
			"final_verified": bool(result.get("verified", false)) or (final_verification is Dictionary and bool(final_verification.get("ok", false)))
		},
		"speed": {"available": false},
		"memory": {"available": false},
		"benchmark": benchmark
	}

func _compact_benchmark(benchmark: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in ["ok", "passed", "failed", "total", "duration_ms", "elapsed_ms", "latency_ms", "peak_memory_mb", "memory_mb"]:
		if benchmark.has(key):
			out[key] = benchmark.get(key)
	return out
