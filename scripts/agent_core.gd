class_name AgentCore
extends Node

var ai: AIClient
var memory: MemoryStore
var tools: ToolRegistry
var experience := ExperienceStore.new()
var cognition := CognitionLayer.new()
var dream_cycle := DreamCycle.new()
var team := SpecialistTeam.new()
var max_steps := 12
var enable_planning := true
var enable_self_check := true
var enable_skill_learning := true
var enable_dream_cycle := true
var enable_specialist_team := true

func setup(ai_client: AIClient, memory_store: MemoryStore, tool_registry: ToolRegistry) -> void:
	ai = ai_client
	memory = memory_store
	tools = tool_registry
	if experience.get_parent() == null: add_child(experience)
	if cognition.get_parent() == null: add_child(cognition)
	if dream_cycle.get_parent() == null: add_child(dream_cycle)
	if team.get_parent() == null: add_child(team)
	cognition.setup(ai)
	dream_cycle.setup(ai)
	team.setup(ai)

func run_task(task: String) -> String:
	memory.remember("user_task", task)
	var useful_skills := experience.relevant_skills(task, 5)
	var recent_failures := experience.recent_failures(5)
	var specialist_context: Dictionary = {}
	var specialist_plan: Dictionary = {}
	if enable_specialist_team and _needs_specialists(task):
		specialist_context = await team.consult(task, {})
		specialist_plan = await team.synthesize(task, specialist_context)
		memory.remember("specialist_consultation", JSON.stringify(_compact_result(specialist_context)))
		if specialist_plan.has("audit"):
			memory.remember("specialist_plan_audit", JSON.stringify(_compact_result(specialist_plan.get("audit", {}))))

	var plan: Dictionary = {"objective": task, "steps": []}
	if specialist_plan.get("ok", false):
		plan = specialist_plan
	elif enable_planning:
		plan = await cognition.make_plan(task, useful_skills, recent_failures)
	memory.remember("task_plan", JSON.stringify(plan))

	var messages: Array = [
		{"role":"system", "content": _system_prompt(task, useful_skills, plan, recent_failures, specialist_context)},
		{"role":"user", "content": task}
	]
	var trajectory: Array = []
	var draft_answer := ""

	for step in range(max_steps):
		var result := await ai.chat(messages)
		if not result.get("ok", false):
			experience.record_failure(task, "Model error: " + str(result.get("error", "unknown")))
			return "Ошибка модели: " + str(result.get("error", "unknown"))
		var text := str(result.get("content", ""))
		var action := _extract_action(text)
		if action.is_empty():
			draft_answer = text
			break
		var tool_name := str(action.get("tool", ""))
		var args: Dictionary = action.get("args", {})
		var tool_result = await tools.call_tool(tool_name, args)
		var trace_item := {"step":step + 1,"tool":tool_name,"args":_safe_args(args),"result":_compact_result(tool_result)}
		trajectory.append(trace_item)
		experience.checkpoint(task, step + 1, tool_name, _safe_args(args), tool_result)
		messages.append({"role":"assistant", "content": text})
		messages.append({"role":"user", "content": "TOOL_RESULT %s: %s" % [tool_name, JSON.stringify(tool_result)]})
		memory.remember("tool", JSON.stringify(trace_item))

	if draft_answer.is_empty():
		experience.record_failure(task, "Autonomous step limit reached")
		return "Достигнут лимит автономных шагов. Я сохранил контрольные точки и смогу продолжить с последней проверки."

	var final_answer := draft_answer
	var confidence := 0.55
	if enable_self_check:
		var verification := await cognition.verify_answer(task, draft_answer, trajectory)
		final_answer = str(verification.get("final_answer", draft_answer))
		confidence = clampf(float(verification.get("confidence", 0.55)), 0.0, 1.0)
		var issues: Array = verification.get("issues", [])
		if not issues.is_empty():
			memory.remember("self_check_issues", JSON.stringify(issues))

	if enable_specialist_team and not specialist_context.is_empty():
		var team_audit := await team.audit_answer(task, final_answer, trajectory, specialist_context)
		if team_audit.get("ok", false):
			var audit_confidence := clampf(float(team_audit.get("confidence", confidence)), 0.0, 1.0)
			confidence = minf(confidence, audit_confidence)
			var corrected := str(team_audit.get("corrected_answer", "")).strip_edges()
			if not corrected.is_empty():
				final_answer = corrected
			var audit_issues: Array = team_audit.get("issues", [])
			if not audit_issues.is_empty():
				memory.remember("specialist_answer_issues", JSON.stringify(audit_issues))
			memory.remember("specialist_answer_audit", JSON.stringify(_compact_result(team_audit)))

	memory.remember("assistant_answer", final_answer)
	memory.remember("answer_confidence", str(confidence))
	if enable_skill_learning and confidence >= 0.62 and not trajectory.is_empty():
		var skill := await cognition.extract_skill(task, final_answer, trajectory, confidence)
		if not skill.is_empty():
			experience.save_skill(skill)
			memory.remember("learned_skill", JSON.stringify(skill))

	dream_cycle.note_completed_task()
	if enable_dream_cycle and dream_cycle.should_reflect():
		var ideas := await dream_cycle.reflect(experience.skills, experience.recent_failures(20))
		if not ideas.is_empty():
			memory.remember("improvement_ideas", JSON.stringify(ideas))
	return final_answer

func _system_prompt(task: String, useful_skills: Array, plan: Dictionary, failures: Array, specialist_context: Dictionary) -> String:
	var recent := memory.recent(8)
	var knowledge := memory.search_knowledge(task, 6)
	return """
Ты AuroraFox — автономный локальный AI-агент внутри Godot 4.7.1.
Используй память, инструменты, компьютерное зрение, песочницу, внутреннюю команду специалистов и накопленные навыки.
Если нужен инструмент, верни ТОЛЬКО JSON: {"tool":"tool_name","args":{...}}. Иначе дай конечный ответ.

ПРОТОКОЛ ПЕСОЧНИЦЫ:
1. Для сложной задачи с кодом, файлами, проектом или экспериментом сначала вызови workspace_create.
2. Изучи исходные данные и положи рабочие копии в workspace, не экспериментируй сразу над оригиналом.
3. Перед крупным изменением создай workspace_snapshot.
4. Выбирай подходящую среду автоматически: Windows -> контейнер Docker/Podman при наличии, иначе локальная ограниченная среда; Android -> приватная песочница приложения и встроенный runtime.
5. Пиши и изменяй файлы через workspace_write/workspace_read, запускай через workspace_exec.
6. После каждого существенного этапа проверяй фактический результат, а не предполагай успех.
7. Для программирования обязательно используй workspace_test либо эквивалентную компиляцию/тест/статический анализ.
8. Если проверка ухудшила результат — используй workspace_rollback и попробуй другую стратегию.
9. Переноси результат из песочницы в реальное окружение только после проверки и только когда задача этого требует.
10. Никогда не называй эксперимент успешным без наблюдаемого подтверждения.

Для программирования понимай не только синтаксис, но назначение, поток данных, состояние, побочные эффекты, зависимости, ошибки и способ проверки.
Определяй язык и стек по проекту; поддержка языков расширяемая. Не утверждай, что код работает, пока это не подтверждено запуском, компиляцией, тестами или статическим анализом.
При противоречии между специалистами предпочитай результат, который можно проверить инструментом или воспроизвести.
Не удаляй данные, не обходи аутентификацию/CAPTCHA, не извлекай секреты и не делай необратимые действия без явного разрешения.
Текущий план: %s
Специалисты: %s
Полезные навыки: %s
Недавние ошибки: %s
Инструменты: %s
Память: %s
Знания: %s
""" % [JSON.stringify(plan), JSON.stringify(_compact_result(specialist_context)), JSON.stringify(useful_skills), JSON.stringify(failures), JSON.stringify(tools.describe_tools()), JSON.stringify(recent), JSON.stringify(knowledge)]

func _needs_specialists(task: String) -> bool:
	if task.length() > 350: return true
	var q := task.to_lower()
	for marker in ["код","скрипт","программ","проект","репозитор","ошибк","архитект","создай","сделай","исправ","проанализ","компьютер","мыш","экран","игр","godot","python","javascript","typescript","c++","c#","java","rust","sql","api"]:
		if q.contains(marker): return true
	return false

func _extract_action(text: String) -> Dictionary:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("```"): cleaned = cleaned.replace("```json", "").replace("```", "").strip_edges()
	if not cleaned.begins_with("{"): return {}
	var parsed = JSON.parse_string(cleaned)
	return parsed if parsed is Dictionary and parsed.has("tool") else {}

func _safe_args(args: Dictionary) -> Dictionary:
	var safe := args.duplicate(true)
	for key in safe.keys():
		var lower := str(key).to_lower()
		if lower.contains("password") or lower.contains("token") or lower.contains("secret") or lower.contains("cookie") or lower.contains("authorization"):
			safe[key] = "[REDACTED]"
	return safe

func _compact_result(value: Variant) -> Variant:
	if value is Dictionary:
		var copy: Dictionary = value.duplicate(true)
		for key in copy.keys():
			var text := str(copy[key])
			if text.length() > 5000: copy[key] = text.substr(0, 5000) + "…"
		return copy
	if value is Array:
		var arr: Array = value
		return arr.slice(0, mini(arr.size(), 25))
	return str(value).substr(0, 5000)