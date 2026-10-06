class_name CognitionLayer
extends Node

var ai: AIClient

func setup(ai_client: AIClient) -> void:
	ai = ai_client

func make_plan(task: String, skills: Array, failures: Array) -> Dictionary:
	var prompt := """
Ты модуль планирования AuroraFox. Составь короткий практический план выполнения задачи.
Не раскрывай скрытые рассуждения. Верни ТОЛЬКО JSON:
{"objective":"...","steps":["..."],"risks":["..."],"success_checks":["..."],"needs_tools":true}
Учитывай прошлые навыки и ошибки. План должен быть проверяемым и обратимым, где это возможно.
Задача: %s
Полезные навыки: %s
Недавние ошибки: %s
""" % [task, JSON.stringify(skills), JSON.stringify(failures)]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.1)
	if not result.get("ok", false):
		return {"objective": task, "steps": [], "risks": [], "success_checks": [], "needs_tools": true}
	return _parse_json(str(result.get("content", "")), {"objective": task, "steps": []})

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
	if cleaned.begins_with("```"):
		cleaned = cleaned.replace("```json", "").replace("```", "").strip_edges()
	var parser := JSON.new()
	if parser.parse(cleaned) != OK: return fallback
	return parser.data if parser.data is Dictionary else fallback
