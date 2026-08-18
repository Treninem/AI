class_name SpecialistTeam
extends Node

var ai: AIClient
var coder := CodeSpecialist.new()

func setup(ai_client: AIClient) -> void:
	ai = ai_client
	if coder.get_parent() == null:
		add_child(coder)
	coder.setup(ai_client)

func consult(task: String, context: Dictionary = {}) -> Dictionary:
	var responses: Dictionary = {}
	var roles := [
		{"name":"planner","prompt":"Разложи задачу на проверяемые этапы, зависимости и критерии готовности."},
		{"name":"researcher","prompt":"Определи, какие факты, документацию или внешние данные нужно проверить, а что уже можно решить локально."},
		{"name":"critic","prompt":"Ищи слабые места, ложные предположения, риски, пропущенные проверки и способы доказать результат."},
		{"name":"computer_operator","prompt":"Если задача требует работы с GUI/экраном, предложи безопасную последовательность наблюдение-действие-проверка. Иначе скажи, что GUI не нужен."}
	]
	for role in roles:
		responses[role.name] = await _ask_role(str(role.name), str(role.prompt), task, context)
	if _looks_like_code_task(task, context):
		responses["code_architect"] = await coder.analyze_request(task, context.get("files", []))
	return responses

func synthesize(task: String, opinions: Dictionary) -> Dictionary:
	var prompt := """
Ты главный координатор AuroraFox. Ниже результаты внутренних специалистов.
Собери из них единый исполнимый план. Не выбирай мнение по голосованию: разрешай противоречия по проверяемости.
Верни строгий JSON:
{"objective":"...","steps":[{"id":1,"action":"...","verification":"...","specialist":"..."}],"needs_tools":["..."],"risks":["..."],"success_criteria":["..."]}
Задача: %s
Специалисты: %s
""" % [task, JSON.stringify(opinions)]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.1)
	if not result.get("ok", false): return {"ok":false,"error":result.get("error", "")}
	var parsed := _parse_json(str(result.get("content", "")))
	if parsed.is_empty(): return {"ok":false,"error":"Coordinator returned invalid JSON"}
	parsed["ok"] = true
	return parsed

func _ask_role(name: String, instruction: String, task: String, context: Dictionary) -> Dictionary:
	var prompt := """
Ты внутренний специалист AuroraFox: %s.
%s
Не выдавай скрытые рассуждения. Нужны только краткие выводы, проверяемые факты и рекомендации.
Верни строгий JSON: {"summary":"...","recommendations":["..."],"checks":["..."],"risks":["..."],"confidence":0.0}
Задача: %s
Контекст: %s
""" % [name, instruction, task, JSON.stringify(context)]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.15)
	if not result.get("ok", false): return {"ok":false,"error":result.get("error", "")}
	var parsed := _parse_json(str(result.get("content", "")))
	if parsed.is_empty(): return {"ok":false,"error":"Invalid specialist JSON"}
	parsed["ok"] = true
	return parsed

func _looks_like_code_task(task: String, context: Dictionary) -> bool:
	if not context.get("files", []).is_empty(): return true
	var q := task.to_lower()
	var markers := ["код","скрипт","программ","compile","build","bug","ошибк","godot","python","javascript","typescript","c++","c#","java","rust","golang","sql","api","repository","репозитор"]
	for marker in markers:
		if q.contains(marker): return true
	return false

func _parse_json(text: String) -> Dictionary:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("```"):
		cleaned = cleaned.replace("```json", "").replace("```", "").strip_edges()
	var parsed = JSON.parse_string(cleaned)
	return parsed if parsed is Dictionary else {}
