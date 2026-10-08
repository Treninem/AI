class_name CognitionLayer
extends Node

var ai: AIClient
var last_plan_diagnostic: Dictionary = {}
var capture_synthetic_plan_response := false

func setup(ai_client: AIClient) -> void:
	ai = ai_client

func make_plan(task: String, skills: Array, failures: Array) -> Dictionary:
	var prompt := """
Ты модуль планирования AuroraFox. Составь короткий практический план выполнения задачи.
Не раскрывай скрытые рассуждения. Верни только строгий JSON:
{"objective":"...","steps":["..."],"risks":["..."],"success_checks":["..."],"needs_tools":true}
Учитывай прошлые навыки и ошибки. План должен быть проверяемым и обратимым, где это возможно.
Задача: %s
Полезные навыки: %s
Недавние ошибки: %s
""" % [task, JSON.stringify(skills), JSON.stringify(failures)]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.1)
	var content := str(result.get("content", ""))
	last_plan_diagnostic = {"transport_ok": bool(result.get("ok", false)), "content_chars": content.length(), "content_sha256": content.sha256_text(), "json_brace_present": content.contains("{"), "fence_present": content.contains("```")}
	if capture_synthetic_plan_response:
		last_plan_diagnostic["synthetic_response_excerpt"] = content.substr(0, 1024)
	var failed := {"objective": task, "steps": [], "risks": [], "success_checks": [], "needs_tools": true}
	if not result.get("ok", false):
		last_plan_diagnostic["status"] = "transport_failed"
		return failed
	var plan := _parse_json(content, {})
	last_plan_diagnostic["objective_type"] = typeof(plan.get("objective"))
	last_plan_diagnostic["steps_type"] = typeof(plan.get("steps"))
	if not plan.get("objective") is String or not plan.get("steps") is Array:
		last_plan_diagnostic["status"] = "invalid_json_or_plan_contract"
		return failed
	for step in plan.steps:
		if not step is String or str(step).strip_edges().is_empty():
			last_plan_diagnostic["status"] = "invalid_step_contract"
			return failed
	if str(plan.objective).strip_edges().is_empty() or plan.steps.is_empty():
		last_plan_diagnostic["status"] = "empty_plan"
		return failed
	last_plan_diagnostic["status"] = "valid_plan"
	return plan

func verify_answer(task: String, answer: String, trajectory: Array) -> Dictionary:
	var prompt := """
Ты независимый проверяющий AuroraFox. Не показывай скрытые рассуждения.
Проверь, действительно ли ответ соответствует задаче и подтверждается результатами инструментов.
Верни ТОЛЬКО JSON:
{"ok":true,"confidence":0.0,"issues":["..."],"final_answer":"...","should_retry":false}
Если ответ хороший, final_answer может совпадать с исходным. Если есть неподтверждённые утверждения — исправь их или явно отметь ограничения.
Задача: %s
Черновой ответ: %s
Краткий журнал инструментов: %s
""" % [task, answer, OwnerResourcePolicy.clip(JSON.stringify(trajectory), "verification_trace_chars")]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.05)
	if not result.get("ok", false):
		return {"ok": false, "confidence": 0.0, "issues": ["self-check unavailable"], "final_answer": answer, "should_retry": false}
	var failed := {"ok": false, "confidence": 0.0, "issues": ["self-check returned invalid JSON/contract"], "final_answer": answer, "should_retry": false}
	var checked := _parse_json(str(result.get("content", "")), {})
	var confidence_value = checked.get("confidence")
	if not checked.get("ok") is bool or not (confidence_value is int or confidence_value is float):
		return failed
	if not is_finite(float(confidence_value)) or float(confidence_value) < 0.0 or float(confidence_value) > 1.0:
		return failed
	if not checked.get("final_answer") is String or not checked.get("issues") is Array:
		return failed
	return checked

func extract_skill(task: String, final_answer: String, trajectory: Array, confidence: float) -> Dictionary:
	if trajectory.is_empty():
		return {}
	var prompt := """
Ты модуль обучения AuroraFox. Из успешного выполнения выдели повторно используемый навык.
Не сохраняй пароли, токены, персональные данные и скрытые рассуждения.
Верни ТОЛЬКО JSON:
{"name":"...","goal_pattern":"...","summary":"...","steps":["..."],"tools":["..."],"confidence":0.0}
Сохраняй только практическую стратегию и проверяемые действия.
Задача: %s
Финальный результат: %s
Журнал действий: %s
Оценка уверенности: %.2f
""" % [task, final_answer, OwnerResourcePolicy.clip(JSON.stringify(trajectory), "verification_trace_chars"), confidence]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.1)
	if not result.get("ok", false):
		return {}
	return _parse_json(str(result.get("content", "")), {})

func _parse_json(text: String, fallback: Dictionary) -> Dictionary:
	var cleaned := text.strip_edges()
	var parser := JSON.new()
	if parser.parse(cleaned) == OK and parser.data is Dictionary: return parser.data
	if cleaned.begins_with("```"):
		var first_newline := cleaned.find("\n")
		var closing_fence := cleaned.rfind("```")
		if first_newline >= 0 and closing_fence > first_newline:
			if parser.parse(cleaned.substr(first_newline + 1, closing_fence - first_newline - 1).strip_edges()) == OK and parser.data is Dictionary:
				return parser.data
	var extracted := _extract_first_json_object(cleaned)
	if extracted.is_empty(): return fallback
	return parser.data if parser.parse(extracted) == OK and parser.data is Dictionary else fallback

func _extract_first_json_object(text: String) -> String:
	var start := text.find("{")
	while start >= 0:
		var depth := 0
		var in_string := false
		var escaped := false
		for i in range(start, text.length()):
			var ch := text.substr(i, 1)
			if in_string:
				if escaped:
					escaped = false
				elif ch == "\\":
					escaped = true
				elif ch == "\"":
					in_string = false
				continue
			if ch == "\"":
				in_string = true
			elif ch == "{":
				depth += 1
			elif ch == "}":
				depth -= 1
				if depth == 0:
					var candidate := text.substr(start, i - start + 1)
					var parser := JSON.new()
					if parser.parse(candidate) == OK and parser.data is Dictionary: return candidate
					break
		start = text.find("{", start + 1)
	return ""
