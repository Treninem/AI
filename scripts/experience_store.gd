class_name ExperienceStore
extends Node

const SKILLS_PATH := "user://aurorafox_skills.json"
const CHECKPOINTS_PATH := "user://aurorafox_checkpoints.json"
const FAILURES_PATH := "user://aurorafox_failures.json"

var skills: Array = []
var checkpoints: Array = []
var failures: Array = []

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	skills = _load_array(SKILLS_PATH)
	checkpoints = _load_array(CHECKPOINTS_PATH)
	failures = _load_array(FAILURES_PATH)

func _load_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Array else []

func _save_array(path: String, data: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))

func save_skill(skill: Dictionary) -> void:
	var normalized := {
		"name": str(skill.get("name", "Навык")),
		"goal_pattern": str(skill.get("goal_pattern", "")),
		"summary": str(skill.get("summary", "")),
		"steps": skill.get("steps", []),
		"tools": skill.get("tools", []),
		"success_count": int(skill.get("success_count", 1)),
		"failure_count": int(skill.get("failure_count", 0)),
		"confidence": clampf(float(skill.get("confidence", 0.6)), 0.0, 1.0),
		"created_at": Time.get_datetime_string_from_system(true),
		"last_used_at": Time.get_datetime_string_from_system(true)
	}
	var existing := _find_similar_skill(normalized.goal_pattern)
	if existing >= 0:
		var old: Dictionary = skills[existing]
		old["summary"] = normalized.summary
		old["steps"] = normalized.steps
		old["tools"] = normalized.tools
		old["success_count"] = int(old.get("success_count", 0)) + 1
		old["confidence"] = min(1.0, max(float(old.get("confidence", 0.5)), normalized.confidence) + 0.03)
		old["last_used_at"] = normalized.last_used_at
		skills[existing] = old
	else:
		skills.append(normalized)
	_save_array(SKILLS_PATH, skills)

func mark_skill_failure(goal_pattern: String, note: String) -> void:
	var idx := _find_similar_skill(goal_pattern)
	if idx >= 0:
		var item: Dictionary = skills[idx]
		item["failure_count"] = int(item.get("failure_count", 0)) + 1
		item["confidence"] = max(0.05, float(item.get("confidence", 0.5)) - 0.08)
		skills[idx] = item
		_save_array(SKILLS_PATH, skills)
	record_failure(goal_pattern, note)

func record_failure(task: String, note: String) -> void:
	failures.append({
		"task": task,
		"note": note,
		"time": Time.get_datetime_string_from_system(true)
	})
	if failures.size() > 300:
		failures = failures.slice(failures.size() - 300)
	_save_array(FAILURES_PATH, failures)

func checkpoint(task: String, step_index: int, tool_name: String, args: Dictionary, result: Variant) -> void:
	checkpoints.append({
		"task": task,
		"step": step_index,
		"tool": tool_name,
		"args": args,
		"result_summary": _compact(result),
		"time": Time.get_datetime_string_from_system(true)
	})
	if checkpoints.size() > 500:
		checkpoints = checkpoints.slice(checkpoints.size() - 500)
	_save_array(CHECKPOINTS_PATH, checkpoints)

func relevant_skills(task: String, limit := 5) -> Array:
	var scored: Array = []
	var q_tokens := _tokens(task)
	for s in skills:
		var item: Dictionary = s
		var hay := str(item.get("goal_pattern", "")) + " " + str(item.get("summary", ""))
		var score := _overlap(q_tokens, _tokens(hay))
		score += float(item.get("confidence", 0.0)) * 0.35
		score += min(0.25, float(int(item.get("success_count", 0))) * 0.02)
		score -= min(0.25, float(int(item.get("failure_count", 0))) * 0.03)
		if score > 0.05:
			scored.append({"score": score, "skill": item})
	scored.sort_custom(func(a, b): return float(a.score) > float(b.score))
	var out: Array = []
	for i in range(min(limit, scored.size())):
		out.append(scored[i].skill)
	return out

func recent_failures(limit := 5) -> Array:
	if failures.is_empty():
		return []
	return failures.slice(max(0, failures.size() - limit))

func _find_similar_skill(pattern: String) -> int:
	var p := _tokens(pattern)
	var best := -1
	var best_score := 0.0
	for i in range(skills.size()):
		var score := _overlap(p, _tokens(str(skills[i].get("goal_pattern", ""))))
		if score > best_score:
			best_score = score
			best = i
	return best if best_score >= 0.6 else -1

func _tokens(text: String) -> Dictionary:
	var normalized := text.to_lower()
	for c in [".", ",", ":", ";", "!", "?", "(", ")", "[", "]", "{", "}", "\n", "\t", "/", "\\"]:
		normalized = normalized.replace(c, " ")
	var d := {}
	for part in normalized.split(" ", false):
		if part.length() >= 3:
			d[part] = true
	return d

func _overlap(a: Dictionary, b: Dictionary) -> float:
	if a.is_empty() or b.is_empty():
		return 0.0
	var common := 0
	for k in a.keys():
		if b.has(k):
			common += 1
	return float(common) / float(max(1, min(a.size(), b.size())))

func _compact(value: Variant) -> String:
	var text := JSON.stringify(value)
	return text.substr(0, 4000)
