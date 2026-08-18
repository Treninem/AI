class_name SpecialistTeam
extends Node

var ai: AIClient
var coder := CodeSpecialist.new()

const ROLE_DEFS := {
	"planner": "Разложи задачу на проверяемые этапы, зависимости, критерии готовности и точки отката.",
	"researcher": "Определи, какие факты, документацию или внешние данные нужно проверить. Отделяй известное от предположений.",
	"critic": "Ищи слабые места, ложные предположения, риски, пропущенные проверки и способы доказать результат.",
	"computer_operator": "Для GUI-задач предложи цикл наблюдение -> действие -> повторная проверка. Учитывай координаты, состояние окна и возможность отмены.",
	"file_analyst": "Разбери структуру файлов, связи между ними, форматы, зависимости, потенциально важные участки и порядок чтения.",
	"tester": "Определи, как доказать работоспособность: тесты, компиляция, статический анализ, контрольные примеры и критерии прохождения.",
	"verifier": "Проверь, подтверждаются ли выводы реальными результатами инструментов и выполнены ли все условия задачи. Не доверяй неподтверждённым заявлениям.",
	"knowledge_curator": "Определи, что из результата стоит сохранить как долгосрочное знание или навык, а что является временным контекстом."
}

func setup(ai_client: AIClient) -> void:
	ai = ai_client
	if coder.get_parent() == null:
		add_child(coder)
	coder.setup(ai_client)

func consult(task: String, context: Dictionary = {}) -> Dictionary:
	var responses: Dictionary = {}
	var selected := _select_roles(task, context)
	for role_name in selected:
		responses[role_name] = await _ask_role(role_name, str(ROLE_DEFS.get(role_name, "Проверь задачу в своей области.")), task, context)
	if _looks_like_code_task(task, context):
		responses["code_architect"] = await coder.analyze_request(task, context.get("files", []))
	responses["_meta"] = {
		"selected_roles": selected,
		"code_architect": responses.has("code_architect"),
		"mean_confidence": _mean_confidence(responses)
	}
	return responses

func synthesize(task: String, opinions: Dictionary) -> Dictionary:
	var prompt := """
Ты главный координатор AuroraFox. Ниже результаты внутренних специалистов.
Собери единый исполнимый план. Разрешай противоречия по проверяемости, а не голосованием.
Каждый шаг должен иметь способ проверки и ответственного специалиста.
Верни строгий JSON:
{"objective":"...","steps":[{"id":1,"action":"...","verification":"...","specialist":"...","rollback":"..."}],"needs_tools":["..."],"risks":["..."],"success_criteria":["..."],"confidence":0.0}
Задача: %s
Специалисты: %s
""" % [task, JSON.stringify(opinions)]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.1)
	if not result.get("ok", false):
		return {"ok":false,"error":result.get("error", "")}
	var parsed := _parse_json(str(result.get("content", "")))
	if parsed.is_empty():
		return {"ok":false,"error":"Coordinator returned invalid JSON"}
	var audit := await audit_plan(task, parsed, opinions)
	parsed["audit"] = audit
	if audit.get("ok", false) and not bool(audit.get("approved", true)):
		var revised := await _revise_plan(task, parsed, opinions, audit)
		if revised.get("ok", false):
			parsed = revised
			parsed["audit"] = await audit_plan(task, parsed, opinions)
	parsed["ok"] = true
	return parsed

func audit_plan(task: String, plan: Dictionary, opinions: Dictionary) -> Dictionary:
	var prompt := """
Ты независимый критик плана AuroraFox. Проверь план после того, как координатор уже его собрал.
Ищи: пропущенные зависимости, непроверяемые шаги, отсутствие отката, неподтверждённые предположения, рискованную работу сразу в реальном окружении.
Верни строгий JSON:
{"approved":true,"issues":["..."],"required_fixes":["..."],"confidence":0.0}
Задача: %s
План: %s
Исходные мнения: %s
""" % [task, JSON.stringify(plan), JSON.stringify(opinions)]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.05)
	if not result.get("ok", false):
		return {"ok":false,"approved":false,"error":result.get("error", "")}
	var parsed := _parse_json(str(result.get("content", "")))
	if parsed.is_empty():
		return {"ok":false,"approved":false,"error":"Plan audit returned invalid JSON"}
	parsed["ok"] = true
	return parsed

func audit_answer(task: String, answer: String, trajectory: Array, opinions: Dictionary = {}) -> Dictionary:
	var prompt := """
Ты финальный verifier AuroraFox. Сверь ответ с задачей и фактическими результатами инструментов.
Не требуй скрытых рассуждений. Проверь только наблюдаемые утверждения, полноту и соответствие условиям.
Если ответ утверждает, что код работает, должны быть подтверждения запуском/тестом/компиляцией/статическим анализом либо честное указание, что это не проверено.
Верни строгий JSON:
{"approved":true,"confidence":0.0,"issues":["..."],"corrected_answer":"..."}
Задача: %s
Ответ: %s
Траектория инструментов: %s
Мнения специалистов: %s
""" % [task, answer, JSON.stringify(trajectory), JSON.stringify(opinions)]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.05)
	if not result.get("ok", false):
		return {"ok":false,"approved":false,"confidence":0.0,"error":result.get("error", "")}
	var parsed := _parse_json(str(result.get("content", "")))
	if parsed.is_empty():
		return {"ok":false,"approved":false,"confidence":0.0,"error":"Answer audit returned invalid JSON"}
	parsed["ok"] = true
	return parsed

func _revise_plan(task: String, plan: Dictionary, opinions: Dictionary, audit: Dictionary) -> Dictionary:
	var prompt := """
Ты координатор AuroraFox. Исправь план по замечаниям независимого критика.
Сохрани только проверяемые шаги и добавь недостающие проверки/откаты.
Верни строгий JSON той же структуры, без пояснений вокруг JSON.
Задача: %s
План: %s
Замечания: %s
Мнения: %s
""" % [task, JSON.stringify(plan), JSON.stringify(audit), JSON.stringify(opinions)]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.05)
	if not result.get("ok", false):
		return {"ok":false,"error":result.get("error", "")}
	var parsed := _parse_json(str(result.get("content", "")))
	if parsed.is_empty():
		return {"ok":false,"error":"Plan revision returned invalid JSON"}
	parsed["ok"] = true
	return parsed

func _select_roles(task: String, context: Dictionary) -> Array:
	var roles: Array = ["planner", "critic", "verifier"]
	var q := task.to_lower()
	if _contains_any(q, ["найди", "поиск", "интернет", "документац", "верси", "новост", "api", "источник"]):
		roles.append("researcher")
	if _contains_any(q, ["компьютер", "экран", "мыш", "курсор", "окно", "нажми", "открой", "игр", "сапер", "косын"]):
		roles.append("computer_operator")
	if not context.get("files", []).is_empty() or _contains_any(q, ["файл", "архив", "pdf", "docx", "xlsx", "проект", "репозитор"]):
		roles.append("file_analyst")
	if _looks_like_code_task(task, context):
		roles.append("tester")
	if task.length() > 900 or _contains_any(q, ["запомни", "навык", "база знаний", "обуч", "опыт"]):
		roles.append("knowledge_curator")
	return _unique(roles)

func _ask_role(name: String, instruction: String, task: String, context: Dictionary) -> Dictionary:
	var prompt := """
Ты внутренний специалист AuroraFox: %s.
%s
Не выдавай скрытые рассуждения. Нужны только краткие выводы, проверяемые факты и рекомендации.
Верни строгий JSON:
{"summary":"...","recommendations":["..."],"checks":["..."],"risks":["..."],"confidence":0.0}
Задача: %s
Контекст: %s
""" % [name, instruction, task, JSON.stringify(context)]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.12)
	if not result.get("ok", false):
		return {"ok":false,"error":result.get("error", ""),"confidence":0.0}
	var parsed := _parse_json(str(result.get("content", "")))
	if parsed.is_empty():
		return {"ok":false,"error":"Invalid specialist JSON","confidence":0.0}
	parsed["confidence"] = clampf(float(parsed.get("confidence", 0.5)), 0.0, 1.0)
	parsed["ok"] = true
	return parsed

func _looks_like_code_task(task: String, context: Dictionary) -> bool:
	if not context.get("files", []).is_empty():
		return true
	var q := task.to_lower()
	return _contains_any(q, ["код","скрипт","программ","compile","build","bug","ошибк","godot","python","javascript","typescript","c++","c#","java","rust","golang","go ","sql","api","repository","репозитор","php","ruby","swift","kotlin","dart","lua","powershell","bash"])

func _mean_confidence(responses: Dictionary) -> float:
	var total := 0.0
	var count := 0
	for key in responses.keys():
		if str(key).begins_with("_"):
			continue
		var item = responses[key]
		if item is Dictionary and item.get("ok", false):
			total += float(item.get("confidence", 0.5))
			count += 1
	return total / float(count) if count > 0 else 0.0

func _contains_any(text: String, markers: Array) -> bool:
	for marker in markers:
		if text.contains(str(marker)):
			return true
	return false

func _unique(values: Array) -> Array:
	var out: Array = []
	for value in values:
		if value not in out:
			out.append(value)
	return out

func _parse_json(text: String) -> Dictionary:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("```"):
		cleaned = cleaned.replace("```json", "").replace("```", "").strip_edges()
	var parsed = JSON.parse_string(cleaned)
	return parsed if parsed is Dictionary else {}
