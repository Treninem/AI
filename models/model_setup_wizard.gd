class_name AuroraModelSetupWizard
extends Node

const ENGINE_STATE_PATH := "user://aurora_core_engine_setup.json"
const LOCAL_MODEL_PATH := "user://models/aurorafox-main.gguf"
const FOX_LOGO: Texture2D = preload("res://assets/ui/fox_logo.svg")

var popup: PopupPanel
var engine_status: Label
var model_status: Label
var detail_label: Label
var progress: ProgressBar
var install_engine_button: Button
var download_model_button: Button
var import_model_button: Button
var fallback_toggle: CheckButton
var model_picker: FileDialog
var model_manager := LocalModelManager.new()
var engine_pid := 0
var startup_wait := 2.0
var shown_once := false

func _ready() -> void:
	if OS.get_name() != "Windows": return
	add_child(model_manager)
	model_manager.download_started.connect(_on_download_started)
	model_manager.download_progress.connect(_on_download_progress)
	model_manager.download_finished.connect(_on_download_finished)
	_build_ui()
	set_process(true)

func _process(delta: float) -> void:
	if OS.get_name() != "Windows": return
	if engine_pid > 0:
		_read_engine_state()
		if not OS.is_process_running(engine_pid):
			_read_engine_state()
			engine_pid = 0
			_set_controls_enabled(true)
			_refresh_status()
	if not shown_once:
		startup_wait -= delta
		if startup_wait <= 0.0:
			shown_once = true
			_refresh_status()
			if not _core_ready(): popup.popup_centered()

func show_setup() -> void:
	if popup == null: return
	_refresh_status()
	popup.popup_centered()

func _core_ready() -> bool:
	var main := get_parent()
	if main == null: return false
	var existing_ai = main.get("ai")
	if not existing_ai is AIClient: return false
	var info: Dictionary = existing_ai.runtime_info()
	if not bool(info.get("model_installed", false)): return false
	if Engine.has_singleton("AuroraFoxRuntime"):
		var native := Engine.get_singleton("AuroraFoxRuntime")
		if native != null and native.has_method("chatLocal"): return true
	var desktop: Dictionary = info.get("desktop", {})
	return bool(desktop.get("engine_installed", false))

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 89
	add_child(layer)
	popup = PopupPanel.new()
	popup.size = Vector2i(760, 650)
	layer.add_child(popup)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]: margin.add_theme_constant_override(side, 24)
	popup.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var logo := TextureRect.new()
	logo.texture = FOX_LOGO
	logo.custom_minimum_size = Vector2(58, 58)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(logo)
	var title_box := VBoxContainer.new()
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title_box)
	var title := Label.new()
	title.text = "AuroraFox Core"
	title.add_theme_font_size_override("font_size", 26)
	title_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Собственный локальный runtime • GGUF • без обязательной Ollama"
	subtitle.add_theme_font_size_override("font_size", 12)
	title_box.add_child(subtitle)

	var intro := Label.new()
	intro.text = "Для полностью автономной работы на Windows нужны две локальные части: Core Engine и GGUF-модель. Модель хранится в профиле AuroraFox. Ollama может остаться только как необязательный режим совместимости."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)

	box.add_child(HSeparator.new())
	var engine_title := Label.new()
	engine_title.text = "1. AuroraFox Core Engine"
	engine_title.add_theme_font_size_override("font_size", 19)
	box.add_child(engine_title)
	engine_status = Label.new()
	engine_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(engine_status)
	install_engine_button = Button.new()
	install_engine_button.text = "Установить / обновить Core Engine"
	install_engine_button.pressed.connect(_install_engine)
	box.add_child(install_engine_button)

	box.add_child(HSeparator.new())
	var model_title := Label.new()
	model_title.text = "2. Локальная GGUF-модель"
	model_title.add_theme_font_size_override("font_size", 19)
	box.add_child(model_title)
	model_status = Label.new()
	model_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(model_status)
	var model_row := HBoxContainer.new()
	model_row.add_theme_constant_override("separation", 8)
	box.add_child(model_row)
	download_model_button = Button.new()
	download_model_button.text = "Скачать рекомендуемую"
	download_model_button.pressed.connect(_download_model)
	model_row.add_child(download_model_button)
	import_model_button = Button.new()
	import_model_button.text = "Выбрать GGUF…"
	import_model_button.pressed.connect(func(): model_picker.popup_centered_ratio(0.75))
	model_row.add_child(import_model_button)

	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = 100
	progress.value = 0
	progress.show_percentage = true
	progress.custom_minimum_size.y = 25
	box.add_child(progress)
	detail_label = Label.new()
	detail_label.text = "Готово к настройке."
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail_label)

	box.add_child(HSeparator.new())
	fallback_toggle = CheckButton.new()
	fallback_toggle.text = "Разрешить Ollama как резервный режим совместимости"
	fallback_toggle.tooltip_text = "Не требуется для AuroraFox Core. При включении разрешает legacy fallback для чата и legacy semantic embeddings памяти."
	fallback_toggle.toggled.connect(_toggle_fallback)
	box.add_child(fallback_toggle)
	var safety := Label.new()
	safety.text = "Core Engine и модель проверяются локально. Импорт GGUF проверяет заголовок файла и SHA-256; установка Engine использует SHA-256 опубликованного GitHub Release asset и транзакционную замену. По умолчанию AuroraFox не обращается к Ollama даже для памяти."
	safety.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	safety.add_theme_font_size_override("font_size", 12)
	box.add_child(safety)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(footer)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(func(): popup.hide())
	footer.add_child(close)

	model_picker = FileDialog.new()
	model_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	model_picker.access = FileDialog.ACCESS_FILESYSTEM
	model_picker.use_native_dialog = true
	model_picker.filters = PackedStringArray(["*.gguf ; GGUF models"])
	model_picker.file_selected.connect(_import_model)
	add_child(model_picker)
	_refresh_status()

func _main_ai() -> AIClient:
	var main := get_parent()
	if main == null: return null
	var existing = main.get("ai")
	return existing if existing is AIClient else null

func _main_memory() -> MemoryStore:
	var main := get_parent()
	if main == null: return null
	var existing = main.get("memory")
	return existing if existing is MemoryStore else null

func _refresh_status() -> void:
	if engine_status == null: return
	var ai := _main_ai()
	var info := ai.runtime_info() if ai != null else {}
	var desktop: Dictionary = info.get("desktop", {})
	var engine_ready := bool(desktop.get("engine_installed", false))
	engine_status.text = "✓ Core Engine установлен" if engine_ready else "Core Engine ещё не установлен"
	if engine_ready:
		engine_status.text += "\n" + str(desktop.get("engine_path", ""))
	var model_info := model_manager.status()
	var installed := bool(model_info.get("installed", false))
	var size_mb := float(model_info.get("size", 0)) / 1048576.0
	model_status.text = ("✓ GGUF-модель установлена • %.0f МБ\n%s" % [size_mb, LOCAL_MODEL_PATH]) if installed else "GGUF-модель не установлена\n%s" % LOCAL_MODEL_PATH
	if ai != null: fallback_toggle.set_pressed_no_signal(ai.ollama_fallback_enabled())
	if engine_ready and installed:
		detail_label.text = "AuroraFox Core полностью готов к локальной работе."

func _install_engine() -> void:
	if engine_pid > 0: return
	var ai := _main_ai()
	var installer := ai.core_engine_installer() if ai != null else ""
	if installer.is_empty() or not FileAccess.file_exists(installer):
		detail_label.text = "Установщик Core Engine не найден в этой сборке."
		return
	var state_abs := ProjectSettings.globalize_path(ENGINE_STATE_PATH)
	if FileAccess.file_exists(ENGINE_STATE_PATH): DirAccess.remove_absolute(state_abs)
	var args := PackedStringArray(["-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", installer, "-StateFile", state_abs])
	engine_pid = OS.create_process("powershell.exe", args, false)
	if engine_pid <= 0:
		detail_label.text = "Windows не смогла запустить установку Core Engine."
		return
	progress.value = 0
	detail_label.text = "Подготовка AuroraFox Core Engine…"
	_set_controls_enabled(false)

func _read_engine_state() -> void:
	var file := FileAccess.open(ENGINE_STATE_PATH, FileAccess.READ)
	if file == null: return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary: return
	progress.value = clampi(int(parsed.get("progress", 0)), 0, 100)
	detail_label.text = str(parsed.get("message", ""))
	if str(parsed.get("stage", "")) == "ready": _refresh_status()

func _download_model() -> void:
	if model_manager.current_request != null: return
	_set_controls_enabled(false)
	var result := await model_manager.download_recommended()
	_set_controls_enabled(true)
	if bool(result.get("ok", false)):
		_activate_model()
		detail_label.text = "GGUF-модель скачана, проверена и активирована."
	else:
		detail_label.text = "Не удалось установить модель: %s" % str(result.get("error", "неизвестная ошибка"))
	_refresh_status()

func _import_model(path: String) -> void:
	_set_controls_enabled(false)
	detail_label.text = "Проверяю и копирую выбранную GGUF-модель…"
	var result := model_manager.install_local_gguf(path)
	_set_controls_enabled(true)
	if bool(result.get("ok", false)):
		_activate_model()
		detail_label.text = "Модель импортирована и активирована. SHA-256: %s" % str(result.get("sha256", ""))
	else:
		detail_label.text = "Импорт модели отклонён: %s" % str(result.get("error", "неизвестная ошибка"))
	_refresh_status()

func _activate_model() -> void:
	var ai := _main_ai()
	if ai != null: ai.configure_local_model(LOCAL_MODEL_PATH)

func _toggle_fallback(enabled: bool) -> void:
	var ai := _main_ai()
	if ai != null:
		ai.set_ollama_fallback(enabled)
	var memory_store := _main_memory()
	if memory_store != null:
		memory_store.set_legacy_semantic_compat_enabled(enabled)
	detail_label.text = "Legacy Ollama compatibility включена для чата и семантической памяти." if enabled else "Полностью локальный режим: Ollama compatibility отключена."

func _on_download_started(_profile: String, expected_bytes: int) -> void:
	progress.value = 0
	detail_label.text = "Скачивание модели • %.2f ГБ" % (float(expected_bytes) / 1073741824.0)

func _on_download_progress(_profile: String, downloaded_bytes: int, expected_bytes: int) -> void:
	if expected_bytes > 0: progress.value = clampf(float(downloaded_bytes) * 100.0 / float(expected_bytes), 0.0, 100.0)
	detail_label.text = "Модель: %.2f / %.2f ГБ" % [float(downloaded_bytes) / 1073741824.0, float(expected_bytes) / 1073741824.0]

func _on_download_finished(_profile: String, ok: bool, message: String) -> void:
	if ok: progress.value = 100
	detail_label.text = message

func _set_controls_enabled(enabled: bool) -> void:
	if install_engine_button != null: install_engine_button.disabled = not enabled
	if download_model_button != null: download_model_button.disabled = not enabled
	if import_model_button != null: import_model_button.disabled = not enabled
