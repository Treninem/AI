class_name AndroidFirstRun
extends Node

var models := LocalModelManager.new()
var overlay: ColorRect
var panel: VBoxContainer
var status_label: Label
var progress: ProgressBar
var install_button: Button
var import_button: Button
var cancel_button: Button
var model_dialog: FileDialog
var frame: PanelContainer

func _ready() -> void:
	if OS.get_name() != "Android": return
	add_child(models)
	models.download_started.connect(_on_started)
	models.download_progress.connect(_on_progress)
	models.download_finished.connect(_on_finished)
	await get_tree().process_frame
	if not FileAccess.file_exists(LocalModelManager.ACTIVE_MODEL):
		_build_overlay()
		get_viewport().size_changed.connect(_resize_panel)

func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0.015, 0.02, 0.055, 0.97)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 1000
	get_parent().add_child(overlay)

	var safe_margin := MarginContainer.new()
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var insets := _safe_insets()
	safe_margin.add_theme_constant_override("margin_left", int(insets.x) + 18)
	safe_margin.add_theme_constant_override("margin_top", int(insets.y) + 18)
	safe_margin.add_theme_constant_override("margin_right", int(insets.z) + 18)
	safe_margin.add_theme_constant_override("margin_bottom", int(insets.w) + 18)
	overlay.add_child(safe_margin)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_margin.add_child(center)

	frame = PanelContainer.new()
	center.add_child(frame)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(margin)

	panel = VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 14)
	margin.add_child(panel)

	var title := Label.new()
	title.text = "AuroraFox • локальная модель"
	title.add_theme_font_size_override("font_size", 26)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(title)

	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.text = "Модель хранится на телефоне. После установки основной чат работает локально и не требует облачного AI. Можно скачать рекомендуемую модель или выбрать уже имеющийся GGUF-файл."
	panel.add_child(description)

	var recommended := models.recommend_profile()
	var profile: Dictionary = LocalModelManager.PROFILES[recommended]
	var profile_label := Label.new()
	profile_label.text = "Рекомендуется: %s • %.2f ГБ" % [profile.get("name", recommended), float(profile.get("bytes", 0)) / 1000000000.0]
	profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(profile_label)

	var device: Dictionary = models.status().get("device", {})
	var device_label := Label.new()
	device_label.text = "Память устройства: %s МБ RAM • свободно %s МБ" % [str(device.get("total_ram_mb", "?")), str(device.get("free_storage_mb", "?"))]
	device_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(device_label)

	status_label = Label.new()
	status_label.text = "Готово к установке"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status_label)

	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = maxf(1.0, float(profile.get("bytes", 1)))
	progress.value = 0
	progress.show_percentage = true
	progress.custom_minimum_size.y = 28
	panel.add_child(progress)

	install_button = Button.new()
	install_button.text = "Скачать рекомендуемую модель"
	install_button.custom_minimum_size.y = 56
	install_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	install_button.pressed.connect(_install)
	panel.add_child(install_button)

	import_button = Button.new()
	import_button.text = "Выбрать GGUF с телефона"
	import_button.custom_minimum_size.y = 56
	import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_button.pressed.connect(_open_model_dialog)
	panel.add_child(import_button)

	cancel_button = Button.new()
	cancel_button.text = "Отменить загрузку"
	cancel_button.custom_minimum_size.y = 54
	cancel_button.visible = false
	cancel_button.pressed.connect(models.cancel_download)
	panel.add_child(cancel_button)

	model_dialog = FileDialog.new()
	model_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	model_dialog.access = FileDialog.ACCESS_FILESYSTEM
	model_dialog.use_native_dialog = true
	model_dialog.filters = PackedStringArray(["*.gguf ; GGUF model"])
	model_dialog.file_selected.connect(_on_local_model_selected)
	get_parent().add_child(model_dialog)
	_resize_panel()

func _resize_panel() -> void:
	if frame == null: return
	var visible := get_viewport().get_visible_rect().size
	frame.custom_minimum_size = Vector2(
		clampf(visible.x - 48.0, 360.0, 650.0),
		clampf(visible.y - 96.0, 420.0, 720.0)
	)

func _install() -> void:
	_set_actions_enabled(false)
	cancel_button.visible = true
	status_label.text = "Подготовка загрузки…"
	var result: Dictionary = await models.download_recommended()
	if not result.get("ok", false) and not result.get("cancelled", false):
		status_label.text = "Ошибка: " + str(result.get("error", "Не удалось установить модель"))
		_set_actions_enabled(true)
		cancel_button.visible = false
	elif result.get("cancelled", false):
		status_label.text = "Загрузка отменена. Можно продолжить позже."
		_set_actions_enabled(true)
		cancel_button.visible = false

func _open_model_dialog() -> void:
	if model_dialog == null: return
	model_dialog.popup_centered_ratio(0.92)

func _on_local_model_selected(path: String) -> void:
	_set_actions_enabled(false)
	status_label.text = "Проверяю и копирую GGUF…"
	progress.value = 0
	await get_tree().process_frame
	var result: Dictionary = models.install_local_gguf(path)
	if result.get("ok", false):
		status_label.text = "Локальная модель установлена."
		progress.max_value = maxf(1.0, float(result.get("bytes", 1)))
		progress.value = progress.max_value
		await get_tree().create_timer(0.6).timeout
		_close_overlay()
	else:
		status_label.text = "Ошибка GGUF: " + str(result.get("error", "Не удалось установить файл"))
		_set_actions_enabled(true)

func _set_actions_enabled(enabled: bool) -> void:
	if install_button != null: install_button.disabled = not enabled
	if import_button != null: import_button.disabled = not enabled

func _on_started(_profile: String, expected_bytes: int) -> void:
	status_label.text = "Скачивание модели…"
	progress.max_value = maxf(1.0, float(expected_bytes))
	progress.value = 0

func _on_progress(_profile: String, downloaded_bytes: int, expected_bytes: int) -> void:
	progress.max_value = maxf(1.0, float(expected_bytes))
	progress.value = float(downloaded_bytes)
	status_label.text = "Скачано %.2f / %.2f ГБ" % [float(downloaded_bytes) / 1000000000.0, float(expected_bytes) / 1000000000.0]

func _on_finished(_profile: String, ok: bool, message: String) -> void:
	cancel_button.visible = false
	if ok:
		status_label.text = "Локальная модель установлена."
		await get_tree().create_timer(0.7).timeout
		_close_overlay()
	elif message != "Download cancelled":
		status_label.text = "Ошибка: " + message
		_set_actions_enabled(true)

func _close_overlay() -> void:
	if model_dialog != null:
		model_dialog.queue_free()
		model_dialog = null
	if overlay != null:
		overlay.queue_free()
		overlay = null

func _safe_insets() -> Vector4:
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.x <= 0 or screen.y <= 0: return Vector4.ZERO
	if safe.size.x <= 0 or safe.size.y <= 0: safe = Rect2i(Vector2i.ZERO, screen)
	var base := get_window().content_scale_size
	var window_px := DisplayServer.window_get_size()
	var scale := 1.0
	if base.x > 0 and base.y > 0 and window_px.x > 0 and window_px.y > 0:
		scale = maxf(0.001, minf(float(window_px.x) / float(base.x), float(window_px.y) / float(base.y)))
	return Vector4(
		maxf(0.0, float(safe.position.x) / scale),
		maxf(0.0, float(safe.position.y) / scale),
		maxf(0.0, float(screen.x - safe.end.x) / scale),
		maxf(0.0, float(screen.y - safe.end.y) / scale)
	)
