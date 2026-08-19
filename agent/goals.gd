class_name AuroraGoals
extends RefCounted

var targets := {
	"response_accuracy": 0.90,
	"response_latency_seconds": 2.0,
	"memory_recall": 0.95,
	"tool_success": 0.98,
	"stability": 0.99
}

func snapshot() -> Dictionary:
	return targets.duplicate(true)

func choose_goal(compatibility: Dictionary, recent_failures: Array, observations: Dictionary = {}) -> String:
	var missing_components: Array = compatibility.get("missing_components", [])
	if not missing_components.is_empty():
		return "Восстановить совместимость компонентов AuroraFox: " + ", ".join(PackedStringArray(missing_components))

	var missing_tools: Array = compatibility.get("missing_required_tools", [])
	if not missing_tools.is_empty():
		return "Восстановить интеграцию обязательных инструментов AuroraFox: " + ", ".join(PackedStringArray(missing_tools))

	if not recent_failures.is_empty():
		var last_failure = recent_failures[recent_failures.size() - 1]
		return "Снизить повторяемость последней подтвержденной ошибки AuroraFox без изменения существующего ядра: " + str(last_failure).substr(0, 500)

	var latency := float(observations.get("response_latency_seconds", 0.0))
	if latency > float(targets.response_latency_seconds):
		return "Снизить задержку ответа AuroraFox ниже %.1f сек без ухудшения качества" % float(targets.response_latency_seconds)

	return "Улучшить точность и полезность ответов AuroraFox небольшим совместимым расширением, сохранив текущие API и поведение старых модулей"

func score_candidate(metrics: Dictionary) -> float:
	var accuracy := clampf(float(metrics.get("accuracy", 0.0)), 0.0, 1.0)
	var usefulness := clampf(float(metrics.get("usefulness", 0.0)), 0.0, 1.0)
	var preference := clampf(float(metrics.get("user_preference", 0.0)), 0.0, 1.0)
	var speed := clampf(float(metrics.get("speed", 0.0)), 0.0, 1.0)
	var stability := clampf(float(metrics.get("stability", 0.0)), 0.0, 1.0)
	var resource_usage := clampf(float(metrics.get("resource_efficiency", 0.0)), 0.0, 1.0)
	return accuracy * 0.35 + usefulness * 0.20 + preference * 0.15 + speed * 0.10 + stability * 0.15 + resource_usage * 0.05
