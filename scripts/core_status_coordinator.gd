class_name AuroraCoreStatusCoordinator
extends Node

var _updated_once := false

func _ready() -> void:
	call_deferred("_refresh_after_startup")

func _refresh_after_startup() -> void:
	if _updated_once:
		return
	await get_tree().create_timer(0.35).timeout
	var main := get_parent()
	if main == null:
		return
	var ai_value = main.get("ai")
	var status_value = main.get("status")
	if not ai_value is AIClient or not status_value is Label:
		return
	var ai: AIClient = ai_value
	var status: Label = status_value
	var info: Dictionary = ai.runtime_info()
	status.text = _status_text(info)
	_updated_once = true

func refresh_now() -> void:
	_updated_once = false
	await _refresh_after_startup()

func _status_text(info: Dictionary) -> String:
	var platform := str(info.get("platform", OS.get_name()))
	var model_installed := bool(info.get("model_installed", false))
	var fallback := bool(info.get("ollama_fallback", false))
	var suffix := " • режим совместимости Ollama разрешён" if fallback else ""
	if platform == "Windows":
		var desktop: Dictionary = info.get("desktop", {})
		var engine_installed := bool(desktop.get("engine_installed", false))
		var running := bool(desktop.get("running", false))
		if model_installed and engine_installed:
			return ("AuroraFox Core • встроенный AI%s" % [" • активен" if running else ""]) + suffix
		if model_installed:
			return "AuroraFox Core • встроенный AI готов • Core Engine восстанавливается автоматически" + suffix
		if engine_installed:
			return "AuroraFox Core • Engine готов • встроенный Core-файл отсутствует в пакете" + suffix
		return "AuroraFox Core • подготовка встроенного AI" + suffix
	if platform == "Android":
		var android: Dictionary = info.get("android", {})
		if model_installed and bool(android.get("llama_cpp", false)):
			return "AuroraFox Core • встроенный Android AI"
		if model_installed:
			return "AuroraFox Core • встроенный AI готов • runtime восстанавливается"
		return "AuroraFox Core • подготовка встроенного AI"
	if model_installed:
		return "AuroraFox Core • встроенный AI готов" + suffix
	return "AuroraFox Core • встроенный AI недоступен в этой сборке" + suffix
