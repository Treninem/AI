class_name AuroraEvolutionCycle
extends RefCounted

## Controlled self-improvement lifecycle.
## This module does not mutate production code directly.

signal phase_changed(phase)

const PHASES = [
	"analysis",
	"proposal",
	"experiment",
	"mutation",
	"evaluation",
	"accepted",
	"rejected",
	"experience"
]

var cycle_id: String = ""
var phase: String = "analysis"
var baseline_id: String = ""
var candidates: Array = []

func start(new_cycle_id: String, baseline: String) -> void:
	cycle_id = new_cycle_id
	baseline_id = baseline
	phase = "analysis"
	candidates.clear()
	emit_signal("analysis")

func add_candidate(candidate_id: String, description: String) -> void:
	candidates.append({
		"id": candidate_id,
		"description": description,
		"status": "created"
	})

func move_to(next_phase: String) -> bool:
	if next_phase not in PHASES:
		return false
	phase = next_phase
	emit_signal(phase)
	return true
