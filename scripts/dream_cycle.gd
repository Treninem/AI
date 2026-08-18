class_name DreamCycle
extends Node

const IDEAS_PATH := "user://aurorafox_improvement_ideas.json"

var ai: AIClient
var completed_tasks := 0
var ideas: Array = []

func setup(ai_client: AIClient) -> void:
	ai = ai_client
	ideas = _load_ideas()

func note_completed_task() -> void:
	completed_tasks += 1

func should_reflect() -> bool:
	return completed_tasks > 0 and completed_tasks % 5 == 0

func reflect(skills: Array, failures: Array) -> Array:
	if ai == null:
		return []
	var prompt := """
Ты Dream Cycle AuroraFox — безопасный модуль самоанализа.
На основе статистики навыков и ошибок предложи до 5 конкретных улучшений системы.
Не предлагай обход защит, получение секретов, скрытую установку, самовольное развёртывание или необратимые действия.
Не выполняй улучшения — только сформулируй проверяемые идеи.
Верни ТОЛЬКО JSON-массив объектов:
[{"title":"...","problem":"...","proposal":"...","test":"...","priority":1,"risk":"low|medium|high"}]
Навыки: %s
Ошибки: %s
""" % [JSON.stringify(skills).substr(0, 30000), JSON.stringify(failures).substr(0, 20000)]
	var result := await ai.chat([{"role":"user","content":prompt}], 0.15)
	if not result.get("ok", false):
		return []
	var parsed = _parse_array(str(result.get("content", "")))
	for item in parsed:
		if item is Dictionary:
			var idea: Dictionary = item.duplicate(true)
			idea["created_at"] = Time.get_datetime_string_from_system(true)
			idea["status"] = "proposed"
			ideas.append(idea)
	if ideas.size() > 200:
		ideas = ideas.slice(ideas.size() - 200)
	_save_ideas()
	return parsed

func pending_ideas(limit := 20) -> Array:
	var out: Array = []
	for item in ideas:
		if str(item.get("status", "proposed")) == "proposed":
			out.append(item)
	if out.size() > limit:
		return out.slice(out.size() - limit)
	return out

func _load_ideas() -> Array:
	if not FileAccess.file_exists(IDEAS_PATH):
		return []
	var f := FileAccess.open(IDEAS_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Array else []

func _save_ideas() -> void:
	var f := FileAccess.open(IDEAS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(ideas, "\t"))

func _parse_array(text: String) -> Array:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("```"):
		cleaned = cleaned.replace("```json", "").replace("```", "").strip_edges()
	var parsed = JSON.parse_string(cleaned)
	return parsed if parsed is Array else []
