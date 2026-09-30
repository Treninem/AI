extends SceneTree

func _init() -> void:
	var router := UserIntentRouter.new()
	var knowledge := [
		"Изучи этот файл",
		"Пожалуйста, усвой содержимое прикреплённого документа",
		"Запомни эти материалы в своей базе знаний",
		"Внеси информацию из архива в БД",
		"Можешь изучить этот файл?",
		"learn this attached document",
		"Прочитай документ и расскажи главное",
		"Посчитай сумму в таблице",
		"Найди важные данные в этом файле"
	]
	for phrase in knowledge:
		if router.learning_type(phrase) != "knowledge":
			push_error("Knowledge paraphrase was not understood: " + phrase)
			quit(2)
			return
	for phrase in ["Сохрани этот набор примеров как данные для дообучения", "Импортируй training dataset"]:
		if router.learning_type(phrase) != "training":
			push_error("Training paraphrase was not understood: " + phrase)
			quit(3)
			return
	for phrase in ["Усвой этот материал как новый навык", "save as skill"]:
		if router.learning_type(phrase) != "skill":
			push_error("Skill paraphrase was not understood: " + phrase)
			quit(4)
			return
	for phrase in [
		"Не изучай этот файл",
		"Как изучить файл?",
		"Ты умеешь изучать документы?"
	]:
		if not router.learning_type(phrase).is_empty():
			push_error("Non-learning request gained durable-write authority: " + phrase)
			quit(5)
			return
	print("AURORA_USER_INTENT_ROUTER_OK")
	quit(0)
