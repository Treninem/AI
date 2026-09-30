extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _run() -> void:
	var store := ChatStore.new()
	root.add_child(store)
	await process_frame
	store.chats.clear()
	store.active_chat_id = ""
	store.create_chat("Feedback smoke")
	store.add_message("user", "Сколько будет два плюс два?")
	var assistant_id := store.add_message("assistant", "Четыре.", [], {
		"response_origin": "aurorafox_core",
		"runtime": "AuroraFox Core",
		"active_model": "smoke.gguf",
		"app_version": "V1.5.0.0"
	})
	if assistant_id.is_empty():
		_fail("Assistant message has no stable identity", 2)
		return
	if not store.set_message_feedback(assistant_id, -1, {}, "recorded"):
		_fail("Negative feedback was not stored", 3)
		return
	var context := store.feedback_context(assistant_id)
	if str(context.get("prompt", "")) != "Сколько будет два плюс два?" or str(context.get("answer", "")) != "Четыре.":
		_fail("Feedback is not bound to the exact prompt and answer", 4)
		return
	if int(context.get("feedback", {}).get("score", 0)) != -1:
		_fail("Feedback score was lost", 5)
		return
	var metadata: Dictionary = context.get("metadata", {})
	for key in ["response_origin", "runtime", "active_model", "app_version"]:
		if str(metadata.get(key, "")).is_empty():
			_fail("Feedback identity is missing metadata: " + key, 6)
			return
	var analysis := {
		"ok": true,
		"summary": "Проверка",
		"observed": "Ответ отмечен пользователем",
		"proposed_lesson": "Не применять без подтверждения",
		"promotion": "owner_confirmation_required"
	}
	if not store.set_message_feedback(assistant_id, -1, analysis, "awaiting_confirmation"):
		_fail("Feedback analysis proposal was not stored", 7)
		return
	if str(store.feedback_context(assistant_id).get("feedback", {}).get("state", "")) != "awaiting_confirmation":
		_fail("Feedback bypassed the owner-confirmation state", 8)
		return
	if not store.set_message_feedback(assistant_id, 0):
		_fail("Feedback cancellation failed", 9)
		return
	if not store.feedback_context(assistant_id).get("feedback", {}).is_empty():
		_fail("Cancelled feedback remained active", 10)
		return
	var experience := ExperienceStore.new()
	root.add_child(experience)
	await process_frame
	experience.skills.clear()
	experience.failures.clear()
	experience.save_skill({
		"name": "Feedback smoke",
		"goal_pattern": "два плюс два",
		"summary": "Проверять арифметику",
		"source_feedback_id": assistant_id,
		"confidence": 0.8
	})
	experience.record_failure("два плюс два", "ошибка", assistant_id)
	if experience.relevant_skills("два плюс два", 5).is_empty() or experience.recent_failures(5).is_empty():
		_fail("Confirmed feedback did not enter private experience", 11)
		return
	if not experience.retract_feedback(assistant_id):
		_fail("Accepted feedback experience could not be retracted", 12)
		return
	if not experience.relevant_skills("два плюс два", 5).is_empty() or not experience.recent_failures(5).is_empty():
		_fail("Retracted feedback still influences private experience", 13)
		return
	store.save_all()
	print("AURORA_CHAT_FEEDBACK_OK")
	quit(0)
