class_name SelfImprover
extends Node

signal improvement_stage(stage: String, details: Dictionary)
signal improvement_verified(result: Dictionary)
signal improvement_rejected(result: Dictionary)
signal mutation_population_started(goal: String, requested: int)
signal mutation_candidate_completed(candidate: Dictionary)
signal mutation_tournament_completed(result: Dictionary)

const GENERATED_ROOT := "res://generated/"
const RUNTIME_GENERATED_ROOT := "user://generated/"
const MAX_GENERATED_BYTES := 512 * 1024
const MAX_PROJECT_FILES := 30000
const MAX_PROJECT_BYTES := 2 * 1024 * 1024 * 1024
const HOT_TOOL_PREFIX := "aurora_ext_"
const MIN_MUTATIONS := 3
const MAX_MUTATIONS := 10
const MAX_GENERATION_ATTEMPTS := 24
const MUTATION_STRATEGIES := [
	"robustness_and_edge_cases",
	"performance_and_low_allocations",
	"precision_and_determinism",
	"simplicity_and_maintainability",
	"context_quality_and_reasoning",
	"observability_and_diagnostics",
	"composability_and_reuse",
	"failure_resistance",
	"input_validation",
	"low_memory_behavior"
]
const HOT_BLOCKED_MARKERS := [
	"OS.", "FileAccess", "DirAccess", "ProjectSettings", "Engine.", "ClassDB",
	"DisplayServer", "RenderingServer", "AudioServer", "Input.", "InputMap",
	"HTTPRequest", "HTTPClient", "TCPServer", "StreamPeerTCP", "UDPServer", "PacketPeerUDP",
	"WebSocket", "IP.", "JavaClassWrapper", "JavaScriptBridge", "ResourceLoader",
	"ResourceSaver", "GDScript.new", "source_code", "Expression.new", "preload(",
	"instance_from_id", "@tool", "@onready", "while true"
]

var tools: ToolRegistry
var ai: AIClient

func setup(tool_registry: ToolRegistry, ai_client: AIClient) -> void:
	tools = tool_registry
	ai = ai_client

func propose_improvement(goal: String, mutation_index := 0, strategy := "balanced", previous_signatures: Array = []) -> Dictionary:
	if ai == null:
		return {"ok": false, "error": "AI client is not configured"}
	var mutation_tag := "m%02d" % maxi(0, mutation_index + 1)
	var diversity := ""
	if not previous_signatures.is_empty():
		diversity = "\nУже созданные варианты (НЕ ПОВТОРЯЙ их путь/структуру/идею):\n- " + "\n- ".join(previous_signatures.slice(0, mini(previous_signatures.size(), 12)))
	var prompt := """
Ты создаёшь ОДНУ независимую мутацию AuroraFox — Godot 4.7.1 проекта автономного локального AI.
Цель эволюции: %s
Номер мутации: %s
Стратегия этой мутации: %s

Эта мутация участвует в автоматическом турнире против других независимых копий.
Она должна реально отличаться архитектурной идеей/алгоритмом, а не только именами.
Используй %s в имени файла и имени хотя бы одного aurora_ext_ инструмента, чтобы исключить коллизии.%s

Верни ТОЛЬКО строгий JSON:
{"path":"res://generated/<filename>.gd","content":"полный готовый GDScript","reason":"что улучшает и чем эта мутация отличается","verification":"что должно подтвердить корректность"}

ОБЯЗАТЕЛЬНЫЙ КОНТРАКТ HOT-EXTENSION:
- файл начинается с `extends RefCounted`;
- реализуй `func aurora_extension_manifest() -> Dictionary`;
- manifest должен содержать `name`, `description`, `tools`;
- каждый элемент tools: {"name":"aurora_ext_<unique>","description":"...","schema":{...},"method":"_method_name"};
- каждый method принимает один Dictionary args и возвращает результат; асинхронный метод допустим;
- имена инструментов только с префиксом aurora_ext_ и не должны совпадать друг с другом;
- расширение не получает ToolRegistry и не регистрирует инструменты самостоятельно;
- расширение НЕ является Node, не входит в scene tree и не должно пытаться получать get_tree/get_parent;
- запрещён прямой доступ к OS, файлам, настройкам движка, сети, динамической загрузке ресурсов/скриптов и системным singleton API;
- горячее расширение должно быть вычислительным/логическим. Новые привилегии, файлы, сеть или системные действия делаются только через полноценное обновление AuroraFox.

ОБЩИЕ ПРАВИЛА:
- только новый .gd внутри логического res://generated/;
- никакого TODO/FIXME/placeholder/stub/pass/implement later;
- код должен быть самодостаточным и совместимым с Godot 4.7.1;
- не меняй project.godot, autoload, секреты, обновлятор и существующее ядро;
- не удаляй файлы;
- не утверждай, что код проверен: AuroraFox сама выполнит отдельный sandbox + Godot 4.7.1 тест каждой мутации.
""" % [goal.strip_edges(), mutation_tag, strategy, mutation_tag, diversity]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.45)
	if not result.get("ok", false): return result
	var text := str(result.get("content", "")).replace("```json", "").replace("```", "").strip_edges()
	var proposal = JSON.parse_string(text)
	if not proposal is Dictionary:
		return {"ok": false, "error": "Invalid improvement proposal JSON", "mutation": mutation_tag}
	var validation := _validate_proposal(proposal)
	if not validation.get("ok", false):
		validation["mutation"] = mutation_tag
		return validation
	proposal["mutation_index"] = mutation_index
	proposal["mutation_tag"] = mutation_tag
	proposal["strategy"] = strategy
	return {"ok": true, "proposal": proposal}

func run_mutation_tournament(goal: String, requested_count := 5) -> Dictionary:
	if ai == null or tools == null:
		return {"ok": false, "error": "SelfImprover is not fully configured", "stage": "setup"}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Automatic mutation tournament verification is currently enabled on Windows only", "stage": "platform"}

	var requested := clampi(requested_count, MIN_MUTATIONS, MAX_MUTATIONS)
	mutation_population_started.emit(goal, requested)
	improvement_stage.emit("mutation_population", {"goal": goal, "requested": requested, "min": MIN_MUTATIONS, "max": MAX_MUTATIONS})

	var population: Array = []
	var verified: Array = []
	var signatures: Array = []
	var seen_hashes: Dictionary = {}
	var seen_paths: Dictionary = {}
	var generation_errors: Array = []
	var attempt := 0

	# Build at least the requested population. If too few candidates survive
	# verification, keep generating distinct mutations up to the hard maximum 10.
	while population.size() < requested and attempt < MAX_GENERATION_ATTEMPTS:
		var strategy := str(MUTATION_STRATEGIES[attempt % MUTATION_STRATEGIES.size()])
		var proposal_result: Dictionary = await propose_improvement(goal, attempt, strategy, signatures)
		attempt += 1
		if not proposal_result.get("ok", false):
			generation_errors.append(_compact(proposal_result))
			continue
		var proposal: Dictionary = proposal_result.get("proposal", {})
		var content := str(proposal.get("content", ""))
		var sha := _sha256_text(content)
		var path := str(proposal.get("path", ""))
		if sha.is_empty() or seen_hashes.has(sha) or seen_paths.has(path):
			generation_errors.append({"ok": false, "error": "duplicate mutation rejected", "path": path, "sha256": sha})
			continue
		seen_hashes[sha] = true
		seen_paths[path] = true
		signatures.append("%s | %s | %s" % [path, str(proposal.get("reason", "")).substr(0, 220), sha.substr(0, 12)])
		var candidate := await _verify_tournament_candidate(goal, proposal, population.size())
		population.append(candidate)
		if candidate.get("verified", false):
			verified.append(candidate)
		mutation_candidate_completed.emit(_compact(candidate))

	# A tournament should not auto-update from a single lucky survivor. If fewer
	# than three verified mutations survived, create extra distinct copies up to 10.
	while verified.size() < MIN_MUTATIONS and population.size() < MAX_MUTATIONS and attempt < MAX_GENERATION_ATTEMPTS:
		var strategy := str(MUTATION_STRATEGIES[attempt % MUTATION_STRATEGIES.size()])
		var proposal_result: Dictionary = await propose_improvement(goal, attempt, strategy, signatures)
		attempt += 1
		if not proposal_result.get("ok", false):
			generation_errors.append(_compact(proposal_result))
			continue
		var proposal: Dictionary = proposal_result.get("proposal", {})
		var content := str(proposal.get("content", ""))
		var sha := _sha256_text(content)
		var path := str(proposal.get("path", ""))
		if sha.is_empty() or seen_hashes.has(sha) or seen_paths.has(path):
			generation_errors.append({"ok": false, "error": "duplicate mutation rejected", "path": path, "sha256": sha})
			continue
		seen_hashes[sha] = true
		seen_paths[path] = true
		signatures.append("%s | %s | %s" % [path, str(proposal.get("reason", "")).substr(0, 220), sha.substr(0, 12)])
		var candidate := await _verify_tournament_candidate(goal, proposal, population.size())
		population.append(candidate)
		if candidate.get("verified", false):
			verified.append(candidate)
		mutation_candidate_completed.emit(_compact(candidate))

	if population.size() < MIN_MUTATIONS:
		var insufficient := {
			"ok": false,
			"stage": "population",
			"error": "Could not create at least 3 distinct valid mutations",
			"goal": goal,
			"population_size": population.size(),
			"verified_count": verified.size(),
			"generation_attempts": attempt,
			"generation_errors": generation_errors.slice(0, mini(generation_errors.size(), 20)),
			"candidates": _compact_candidates(population)
		}
		improvement_rejected.emit(insufficient)
		mutation_tournament_completed.emit(insufficient)
		return insufficient

	if verified.size() < MIN_MUTATIONS:
		var no_finalists := {
			"ok": false,
			"stage": "competition",
			"error": "Fewer than 3 mutations passed independent Godot tests; automatic update cancelled",
			"goal": goal,
			"population_size": population.size(),
			"verified_count": verified.size(),
			"generation_attempts": attempt,
			"candidates": _compact_candidates(population)
		}
		improvement_rejected.emit(no_finalists)
		mutation_tournament_completed.emit(no_finalists)
		return no_finalists

	improvement_stage.emit("competition", {"goal": goal, "population": population.size(), "verified": verified.size()})
	var judge := await _judge_verified_candidates(goal, verified)
	_apply_judge_scores(verified, judge)
	verified.sort_custom(func(a, b):
		var score_a := float(a.get("score", 0.0))
		var score_b := float(b.get("score", 0.0))
		if not is_equal_approx(score_a, score_b): return score_a > score_b
		return str(a.get("sha256", "")) < str(b.get("sha256", ""))
	)

	var winner: Dictionary = verified[0]
	var winner_proposal: Dictionary = winner.get("proposal", {})
	improvement_stage.emit("winner_final_test", {
		"goal": goal,
		"path": winner_proposal.get("path", ""),
		"score": winner.get("score", 0.0),
		"verified_candidates": verified.size()
	})

	# Re-run the winner from a fresh sandbox before staging. This means the code
	# that wins the competition is tested twice: once as a contestant and once
	# immediately before automatic activation.
	var staged := await apply_generated_module(winner_proposal)
	if not staged.get("ok", false):
		var final_reject := {
			"ok": false,
			"stage": "winner_final_test",
			"error": str(staged.get("error", "Winning mutation failed final verification")),
			"goal": goal,
			"population_size": population.size(),
			"verified_count": verified.size(),
			"winner": _candidate_public(winner),
			"final_verification": _compact(staged),
			"scoreboard": _scoreboard(verified),
			"judge": _compact(judge)
		}
		mutation_tournament_completed.emit(final_reject)
		return final_reject

	var result := {
		"ok": true,
		"tournament": true,
		"goal": goal,
		"population_size": population.size(),
		"verified_count": verified.size(),
		"generation_attempts": attempt,
		"winner": _candidate_public(winner),
		"scoreboard": _scoreboard(verified),
		"judge": _compact(judge),
		"stage_path": staged.get("stage_path", ""),
		"sha256": staged.get("sha256", ""),
		"path": staged.get("path", ""),
		"verified": true,
		"staged": true,
		"final_verification": _compact(staged.get("verification", {}))
	}
	mutation_tournament_completed.emit(result)
	return result

func _verify_tournament_candidate(goal: String, proposal: Dictionary, index: int) -> Dictionary:
	improvement_stage.emit("candidate_test", {
		"goal": goal,
		"candidate": index + 1,
		"path": proposal.get("path", ""),
		"strategy": proposal.get("strategy", "")
	})
	var verification := await evaluate_generated_module(proposal)
	var verified_ok := bool(verification.get("ok", false) and verification.get("verified", false))
	var candidate := {
		"index": index,
		"mutation_tag": proposal.get("mutation_tag", ""),
		"strategy": proposal.get("strategy", ""),
		"path": proposal.get("path", ""),
		"sha256": _sha256_text(str(proposal.get("content", ""))),
		"reason": str(proposal.get("reason", "")),
		"proposal": proposal,
		"verification": _compact(verification),
		"verified": verified_ok,
		"base_score": 0.0,
		"judge_score": 0.0,
		"score": 0.0
	}
	if verified_ok:
		var base := _deterministic_candidate_score(goal, proposal, verification)
		candidate["base_score"] = base
		candidate["score"] = base
	return candidate

func _deterministic_candidate_score(goal: String, proposal: Dictionary, verification: Dictionary) -> float:
	if not verification.get("ok", false): return 0.0
	var score := 60.0
	var content := str(proposal.get("content", ""))
	var reason := str(proposal.get("reason", ""))
	var verification_text := str(proposal.get("verification", ""))
	var lines := content.split("\n").size()
	# Reward explicit reasoning/verification and goal relevance without rewarding
	# raw code size. Tests remain the hard gate; these are tie-breaking metrics.
	if reason.length() >= 80: score += 4.0
	if verification_text.length() >= 40: score += 3.0
	score += minf(10.0, float(_goal_overlap(goal, reason + "\n" + content)) * 1.5)
	if lines >= 12 and lines <= 180: score += 5.0
	elif lines > 320: score -= 4.0
	if content.contains("match ") or content.contains("if "): score += 2.0
	if content.contains("clamp") or content.contains("is Dictionary") or content.contains("typeof"):
		score += 2.0
	if verification.get("test", {}) is Dictionary and bool(verification.get("test", {}).get("ok", false)):
		score += 4.0
	return clampf(score, 0.0, 75.0)

func _goal_overlap(goal: String, text: String) -> int:
	var haystack := text.to_lower()
	var seen: Dictionary = {}
	var count := 0
	for raw in goal.to_lower().split(" ", false):
		var token := str(raw).strip_edges().trim_prefix(".").trim_suffix(".").trim_suffix(",").trim_suffix(":")
		if token.length() < 4 or seen.has(token): continue
		seen[token] = true
		if haystack.contains(token): count += 1
	return count

func _judge_verified_candidates(goal: String, candidates: Array) -> Dictionary:
	if ai == null:
		return {"ok": false, "error": "AI judge unavailable"}
	var public_candidates: Array = []
	for i in range(candidates.size()):
		var candidate: Dictionary = candidates[i]
		var proposal: Dictionary = candidate.get("proposal", {})
		public_candidates.append({
			"index": i,
			"strategy": candidate.get("strategy", ""),
			"reason": str(proposal.get("reason", "")).substr(0, 1200),
			"verification": str(proposal.get("verification", "")).substr(0, 800),
			"content": str(proposal.get("content", "")).substr(0, 7000),
			"base_score": candidate.get("base_score", 0.0)
		})
	var prompt := """
Ты судья турнира мутаций AuroraFox. Все варианты ниже УЖЕ независимо прошли Godot 4.7.1 sandbox-тесты.
Цель: %s

Оцени каждый вариант 0..100 по одинаковым критериям:
1) соответствие цели;
2) корректность алгоритма и обработка краёв;
3) устойчивость к плохому вводу;
4) эффективность;
5) простота сопровождения;
6) полезность как инструмента AuroraFox.
Не награждай длину кода и не выдумывай результаты тестов.

Верни ТОЛЬКО JSON:
{"scores":[{"index":0,"score":0,"reason":"кратко"}],"winner_index":0}

Кандидаты:
%s
""" % [goal, JSON.stringify(public_candidates)]
	var response := await ai.chat([{"role":"user","content":prompt}], 0.0)
	if not response.get("ok", false): return response
	var text := str(response.get("content", "")).replace("```json", "").replace("```", "").strip_edges()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "error": "Mutation judge returned invalid JSON"}
	var scores = parsed.get("scores", [])
	if not scores is Array:
		return {"ok": false, "error": "Mutation judge scores are invalid"}
	return {"ok": true, "scores": scores, "winner_index": int(parsed.get("winner_index", -1))}

func _apply_judge_scores(candidates: Array, judge: Dictionary) -> void:
	if not judge.get("ok", false): return
	var by_index: Dictionary = {}
	for item in judge.get("scores", []):
		if not item is Dictionary: continue
		var idx := int(item.get("index", -1))
		if idx < 0 or idx >= candidates.size(): continue
		by_index[idx] = {
			"score": clampf(float(item.get("score", 0.0)), 0.0, 100.0),
			"reason": str(item.get("reason", "")).substr(0, 800)
		}
	for i in range(candidates.size()):
		var candidate: Dictionary = candidates[i]
		if by_index.has(i):
			var judgement: Dictionary = by_index[i]
			candidate["judge_score"] = float(judgement.get("score", 0.0))
			candidate["judge_reason"] = judgement.get("reason", "")
			candidate["score"] = clampf(float(candidate.get("base_score", 0.0)) + float(candidate.get("judge_score", 0.0)) * 0.25, 0.0, 100.0)
		candidates[i] = candidate

func _scoreboard(candidates: Array) -> Array:
	var result: Array = []
	for candidate in candidates:
		if not candidate is Dictionary: continue
		result.append(_candidate_public(candidate))
	return result

func _compact_candidates(candidates: Array) -> Array:
	var result: Array = []
	for candidate in candidates:
		if candidate is Dictionary:
			result.append(_candidate_public(candidate))
	return result

func _candidate_public(candidate: Dictionary) -> Dictionary:
	return {
		"index": candidate.get("index", -1),
		"mutation_tag": candidate.get("mutation_tag", ""),
		"strategy": candidate.get("strategy", ""),
		"path": candidate.get("path", ""),
		"sha256": candidate.get("sha256", ""),
		"reason": str(candidate.get("reason", "")).substr(0, 1200),
		"verified": bool(candidate.get("verified", false)),
		"base_score": float(candidate.get("base_score", 0.0)),
		"judge_score": float(candidate.get("judge_score", 0.0)),
		"judge_reason": str(candidate.get("judge_reason", "")).substr(0, 800),
		"score": float(candidate.get("score", 0.0)),
		"verification": _compact(candidate.get("verification", {}))
	}

func evaluate_generated_module(proposal: Dictionary) -> Dictionary:
	var validation := _validate_proposal(proposal)
	if not validation.get("ok", false):
		improvement_rejected.emit(validation)
		return validation
	if tools == null:
		return {"ok": false, "error": "Tool registry is not configured"}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Automatic Godot 4.7.1 self-improvement verification is currently enabled on Windows only", "stage": "platform"}

	var path := str(validation.get("path", ""))
	var relative := path.trim_prefix("res://")
	var content := str(proposal.get("content", ""))
	improvement_stage.emit("workspace", {"path": path})
	var created = await tools.call_tool("workspace_create", {
		"task": "AuroraFox self-improvement verification: " + str(proposal.get("reason", "generated extension")),
		"runtime": "local"
	})
	if not _ok(created): return _reject("workspace_create", created)

	improvement_stage.emit("import", {"workspace": created.get("workspace", {})})
	var imported = await tools.call_tool("workspace_import_project", {
		"project_path": "res://",
		"target": "project",
		"max_files": MAX_PROJECT_FILES,
		"max_bytes": MAX_PROJECT_BYTES
	})
	if not _ok(imported): return _reject("workspace_import_project", imported)

	improvement_stage.emit("candidate", {"path": relative})
	var written = await tools.call_tool("workspace_write", {
		"path": "project/" + relative,
		"content": content
	})
	if not _ok(written): return _reject("workspace_write", written)

	var reread = await tools.call_tool("workspace_read", {"path": "project/" + relative, "area": "work"})
	if not _ok(reread): return _reject("workspace_read", reread)
	if str(reread.get("content", "")) != content:
		return _reject("candidate_integrity", {"ok": false, "error": "Sandbox candidate differs from proposed content"})

	improvement_stage.emit("godot_test", {"cwd": "project", "version": "4.7.1"})
	var tested = await tools.call_tool("workspace_test", {"language": "gdscript", "cwd": "project"})
	if not _ok(tested): return _reject("workspace_test", tested)

	var result := {
		"ok": true,
		"verified": true,
		"path": path,
		"reason": str(proposal.get("reason", "")),
		"workspace": created.get("workspace", {}),
		"import": _compact(imported),
		"test": _compact(tested),
		"content_sha256": _sha256_text(content)
	}
	improvement_verified.emit(result)
	return result

func apply_generated_module(proposal: Dictionary) -> Dictionary:
	var verification := await evaluate_generated_module(proposal)
	if not verification.get("ok", false): return verification
	var logical_path := str(verification.get("path", ""))
	var stage_path := _stage_path(logical_path)
	if stage_path.is_empty(): return _reject("stage_path", {"ok": false, "error": "Cannot resolve writable stage path"})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(stage_path.get_base_dir()))
	var write_result = await tools.call_tool("write_file", {"path": stage_path, "content": str(proposal.get("content", ""))})
	if not _ok(write_result): return _reject("stage_generated", write_result)
	var check = await tools.call_tool("read_file", {"path": stage_path})
	if not _ok(check): return _reject("stage_verify", check)
	var expected := str(proposal.get("content", ""))
	if str(check.get("content", "")) != expected:
		return _reject("stage_integrity", {"ok": false, "error": "Staged generated module differs from verified candidate"})
	return {
		"ok": true,
		"verified": true,
		"staged": true,
		"hot_extension": true,
		"path": logical_path,
		"stage_path": stage_path,
		"sha256": _sha256_text(expected),
		"verification": verification,
		"message": "Generated hot extension passed Godot 4.7.1 verification and was staged without activation."
	}

func _stage_path(logical_path: String) -> String:
	var safe := _safe_generated_path(logical_path)
	if safe.is_empty(): return ""
	var relative := safe.trim_prefix(GENERATED_ROOT)
	var root := GENERATED_ROOT if OS.has_feature("editor") else RUNTIME_GENERATED_ROOT
	return root + relative

func _validate_proposal(proposal: Dictionary) -> Dictionary:
	var path := _safe_generated_path(str(proposal.get("path", "")))
	if path.is_empty(): return {"ok": false, "error": "Unsafe generated module path"}
	var content := str(proposal.get("content", ""))
	if content.strip_edges().is_empty(): return {"ok": false, "error": "Generated module is empty"}
	if content.to_utf8_buffer().size() > MAX_GENERATED_BYTES:
		return {"ok": false, "error": "Generated module exceeds size limit"}
	if _contains_unfinished_markers(content):
		return {"ok": false, "error": "Generated module contains unfinished placeholder/stub markers"}
	if not content.contains("extends RefCounted"):
		return {"ok": false, "error": "Hot extension must extend RefCounted"}
	if content.contains("extends Node"):
		return {"ok": false, "error": "Hot extension cannot join the scene tree"}
	if not content.contains("func aurora_extension_manifest"):
		return {"ok": false, "error": "Hot extension is missing aurora_extension_manifest()"}
	if not content.contains(HOT_TOOL_PREFIX):
		return {"ok": false, "error": "Hot extension does not declare an aurora_ext_ tool"}
	for marker in HOT_BLOCKED_MARKERS:
		if content.contains(marker):
			return {"ok": false, "error": "Hot extension uses blocked privileged API marker: " + marker}
	for line in content.split("\n"):
		var clean := str(line).strip_edges()
		if clean.begins_with("load(") or clean.contains("= load(") or clean.begins_with("return load("):
			return {"ok": false, "error": "Hot extension uses blocked dynamic load()"}
	return {"ok": true, "path": path}

func _safe_generated_path(value: String) -> String:
	var path := value.strip_edges().replace("\\", "/")
	if not path.begins_with(GENERATED_ROOT): return ""
	if not path.ends_with(".gd"): return ""
	var relative := path.trim_prefix(GENERATED_ROOT)
	if relative.is_empty() or relative.begins_with("/"): return ""
	if relative == ".." or relative.begins_with("../") or relative.contains("/../") or relative.contains(":"): return ""
	for part in relative.split("/", false):
		if part in ["", ".", ".."]: return ""
	return GENERATED_ROOT + relative

func _contains_unfinished_markers(content: String) -> bool:
	var lower := content.to_lower()
	var markers := [
		"todo", "fixme", "implement later", "not implemented", "placeholder",
		"example stub", "class_name examplestub", "pass #", "raise notimplemented",
		"push_error(\"not implemented", "return null # stub"
	]
	for marker in markers:
		if lower.contains(marker): return true
	return false

func _ok(value: Variant) -> bool:
	return value is Dictionary and bool(value.get("ok", false))

func _reject(stage: String, source: Variant) -> Dictionary:
	var source_dict: Dictionary = source if source is Dictionary else {"error": str(source)}
	var result := {
		"ok": false,
		"verified": false,
		"stage": stage,
		"error": str(source_dict.get("error", "Self-improvement verification failed")),
		"details": _compact(source_dict)
	}
	improvement_rejected.emit(result)
	return result

func _compact(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = value.duplicate(true)
		for key in out.keys():
			var text := str(out[key])
			if text.length() > 6000: out[key] = text.substr(0, 6000) + "…"
		return out
	if value is Array:
		var arr: Array = value
		return arr.slice(0, mini(arr.size(), 50))
	return value

func _sha256_text(text: String) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK: return ""
	if ctx.update(text.to_utf8_buffer()) != OK: return ""
	return ctx.finish().hex_encode().to_lower()
