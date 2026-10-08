class_name UserIntentRouter
extends RefCounted

# This router decides whether a user-supplied attachment enters private local
# Knowledge. Owner policy defines reading a supplied source as remembering it;
# explicit negation and capability/how-to questions remain non-persistent.

const NEGATED_LEARNING := [
	"не изуч", "не учи", "не обуч", "не запомин", "не сохраня", "не добав",
	"не импорт", "без сохран", "не заноси", "не включай в баз", "don't learn",
	"do not learn", "don't save", "do not save"
]
const META_QUESTIONS := [
	"как изуч", "как обуч", "как добав", "как импорт", "что значит изуч",
	"умеешь изуч", "можешь ли изучать", "способен изучать", "how to learn",
	"can you learn files", "what does learn"
]
const SKILL_PATTERNS := [
	"научи этому навыку", "научи новому навыку", "сохрани как навык",
	"добавь навык", "импортируй навык", "усвой этот навык", "learn this skill",
	"import skill", "save as skill"
]
const TRAINING_PATTERNS := [
	"для дообучения", "данные для обучения", "обучающая выборка", "набор примеров",
	"датасет", "тренировочные данные", "training data", "training dataset",
	"fine-tuning dataset", "finetuning dataset"
]
const KNOWLEDGE_ACTION_STEMS := [
	"изуч", "усво", "запом", "внес", "занес", "добав", "импорт", "сохран"
]
const READ_ACTION_STEMS := [
	"прочит", "расскаж", "посчит", "проанализ", "найд", "выдел", "объясн",
	"сравн", "проверь", "summar", "read", "calculate", "analy", "find"
]
const KNOWLEDGE_TARGET_STEMS := [
	"файл", "документ", "архив", "материал", "содерж", "информац", "знани",
	"баз", "бд", "памят", "источник", "вложен", "это", "этот", "эти"
]

func learning_type(instruction: String) -> String:
	return str(classify_attachment_learning(instruction).get("learning_type", ""))

func classify_attachment_learning(instruction: String) -> Dictionary:
	var normalized := _normalize(instruction)
	if normalized.is_empty():
		return _decision("none", "", 1.0, "no_instruction")
	if _contains_any(normalized, NEGATED_LEARNING):
		return _decision("do_not_learn", "", 1.0, "explicit_negation")
	if _contains_any(normalized, META_QUESTIONS) and not _has_deictic_attachment_target(normalized):
		return _decision("capability_question", "", 0.98, "question_not_authorization")
	if _contains_any(normalized, SKILL_PATTERNS) or ((_contains_any(normalized, ["навык", "умени", "skill"])) and _has_action(normalized)):
		return _decision("learn_attachment", "skill", 0.99, "explicit_skill_instruction")
	if _contains_any(normalized, TRAINING_PATTERNS) and _has_action(normalized):
		return _decision("learn_attachment", "training", 0.96, "explicit_training_instruction")
	if _has_action(normalized) and (_has_target(normalized) or _is_short_learning_command(normalized)):
		return _decision("learn_attachment", "knowledge", 0.93, "explicit_knowledge_instruction")
	if _contains_any(normalized, READ_ACTION_STEMS):
		return _decision("learn_attachment", "knowledge", 0.91, "owner_read_means_remember")
	return _decision("analyze_only", "", 0.72, "no_durable_learning_authorization")

func _decision(kind: String, learning_type_value: String, confidence: float, reason: String) -> Dictionary:
	return {
		"kind": kind,
		"learning_type": learning_type_value,
		"confidence": confidence,
		"reason": reason,
		"durable_write_authorized": not learning_type_value.is_empty()
	}

func _normalize(value: String) -> String:
	var normalized := value.to_lower().strip_edges().replace("ё", "е")
	for symbol in ["\n", "\t", ".", ",", ":", ";", "!", "?", "(", ")", "[", "]", "{", "}", "\"", "'"]:
		normalized = normalized.replace(symbol, " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	return normalized.strip_edges()

func _contains_any(text: String, patterns: Array) -> bool:
	for pattern in patterns:
		if text.contains(str(pattern)):
			return true
	return false

func _has_action(text: String) -> bool:
	if _contains_any(text, ["learn this", "save this", "add this", "remember this", "import this"]):
		return true
	return _contains_any(text, KNOWLEDGE_ACTION_STEMS)

func _has_target(text: String) -> bool:
	return _contains_any(text, KNOWLEDGE_TARGET_STEMS)

func _has_deictic_attachment_target(text: String) -> bool:
	return _contains_any(text, ["этот файл", "этот документ", "этот архив", "это вложение", "прикреплен", "this file", "this document", "attached"])

func _is_short_learning_command(text: String) -> bool:
	var words := text.split(" ", false)
	return words.size() <= 5 and _has_action(text)
