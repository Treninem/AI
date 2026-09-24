class_name CoreImprovementPipeline
extends Node

signal core_candidate_started(goal: String, target: String)
signal core_candidate_verified(result: Dictionary)
signal core_candidate_rejected(result: Dictionary)

const CANDIDATE_ROOT := "user://core_candidates"
const STATE_PATH := "user://core_candidates/state.json"
const MAX_SOURCE_BYTES := 1024 * 1024
const MAX_HISTORY := 30
const MIN_REVIEW_IMPROVEMENT := 1.0
const MIN_TOURNAMENT_CANDIDATES := 3
const MAX_TOURNAMENT_CANDIDATES := 10
const DEFAULT_TOURNAMENT_CANDIDATES := 5
const PROPOSAL_ATTEMPT_MULTIPLIER := 3
const CORE_TARGETS := [
	"scripts/cognition_layer.gd",
	"scripts/agent_core.gd",
	"scripts/memory_store.gd",
	"agent/goals.gd"
]
const NEVER_TOUCH_PREFIXES := [
	"update/", "api/", "addons/", "core_runtime/", "models/", ".github/",
	"scripts/windows_trusted_project_bridge.gd", "scripts/runtime_extension_manager.gd",
	"scripts/core_improvement_pipeline.gd"
]

@export var autonomous_core_candidates := true
@export var auto_apply_dev_checkout := false
@export_range(3, 10, 1) var tournament_candidate_count := DEFAULT_TOURNAMENT_CANDIDATES
@export_range(3600.0, 604800.0, 60.0) var candidate_cooldown_seconds := 21600.0

var ai: AIClient
var tools: ToolRegistry
var coordinator: AuroraAutonomousCoordinator
var benchmark := CoreCandidateBenchmark.new()
var _running := false
var _last_candidate_unix := 0.0
var _history: Array = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CANDIDATE_ROOT))
	_load_state()
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	for _i in range(180):
		_bind_existing()
		if ai != null and tools != null:
			break
		await get_tree().process_frame
	_bind_existing()
	_register_tools()
	if coordinator != null and not coordinator.autonomous_cycle_completed.is_connected(_on_autonomous_cycle_completed):
		coordinator.autonomous_cycle_completed.connect(_on_autonomous_cycle_completed)

func _bind_existing() -> void:
	var main := get_parent()
	if main == null:
		return
	var value: Variant = main.get("ai")
	if value is AIClient:
		ai = value
	value = main.get("tools")
	if value is ToolRegistry:
		tools = value
	var node := main.get_node_or_null("AutonomousCoordinator")
	if node is AuroraAutonomousCoordinator:
		coordinator = node

func _register_tools() -> void:
	if tools == null:
		return
	if not tools.tools.has("aurora_core_candidate"):
		tools.register_tool(
			"aurora_core_candidate",
			"Создать турнир локальных мутаций, сравнить их с текущим ядром и безопасно подготовить единственного доказанного победителя.",
			{"goal":"string", "target":"string"},
			Callable(self, "_tool_candidate")
		)
	if not tools.tools.has("aurora_core_candidate_status"):
		tools.register_tool(
			"aurora_core_candidate_status",
			"Показать историю проверенных турниров улучшения ядра AuroraFox.",
			{},
			Callable(self, "_tool_status")
		)

func _tool_candidate(args: Dictionary) -> Dictionary:
	return await run_candidate(str(args.get("goal", "")).strip_edges(), str(args.get("target", "")).strip_edges())

func _tool_status(_args: Dictionary) -> Dictionary:
	return status()

func _on_autonomous_cycle_completed(report: Dictionary) -> void:
	if not autonomous_core_candidates or _running or OS.get_name() != "Windows":
		return
	if not bool(report.get("ok", false)):
		return
	if Time.get_unix_time_from_system() - _last_candidate_unix < candidate_cooldown_seconds:
		return
	if _signed_update_busy():
		return
	var goal := str(report.get("goal", "")).strip_edges()
	if goal.is_empty():
		return
	call_deferred("_run_automatic_candidate", goal)

func _run_automatic_candidate(goal: String) -> void:
	await run_candidate(goal)

func run_candidate(goal: String, requested_target := "") -> Dictionary:
	if _running:
		return {"ok": false, "error": "core candidate pipeline is already running"}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "core source verification currently runs on Windows", "platform": OS.get_name()}
	_bind_existing()
	if ai == null or tools == null:
		return {"ok": false, "error": "AuroraFox core candidate dependencies are not ready"}
	if not await ai.is_available():
		return {"ok": false, "error": "local AuroraFox Core inference is not ready"}
	if _signed_update_busy():
		return {"ok": false, "error": "signed product update has priority", "deferred": true}
	var clean_goal := goal.strip_edges()
	if clean_goal.is_empty():
		clean_goal = "Повысить устойчивость, качество рассуждений и полезность AuroraFox без регрессий"
	var target := _select_target(clean_goal, requested_target)
	if target.is_empty():
		return {"ok": false, "error": "target is outside the autonomous core allowlist"}
	var source_result := _read_res_source(target)
	if not bool(source_result.get("ok", false)):
		return source_result
	var original := str(source_result.get("content", ""))
	var baseline_sha := _sha256_text(original)
	var desired_count := clampi(tournament_candidate_count, MIN_TOURNAMENT_CANDIDATES, MAX_TOURNAMENT_CANDIDATES)
	_running = true
	core_candidate_started.emit(clean_goal, target)

	# Every mutation is generated from the exact same incumbent source. Nothing is
	# applied to the checkout while the tournament is running.
	var participants: Array = []
	var reviewed_candidates: Array = []
	var candidate_payloads := {}
	var seen_sha := {baseline_sha: true}
	var max_attempts := desired_count * PROPOSAL_ATTEMPT_MULTIPLIER
	var attempt := 0
	while participants.size() < desired_count and attempt < max_attempts:
		var proposal_result := await _propose(clean_goal, target, original, attempt, desired_count)
		attempt += 1
		if not bool(proposal_result.get("ok", false)):
			continue
		var proposal: Dictionary = proposal_result.get("proposal", {})
		var validation := _validate_candidate(target, original, proposal)
		if not bool(validation.get("ok", false)):
			continue
		var candidate_content := str(proposal.get("content", ""))
		var candidate_sha := _sha256_text(candidate_content)
		if candidate_sha.is_empty() or seen_sha.has(candidate_sha):
			continue
		seen_sha[candidate_sha] = true
		var participant_index := participants.size()
		var participant := {
			"kind": "mutation",
			"index": participant_index,
			"candidate_sha256": candidate_sha,
			"hard_gates_passed": false,
			"scored": false,
			"eligible": false,
			"stage": "verification"
		}
		var verification := await _verify_in_workspace(clean_goal, target, candidate_content)
		verification["source_contract"] = validation.get("source_contract", {})
		if not bool(verification.get("ok", false)):
			participant["stage"] = str(verification.get("stage", "verification"))
			participant["error"] = str(verification.get("error", "candidate failed hard gates"))
			participant["verification"] = _compact(verification)
			participants.append(participant)
			continue
		participant["hard_gates_passed"] = true
		participant["stage"] = "comparative_review"
		var review := await _comparative_review(clean_goal, target, original, candidate_content, verification, proposal)
		participant["review"] = _compact(review)
		participant["scored"] = true
		participant["eligible"] = bool(review.get("ok", false)) and bool(review.get("improved", false))
		participant["stage"] = "eligible" if bool(participant["eligible"]) else "review_rejected"
		participants.append(participant)
		reviewed_candidates.append(participant.duplicate(true))
		candidate_payloads[candidate_sha] = {
			"proposal": proposal,
			"validation": validation,
			"verification": verification,
			"content": candidate_content
		}

	if participants.size() < MIN_TOURNAMENT_CANDIDATES:
		return _finish_rejected({
			"stage": "tournament_generation",
			"error": "fewer than three distinct isolated mutations were produced",
			"goal": clean_goal,
			"target": target,
			"baseline_sha256": baseline_sha,
			"requested_candidates": desired_count,
			"created_candidates": participants.size(),
			"attempts": attempt,
			"participants": _compact(participants),
			"promotion": "none"
		})

	var selection := _select_tournament_winner(reviewed_candidates)
	if not bool(selection.get("ok", false)):
		return _finish_rejected({
			"stage": "tournament_no_winner",
			"error": str(selection.get("error", "no mutation proved better than the incumbent")),
			"goal": clean_goal,
			"target": target,
			"baseline_sha256": baseline_sha,
			"requested_candidates": desired_count,
			"created_candidates": participants.size(),
			"attempts": attempt,
			"incumbent": selection.get("incumbent", {}),
			"participants": _compact(participants),
			"promotion": "none"
		})

	var winner: Dictionary = selection.get("winner", {})
	var winner_sha := str(winner.get("candidate_sha256", ""))
	var payload: Dictionary = candidate_payloads.get(winner_sha, {})
	if payload.is_empty():
		return _finish_rejected({"stage":"tournament_integrity", "error":"selected mutation payload is unavailable", "promotion":"none"})
	var winner_content := str(payload.get("content", ""))
	if _sha256_text(winner_content) != winner_sha:
		return _finish_rejected({"stage":"tournament_integrity", "error":"selected mutation content hash changed", "promotion":"none"})

	# Only the tournament winner is allowed into a second clean workspace. This
	# independently re-imports the unchanged incumbent, re-runs baseline gates,
	# writes the winner and re-runs the same target-specific tests/benchmarks.
	var independent_verification := await _verify_in_workspace(clean_goal, target, winner_content)
	independent_verification["source_contract"] = payload.get("validation", {}).get("source_contract", {})
	if not bool(independent_verification.get("ok", false)):
		return _finish_rejected({
			"stage": "independent_verification",
			"error": "tournament winner failed the second clean verification pass",
			"goal": clean_goal,
			"target": target,
			"candidate_sha256": winner_sha,
			"details": _compact(independent_verification),
			"promotion": "none"
		})

	var first_verification: Dictionary = payload.get("verification", {})
	var first_review: Dictionary = winner.get("review", {})
	var verification := first_verification.duplicate(true)
	verification["source_contract"] = payload.get("validation", {}).get("source_contract", {})
	verification["comparative_review"] = first_review
	verification["independent_verification"] = _compact(independent_verification)
	verification["tournament"] = {
		"requested_candidates": desired_count,
		"created_candidates": participants.size(),
		"attempts": attempt,
		"incumbent": selection.get("incumbent", {}),
		"winner": winner,
		"participants": _compact(participants),
		"second_clean_pass": true
	}
	var proposal: Dictionary = payload.get("proposal", {})
	var stored := _store_candidate(clean_goal, target, original, proposal, verification)
	if not bool(stored.get("ok", false)):
		return _finish_rejected(stored)

	var result := {
		"ok": true,
		"goal": clean_goal,
		"target": target,
		"candidate_id": stored.get("candidate_id", ""),
		"candidate_path": stored.get("candidate_path", ""),
		"manifest_path": stored.get("manifest_path", ""),
		"base_sha256": baseline_sha,
		"candidate_sha256": winner_sha,
		"reason": str(proposal.get("reason", "")).substr(0, 2000),
		"verified": true,
		"benchmark_verified": true,
		"review_improved": true,
		"tournament_verified": true,
		"independent_verification_passed": true,
		"tournament": verification.get("tournament", {}),
		"verification": _compact(verification),
		"promotion": "signed_update_candidate",
		"applied_to_dev_checkout": false
	}

	# Automatic source rewriting is OFF by default. An editor checkout may opt in,
	# but only after the bounded tournament and second clean verification passed.
	# Packaged/signed builds never rewrite their runtime in place.
	if OS.has_feature("editor") and auto_apply_dev_checkout:
		var applied = await tools.call_tool("project_apply_file", {
			"project_path": "res://",
			"relative_path": target,
			"sandbox_path": independent_verification.get("sandbox_path", "")
		})
		result["apply"] = _compact(applied)
		result["applied_to_dev_checkout"] = bool(applied is Dictionary and applied.get("ok", false))
		if bool(result.get("applied_to_dev_checkout", false)):
			result["promotion"] = "verified_dev_checkout_candidate_then_signed_update"
			if tools.tools.has("index_project"):
				result["reindex"] = _compact(await tools.call_tool("index_project", {"path":"res://", "max_files":30000, "force":false}))

	_last_candidate_unix = Time.get_unix_time_from_system()
	_history.append(_history_entry(result))
	_trim_history()
	_save_state()
	_running = false
	core_candidate_verified.emit(result)
	return result

func _propose(goal: String, target: String, original: String, mutation_index: int, mutation_count: int) -> Dictionary:
	var prompt := """
Ты создаёшь ОДНУ из %d независимых мутаций разрешённого файла собственного ядра AuroraFox. Все мутации строятся от ОДНОГО неизменного baseline и позже будут проверены в изолированных workspace. Ты — собственный локальный AuroraFox Core; внешние AI/API не являются источником решения.
Номер мутации: %d
Цель: %s
Файл: %s

Верни ТОЛЬКО строгий JSON:
{"path":"%s","content":"ПОЛНЫЙ новый текст файла","reason":"какое измеримое улучшение внесено","verification":"какие регрессии особенно важно проверить"}

Правила:
- придумай самостоятельный вариант, а не косметическую перестановку;
- сохраняй назначение файла и совместимость публичных методов/сигналов;
- не удаляй существующие публичные функции ради упрощения;
- не трогай updater, подписи, sandbox, разрешения, секреты, project.godot или другие файлы;
- не добавляй новые process/network primitives, обходы ограничений, скрытые каналы или ослабление проверок;
- не используй TODO/FIXME/placeholder;
- изменение должно давать конкретное улучшение устойчивости, качества, памяти, планирования, отказоустойчивости или производительности;
- scoring разрешён только после source/safety/test/benchmark hard-gates;
- не утверждай, что тесты прошли: их запустит AuroraFox независимо.

Неизменный baseline:
--- BEGIN CURRENT SOURCE ---
%s
--- END CURRENT SOURCE ---
""" % [mutation_count, mutation_index + 1, goal, target, target, original]
	var temperature := clampf(0.08 + float(mutation_index % MAX_TOURNAMENT_CANDIDATES) * 0.025, 0.08, 0.30)
	var response := await ai.chat([{"role":"user", "content":prompt}], temperature)
	if not bool(response.get("ok", false)):
		return {"ok": false, "stage": "proposal", "error": str(response.get("error", "local proposal generation failed"))}
	var text := str(response.get("content", "")).replace("```json", "").replace("```", "").strip_edges()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "stage": "proposal", "error": "core improvement proposal is not valid JSON"}
	return {"ok": true, "proposal": parsed}

func _validate_candidate(target: String, original: String, proposal: Dictionary) -> Dictionary:
	if str(proposal.get("path", "")) != target:
		return {"ok": false, "stage": "validation", "error": "candidate attempted to change a different path"}
	var content := str(proposal.get("content", ""))
	if content.strip_edges().is_empty():
		return {"ok": false, "stage": "validation", "error": "candidate source is empty"}
	if content.to_utf8_buffer().size() > MAX_SOURCE_BYTES:
		return {"ok": false, "stage": "validation", "error": "candidate source exceeds size limit"}
	if content == original:
		return {"ok": false, "stage": "validation", "error": "candidate does not change the source"}
	var lower := content.to_lower()
	for marker in ["todo", "fixme", "implement later", "placeholder"]:
		if lower.contains(marker):
			return {"ok": false, "stage": "validation", "error": "candidate contains unfinished marker", "marker": marker}
	var old_class := _line_with_prefix(original, "class_name ")
	var new_class := _line_with_prefix(content, "class_name ")
	if not old_class.is_empty() and old_class != new_class:
		return {"ok": false, "stage": "validation", "error": "candidate changed class_name contract", "expected": old_class, "actual": new_class}
	var old_extends := _line_with_prefix(original, "extends ")
	var new_extends := _line_with_prefix(content, "extends ")
	if not old_extends.is_empty() and old_extends != new_extends:
		return {"ok": false, "stage": "validation", "error": "candidate changed base class contract", "expected": old_extends, "actual": new_extends}
	var contract := benchmark.source_contract(original, content, target)
	if not bool(contract.get("ok", false)):
		return {
			"ok": false,
			"stage": "source_contract",
			"error": "candidate regresses public contracts, adds risky primitives or grows beyond the bounded source budget",
			"source_contract": contract
		}
	return {"ok": true, "source_contract": contract}

func _verify_in_workspace(goal: String, target: String, content: String) -> Dictionary:
	for required in ["workspace_create", "workspace_import_project", "workspace_write", "workspace_read", "workspace_test", "workspace_exec", "project_compare_file"]:
		if not tools.tools.has(required):
			return {"ok": false, "stage": "workspace", "error": "required verification tool missing", "tool": required}
	var created = await tools.call_tool("workspace_create", {"task":"AuroraFox core candidate benchmark: " + goal, "runtime":"local"})
	if not _ok(created): return _failed("workspace_create", created)
	var imported = await tools.call_tool("workspace_import_project", {"project_path":"res://", "target":"project", "max_files":30000, "max_bytes":2147483648})
	if not _ok(imported): return _failed("workspace_import_project", imported)

	var benchmark_commands := benchmark.commands_for_target(target)
	if benchmark_commands.is_empty():
		return {"ok": false, "stage": "baseline_benchmark", "error": "no deterministic benchmark suite is registered for target", "target": target}
	var baseline_runs := await _run_benchmark_commands(benchmark_commands)
	var baseline_summary := benchmark.summarize_runs(baseline_runs)
	if not bool(baseline_summary.get("ok", false)):
		return {"ok": false, "stage": "baseline_benchmark", "error": "current source baseline is not healthy enough to judge an autonomous replacement", "baseline": _compact(baseline_summary)}

	var sandbox_path := "project/" + target
	var written = await tools.call_tool("workspace_write", {"path":sandbox_path, "content":content})
	if not _ok(written): return _failed("workspace_write", written)
	var reread = await tools.call_tool("workspace_read", {"path":sandbox_path, "area":"work"})
	if not _ok(reread): return _failed("workspace_read", reread)
	if str(reread.get("content", "")) != content:
		return {"ok": false, "stage": "candidate_integrity", "error": "workspace candidate differs from proposed source"}

	var tested = await tools.call_tool("workspace_test", {"language":"gdscript", "cwd":"project"})
	if not _ok(tested): return _failed("workspace_test", tested)
	var candidate_runs := await _run_benchmark_commands(benchmark_commands)
	var candidate_summary := benchmark.summarize_runs(candidate_runs)
	var runtime_comparison := benchmark.compare_runtime(baseline_summary, candidate_summary)
	if not bool(runtime_comparison.get("ok", false)):
		return {"ok": false, "stage": "candidate_benchmark", "error": "candidate failed target-specific no-regression benchmark", "benchmark": _compact(runtime_comparison)}

	var compared = await tools.call_tool("project_compare_file", {"project_path":"res://", "relative_path":target, "sandbox_path":sandbox_path})
	if not _ok(compared): return _failed("project_compare_file", compared)
	if not bool(compared.get("changed", false)):
		return {"ok": false, "stage": "project_compare_file", "error": "verified candidate is identical to current source"}
	return {
		"ok": true,
		"verified": true,
		"workspace": _compact(created.get("workspace", {})),
		"import": _compact(imported),
		"test": _compact(tested),
		"benchmark": _compact(runtime_comparison),
		"compare": _compact(compared),
		"sandbox_path": sandbox_path,
		"verification_mode": "clean_baseline_then_candidate_godot_4_7_1_target_benchmarks_plus_hash_compare"
	}

func _run_benchmark_commands(commands: Array) -> Array:
	var results: Array = []
	for command in commands:
		if not command is Array:
			results.append({"ok": false, "error": "invalid benchmark command", "command": command})
			continue
		var result = await tools.call_tool("workspace_exec", {
			"command": command,
			"cwd": "project",
			"timeout": 150,
			"mode": "auto"
		})
		if result is Dictionary:
			var row: Dictionary = result.duplicate(true)
			row["command"] = command
			results.append(row)
		else:
			results.append({"ok": false, "error": "benchmark command returned invalid result", "command": command})
	return results

func _comparative_review(goal: String, target: String, original: String, candidate: String, verification: Dictionary, proposal: Dictionary) -> Dictionary:
	var evidence := {
		"source_contract": verification.get("source_contract", {}),
		"benchmark": verification.get("benchmark", {}),
		"requested_reason": str(proposal.get("reason", "")).substr(0, 2000),
		"requested_verification": str(proposal.get("verification", "")).substr(0, 1500)
	}
	var prompt := """
Ты локальный независимый reviewer AuroraFox. Сравни неизменный incumbent и уже прошедшую source/safety/test/benchmark hard-gates мутацию.
Цель: %s
Файл: %s

Верни ТОЛЬКО JSON:
{"baseline_score":0-100,"candidate_score":0-100,"improved":true|false,"reasons":["..."],"risks":["..."]}

Оценивай только доказанное качество относительно цели: корректность, устойчивость, понятность, производительность, отказоустойчивость, сохранение контрактов. Не давай бонус за размер или новизну сами по себе. Если улучшение не доказано, improved=false. Scoring идёт только после hard-gates и не может отменить их провал.

Проверочная информация:
%s

--- INCUMBENT ---
%s
--- MUTATION ---
%s
""" % [goal, target, JSON.stringify(_compact(evidence)), original.substr(0, 120000), candidate.substr(0, 120000)]
	var response := await ai.chat([{"role":"user", "content":prompt}], 0.0)
	if not bool(response.get("ok", false)):
		return {"ok": false, "stage": "comparative_review", "error": str(response.get("error", "comparative review failed"))}
	var text := str(response.get("content", "")).replace("```json", "").replace("```", "").strip_edges()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "stage": "comparative_review", "error": "review did not return valid JSON"}
	var baseline_score := clampf(float(parsed.get("baseline_score", 0.0)), 0.0, 100.0)
	var candidate_score := clampf(float(parsed.get("candidate_score", 0.0)), 0.0, 100.0)
	var delta := candidate_score - baseline_score
	var improved := bool(parsed.get("improved", false)) and delta >= MIN_REVIEW_IMPROVEMENT
	return {
		"ok": improved,
		"stage": "comparative_review",
		"improved": improved,
		"baseline_score": baseline_score,
		"candidate_score": candidate_score,
		"delta": delta,
		"minimum_delta": MIN_REVIEW_IMPROVEMENT,
		"reasons": parsed.get("reasons", []),
		"risks": parsed.get("risks", []),
		"error": "candidate was not demonstrably better than baseline" if not improved else ""
	}

func _select_tournament_winner(reviewed_candidates: Array) -> Dictionary:
	var incumbent_score := 0.0
	var baseline_observations := 0
	for row in reviewed_candidates:
		if not row is Dictionary:
			continue
		var review = row.get("review", {})
		if not review is Dictionary or not review.has("baseline_score"):
			continue
		incumbent_score = maxf(incumbent_score, float(review.get("baseline_score", 0.0)))
		baseline_observations += 1
	var incumbent := {
		"kind": "incumbent",
		"score": incumbent_score,
		"baseline_observations": baseline_observations,
		"eligible": true
	}
	if baseline_observations == 0:
		return {"ok": false, "error": "no mutation reached post-hard-gate scoring", "incumbent": incumbent}
	var winner: Dictionary = {}
	var best_score := -1.0
	for row in reviewed_candidates:
		if not row is Dictionary or not bool(row.get("hard_gates_passed", false)) or not bool(row.get("eligible", false)):
			continue
		var review = row.get("review", {})
		if not review is Dictionary:
			continue
		var score := float(review.get("candidate_score", 0.0))
		if score < incumbent_score + MIN_REVIEW_IMPROVEMENT:
			continue
		if winner.is_empty() or score > best_score or (is_equal_approx(score, best_score) and str(row.get("candidate_sha256", "")) < str(winner.get("candidate_sha256", ""))):
			winner = row.duplicate(true)
			best_score = score
	if winner.is_empty():
		return {"ok": false, "error": "all mutations were worse, tied, inconclusive or failed hard gates", "incumbent": incumbent}
	winner["tournament_score"] = best_score
	winner["incumbent_score"] = incumbent_score
	return {"ok": true, "winner": winner, "incumbent": incumbent}

func _store_candidate(goal: String, target: String, original: String, proposal: Dictionary, verification: Dictionary) -> Dictionary:
	var content := str(proposal.get("content", ""))
	var candidate_sha := _sha256_text(content)
	var candidate_id := "%d_%s" % [int(Time.get_unix_time_from_system()), candidate_sha.substr(0, 12)]
	var root := CANDIDATE_ROOT.path_join(candidate_id)
	var candidate_path := root.path_join(target)
	var manifest_path := root.path_join("candidate.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(candidate_path.get_base_dir()))
	var candidate_file := FileAccess.open(candidate_path, FileAccess.WRITE)
	if candidate_file == null:
		return {"ok": false, "stage": "store", "error": "cannot store verified core candidate"}
	candidate_file.store_string(content)
	candidate_file.close()
	var manifest := {
		"candidate_id": candidate_id,
		"goal": goal,
		"target": target,
		"base_sha256": _sha256_text(original),
		"candidate_sha256": candidate_sha,
		"reason": str(proposal.get("reason", "")).substr(0, 4000),
		"requested_verification": str(proposal.get("verification", "")).substr(0, 3000),
		"verified": true,
		"benchmark_verified": bool(verification.get("benchmark", {}).get("ok", false)) if verification.get("benchmark", {}) is Dictionary else false,
		"tournament_verified": bool(verification.get("tournament", {}).get("second_clean_pass", false)) if verification.get("tournament", {}) is Dictionary else false,
		"comparative_review": verification.get("comparative_review", {}),
		"independent_verification": verification.get("independent_verification", {}),
		"tournament": verification.get("tournament", {}),
		"verification": _compact(verification),
		"created_at": Time.get_datetime_string_from_system(true),
		"promotion": "signed_update_candidate"
	}
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate_path))
		return {"ok": false, "stage": "store", "error": "cannot store core candidate manifest"}
	manifest_file.store_string(JSON.stringify(manifest, "  "))
	manifest_file.close()
	if _sha256_file(candidate_path) != candidate_sha:
		return {"ok": false, "stage": "store", "error": "stored candidate failed SHA-256 integrity check"}
	return {"ok": true, "candidate_id":candidate_id, "candidate_path":candidate_path, "manifest_path":manifest_path}

func _select_target(goal: String, requested: String) -> String:
	var request := requested.trim_prefix("res://").replace("\\", "/")
	if not request.is_empty():
		return request if _target_allowed(request) else ""
	var q := goal.to_lower()
	if _contains_any(q, ["памят", "memory", "retriev", "знан"]): return "scripts/memory_store.gd"
	if _contains_any(q, ["план", "reason", "рассуж", "cognit", "провер"]): return "scripts/cognition_layer.gd"
	if _contains_any(q, ["цель", "goal", "приоритет"]): return "agent/goals.gd"
	return "scripts/agent_core.gd"

func _target_allowed(path: String) -> bool:
	if path not in CORE_TARGETS:
		return false
	for prefix in NEVER_TOUCH_PREFIXES:
		if path == prefix or path.begins_with(prefix):
			return false
	return true

func _read_res_source(target: String) -> Dictionary:
	if not _target_allowed(target):
		return {"ok": false, "error": "target is not allowed"}
	var path := "res://" + target
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot read core source", "path": target}
	if file.get_length() > MAX_SOURCE_BYTES:
		file.close()
		return {"ok": false, "error": "core source exceeds size limit", "path": target}
	var content := file.get_as_text()
	file.close()
	return {"ok": true, "content": content}

func _signed_update_busy() -> bool:
	var update_node := get_node_or_null("/root/AuroraUpdate")
	if update_node == null:
		return false
	if bool(update_node.get("checking")) or bool(update_node.get("downloading")):
		return true
	return not str(update_node.get("downloaded_path")).is_empty()

func status() -> Dictionary:
	return {
		"running": _running,
		"autonomous_core_candidates": autonomous_core_candidates,
		"auto_apply_dev_checkout": auto_apply_dev_checkout,
		"tournament_candidate_count": clampi(tournament_candidate_count, MIN_TOURNAMENT_CANDIDATES, MAX_TOURNAMENT_CANDIDATES),
		"tournament_candidate_min": MIN_TOURNAMENT_CANDIDATES,
		"tournament_candidate_max": MAX_TOURNAMENT_CANDIDATES,
		"candidate_cooldown_seconds": candidate_cooldown_seconds,
		"last_candidate_unix": _last_candidate_unix,
		"minimum_review_improvement": MIN_REVIEW_IMPROVEMENT,
		"targets": CORE_TARGETS.duplicate(),
		"history": _history.duplicate(true)
	}

func _finish_rejected(result: Dictionary) -> Dictionary:
	_running = false
	var row := result.duplicate(true)
	row["ok"] = false
	row["rejected_at"] = Time.get_datetime_string_from_system(true)
	_history.append(_history_entry(row))
	_trim_history()
	_save_state()
	core_candidate_rejected.emit(row)
	return row

func _history_entry(result: Dictionary) -> Dictionary:
	return {
		"ok": bool(result.get("ok", false)),
		"goal": str(result.get("goal", "")).substr(0, 1000),
		"target": str(result.get("target", "")),
		"candidate_id": str(result.get("candidate_id", "")),
		"candidate_sha256": str(result.get("candidate_sha256", "")),
		"verified": bool(result.get("verified", false)),
		"benchmark_verified": bool(result.get("benchmark_verified", false)),
		"review_improved": bool(result.get("review_improved", false)),
		"tournament_verified": bool(result.get("tournament_verified", false)),
		"independent_verification_passed": bool(result.get("independent_verification_passed", false)),
		"promotion": str(result.get("promotion", "")),
		"applied_to_dev_checkout": bool(result.get("applied_to_dev_checkout", false)),
		"stage": str(result.get("stage", "")),
		"error": str(result.get("error", "")).substr(0, 1000),
		"time": Time.get_datetime_string_from_system(true)
	}

func _trim_history() -> void:
	if _history.size() > MAX_HISTORY:
		_history = _history.slice(_history.size() - MAX_HISTORY, _history.size())

func _load_state() -> void:
	var file := FileAccess.open(STATE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	_last_candidate_unix = float(parsed.get("last_candidate_unix", 0.0))
	var rows = parsed.get("history", [])
	if rows is Array:
		_history = rows

func _save_state() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CANDIDATE_ROOT))
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"last_candidate_unix": _last_candidate_unix,
		"history": _history,
		"updated_at": Time.get_datetime_string_from_system(true)
	}, "  "))
	file.close()

func _line_with_prefix(text: String, prefix: String) -> String:
	for line in text.split("\n"):
		var clean := str(line).strip_edges()
		if clean.begins_with(prefix):
			return clean
	return ""

func _contains_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.contains(str(needle)):
			return true
	return false

func _ok(value: Variant) -> bool:
	return value is Dictionary and bool(value.get("ok", false))

func _failed(stage: String, value: Variant) -> Dictionary:
	return {"ok": false, "stage": stage, "error": str(value.get("error", "verification failed")) if value is Dictionary else "verification failed", "details": _compact(value)}

func _compact(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value.keys():
			var k := str(key)
			if k in ["content", "source", "raw", "stdout", "stderr", "output"]:
				continue
			out[k] = _compact(value[key])
		return out
	if value is Array:
		var out_array: Array = []
		for item in value.slice(0, mini(value.size(), 24)):
			out_array.append(_compact(item))
		return out_array
	return value

func _sha256_text(text: String) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if ctx.update(text.to_utf8_buffer()) != OK:
		return ""
	return ctx.finish().hex_encode().to_lower()

func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return ""
	while file.get_position() < file.get_length():
		ctx.update(file.get_buffer(mini(1024 * 1024, file.get_length() - file.get_position())))
	file.close()
	return ctx.finish().hex_encode().to_lower()