extends Control

const InstalledProductionKnowledgePackSmokeScript = preload("res://scripts/installed_production_knowledge_pack_smoke.gd")
const PACK_ROOT := "user://android-production-pack"
const REPORT_PATH := "user://android-production-knowledge.json"
const FIRST_PATH := "user://android-production-knowledge-first.json"
const ROOTLESS_PATH := "user://android-production-rootless.json"
const EXPECTED_ARCHIVE_SHA256 := "bc0f312448f70a650435af8f30e853ca0a81a58f69c61802de7095bed9e24614"
const EXPECTED_MANIFEST_SHA256 := "bc395f76c0797e9b3751f11fcb7a52b9999ce5c5857ece1f433778bf1fd75cbd"
const EXPECTED_SHARDS := 60
const EXPECTED_RECORDS := 75871
const EXPECTED_CONTENT_BYTES := 1924345221

var _plugin: Object
var _status: Label
var _action: Button
var _share: Button
var _polling := false
var _archive_proof: Dictionary = {}


func _ready() -> void:
	_plugin = Engine.get_singleton("AuroraFoxRuntime") if Engine.has_singleton("AuroraFoxRuntime") else null
	if _plugin == null or not OS.has_feature("android"):
		call_deferred("_run_legacy")
		return
	_build_ui()
	if FileAccess.file_exists(ROOTLESS_PATH):
		_archive_proof = _read_json(ROOTLESS_PATH)
		if FileAccess.file_exists(FIRST_PATH):
			_status.text = "Проверяется повторный запуск и сохранённое состояние…"
			call_deferred("_run_rootless_restart")
		else:
			_prepare_offline_run()
	elif FileAccess.file_exists(PACK_ROOT + "/manifest.json"):
		call_deferred("_run_legacy")
	else:
		_status.text = "Выберите точный архив AuroraFox-Knowledge-RU-2026.09.01-v1.tar.zst.\nНужно около 4 ГБ свободного места. Root и ПК не требуются."
		_action.text = "Выбрать архив"
		_action.disabled = false


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	margin.add_child(box)
	var title := Label.new()
	title.text = "AuroraFox — проверка production Knowledge"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_status.add_theme_font_size_override("font_size", 18)
	box.add_child(_status)
	_action = Button.new()
	_action.custom_minimum_size = Vector2(0, 64)
	_action.pressed.connect(_on_action_pressed)
	box.add_child(_action)
	_share = Button.new()
	_share.text = "Поделиться отчётом"
	_share.custom_minimum_size = Vector2(0, 64)
	_share.visible = false
	_share.pressed.connect(_share_report)
	box.add_child(_share)


func _on_action_pressed() -> void:
	if _action.text == "Выбрать архив":
		var parsed = JSON.parse_string(str(_plugin.selectProductionPackArchive()))
		if not parsed is Dictionary or not bool(parsed.get("ok", false)):
			_fail("Не удалось открыть выбор архива: " + JSON.stringify(parsed))
			return
		_action.disabled = true
		_status.text = "Выберите архив в системном окне Android…"
		_polling = true
	elif _action.text == "Запустить офлайн-проверку":
		_action.disabled = true
		_status.text = "Первый импорт 60 шардов выполняется. Не закрывайте приложение…"
		call_deferred("_run_rootless_first")
	elif _action.text == "Закрыть для перезапуска":
		get_tree().quit(0)


func _process(_delta: float) -> void:
	if not _polling:
		return
	var parsed = JSON.parse_string(str(_plugin.pollProductionPackArchiveImport()))
	if not parsed is Dictionary:
		return
	var stage := str(parsed.get("stage", ""))
	if stage == "extracting":
		var mib := int(parsed.get("progress_bytes", 0)) / (1024 * 1024)
		_status.text = "Проверка и распаковка: %d МБ, файлов: %d…" % [mib, int(parsed.get("files", 0))]
	elif stage == "ready":
		_polling = false
		_archive_proof = parsed
		if str(parsed.get("archive_sha256", "")) != EXPECTED_ARCHIVE_SHA256 or int(parsed.get("shards", 0)) != EXPECTED_SHARDS:
			_fail("Архив распакован, но не совпал с release-контрактом.")
			return
		_write_json(ROOTLESS_PATH, parsed)
		_prepare_offline_run()
	elif stage in ["failed", "cancelled"]:
		_polling = false
		_action.disabled = false
		_fail(str(parsed.get("error", "Выбор архива отменён")))


func _prepare_offline_run() -> void:
	_status.text = "Архив проверен. Включите авиарежим и убедитесь, что Wi-Fi выключен. Затем запустите офлайн-проверку."
	_action.text = "Запустить офлайн-проверку"
	_action.disabled = false


func _run_legacy() -> void:
	var report_path := ProjectSettings.globalize_path(REPORT_PATH)
	var pack_root := ProjectSettings.globalize_path(PACK_ROOT)
	var result: Dictionary = InstalledProductionKnowledgePackSmokeScript.new().run(report_path, pack_root)
	if not bool(result.get("ok", false)):
		push_error(str(result.get("error", "Android production Knowledge Pack acceptance failed")))
	get_tree().quit(int(result.get("exit_code", 1)))


func _run_rootless_first() -> void:
	var result := _run_strict()
	if not _valid_phase(result, EXPECTED_SHARDS, 0):
		_fail("Первый импорт не прошёл: " + JSON.stringify(result))
		return
	var proof: Dictionary = result.get("proof", {})
	_write_json(FIRST_PATH, proof)
	_status.text = "Первый импорт пройден: 60/60 шардов и 75 871 записей. Нажмите кнопку, затем снова откройте приложение для независимой проверки перезапуска."
	_action.text = "Закрыть для перезапуска"
	_action.disabled = false


func _run_rootless_restart() -> void:
	var first := _read_json(FIRST_PATH)
	var result := _run_strict()
	if not _valid_phase({"proof": first}, EXPECTED_SHARDS, 0) or not _valid_phase(result, 0, EXPECTED_SHARDS):
		_fail("Проверка перезапуска не прошла: " + JSON.stringify(result))
		return
	var resumed: Dictionary = result.get("proof", {})
	var final := {
		"schema": "aurorafox.android-rootless-production-knowledge.v1",
		"passed": true,
		"installed": true,
		"platform": "Android",
		"rootless": true,
		"offline_user_confirmed": true,
		"external_ai_required": false,
		"archive_sha256": str(_archive_proof.get("archive_sha256", "")),
		"manifest_sha256": EXPECTED_MANIFEST_SHA256,
		"pack_id": "aurorafox-bootstrap-ru",
		"pack_version": "2026.09.01",
		"shards": EXPECTED_SHARDS,
		"record_count": EXPECTED_RECORDS,
		"content_bytes": EXPECTED_CONTENT_BYTES,
		"first_imported_shards": int(first.get("imported_shards", -1)),
		"restart_skipped_shards": int(resumed.get("skipped_shards", -1)),
		"first_query_match": bool(first.get("query_match", false)),
		"restart_query_match": bool(resumed.get("query_match", false)),
		"state_sha256": str(resumed.get("state_sha256", "")),
	}
	_write_json(REPORT_PATH, final)
	_status.text = "AURORA_ANDROID_ROOTLESS_PRODUCTION_KNOWLEDGE_OK\n\n60 шардов, 75 871 записей: импорт, запрос и отдельный перезапуск прошли. Поделитесь отчётом в этот чат."
	_action.visible = false
	_share.visible = true


func _run_strict() -> Dictionary:
	return InstalledProductionKnowledgePackSmokeScript.new().run(
		ProjectSettings.globalize_path(REPORT_PATH),
		ProjectSettings.globalize_path(PACK_ROOT),
	)


func _valid_phase(result: Dictionary, imported: int, skipped: int) -> bool:
	var proof = result.get("proof", {})
	return (
		proof is Dictionary
		and bool(proof.get("passed", false))
		and bool(proof.get("offline", false))
		and not bool(proof.get("external_ai_required", true))
		and str(proof.get("manifest_sha256", "")) == EXPECTED_MANIFEST_SHA256
		and int(proof.get("shards", -1)) == EXPECTED_SHARDS
		and int(proof.get("record_count", -1)) == EXPECTED_RECORDS
		and int(proof.get("content_bytes", -1)) == EXPECTED_CONTENT_BYTES
		and int(proof.get("imported_shards", -1)) == imported
		and int(proof.get("skipped_shards", -1)) == skipped
		and bool(proof.get("query_match", false))
	)


func _share_report() -> void:
	var report := _read_json(REPORT_PATH)
	var response = JSON.parse_string(str(_plugin.shareProductionPackAcceptanceReport(JSON.stringify(report, "  "))))
	if not response is Dictionary or not bool(response.get("ok", false)):
		_fail("Не удалось открыть отправку отчёта: " + JSON.stringify(response))


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  ") + "\n")
	file.close()
	return true


func _fail(message: String) -> void:
	_status.text = "ОШИБКА: " + message
	push_error(message)
