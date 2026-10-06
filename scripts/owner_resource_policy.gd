class_name OwnerResourcePolicy
extends RefCounted

const PATH := "user://owner_resources.cfg"
const DEFAULTS := {
	"chat_max_tokens": 768,
	"terse_max_tokens": 128,
	"memory_max_items": 5000,
	"knowledge_max_items": 10000,
	"dedupe_window": 1000,
	"index_batch": 64,
	"index_text_chars": 24000,
	"vector_tokens": 768,
	"vector_features": 4096,
	"task_trace_chars": 12000,
	"feedback_prompt_chars": 12000,
	"feedback_answer_chars": 20000,
	"feedback_summary_chars": 1200,
	"feedback_observed_chars": 2400,
	"feedback_lesson_chars": 2400,
	"direct_memory_chars": 240,
	"direct_history_items": 4,
	"direct_history_chars": 800,
	"agent_history_items": 24,
	"agent_history_chars": 16000,
	"attachment_items": 6,
	"attachment_excerpt_chars": 6000,
	"attachment_metadata_chars": 1800,
	"context_message_chars": 24000,
	"tool_result_chars": 5000,
	"tool_result_items": 25,
}
const LABELS := {
	"chat_max_tokens": "Windows Core: токенов обычного ответа",
	"terse_max_tokens": "Windows Core: токенов короткого ответа",
	"memory_max_items": "Память: записей",
	"knowledge_max_items": "Прежнее Knowledge: записей",
	"dedupe_window": "Окно проверки дубликатов, записей",
	"index_batch": "Индексация: записей в пакете",
	"index_text_chars": "Индексация: символов записи",
	"vector_tokens": "Семантический индекс: токенов записи",
	"vector_features": "Семантический индекс: признаков записи",
	"task_trace_chars": "Память: символов следа задачи",
	"feedback_prompt_chars": "Feedback: символов запроса",
	"feedback_answer_chars": "Feedback: символов ответа",
	"feedback_summary_chars": "Feedback: символов итога",
	"feedback_observed_chars": "Feedback: символов наблюдения",
	"feedback_lesson_chars": "Feedback: символов урока",
	"direct_memory_chars": "Чат: символов найденной записи",
	"direct_history_items": "Чат: реплик истории",
	"direct_history_chars": "Чат: символов реплики",
	"agent_history_items": "Агент: реплик истории",
	"agent_history_chars": "Агент: символов реплики",
	"attachment_items": "Агент: вложений из реплики",
	"attachment_excerpt_chars": "Агент: символов фрагмента вложения",
	"attachment_metadata_chars": "Агент: символов метаданных",
	"context_message_chars": "Агент: символов собранной реплики",
	"tool_result_chars": "Агент: символов результата инструмента",
	"tool_result_items": "Агент: элементов результата инструмента",
}
static var _cached: Dictionary = {}
static var revision := 0

static func limits(path: String = PATH) -> Dictionary:
	var file := ConfigFile.new()
	file.load(path)
	var out := DEFAULTS.duplicate()
	for key in DEFAULTS:
		var candidate = file.get_value("resources", key, DEFAULTS[key])
		if _valid(key, candidate): out[key] = int(candidate)
	return out

static func value(key: String) -> int:
	if _cached.is_empty(): _cached = limits()
	return int(_cached.get(key, DEFAULTS.get(key, 0)))

static func _valid(key: String, candidate: Variant) -> bool:
	if not (candidate is int or candidate is float): return false
	var number := float(candidate)
	if key in ["chat_max_tokens", "terse_max_tokens"] and number > 2147483647.0: return false
	# Representation only; no artificial maximum. A batch must make progress.
	return is_finite(number) and number >= (1 if key == "index_batch" else 0) and number < 9223372036854775807.0 and number == floor(number)

static func save(values: Dictionary, path: String = PATH) -> Error:
	var current := limits(path)
	for key in values:
		if not DEFAULTS.has(key) or not _valid(key, values[key]): return ERR_INVALID_PARAMETER
		current[key] = int(values[key])
	var file := ConfigFile.new()
	for key in current: file.set_value("resources", key, current[key])
	var err := file.save(path)
	if err == OK and path == PATH:
		_cached = current
		revision += 1
	return err

static func clip(text: String, key: String) -> String:
	var cap := value(key)
	return text if cap == 0 or text.length() <= cap else text.substr(0, cap)

static func count(size: int, key: String) -> int:
	var cap := value(key)
	return size if cap == 0 else mini(size, cap)
