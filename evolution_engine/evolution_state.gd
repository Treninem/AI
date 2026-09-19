class_name AuroraEvolutionState
extends RefCounted

## Minimal state container for controlled self-improvement.
## This does not execute mutations or change AuroraFox code.

var cycle_id: String = ""
var baseline_id: String = ""
var phase: String = "idle"
var candidates: Array[String] = []
var accepted_candidate: String = ""
var rejected_candidates: Array[String] = []

func reset() -> void:
	cycle_id = ""
	baseline_id = ""
	phase = "idle"
	candidates.clear()
	accepted_candidate = ""
	rejected_candidates.clear()

func to_dict() -> Dictionary:
	return {
		"cycle_id": cycle_id,
		"baseline_id": baseline_id,
		"phase": phase,
		"candidates": candidates,
		"accepted_candidate": accepted_candidate,
		"rejected_candidates": rejected_candidates
	}
