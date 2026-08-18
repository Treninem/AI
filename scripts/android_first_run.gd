class_name AndroidFirstRun
extends Node

var models := LocalModelManager.new()
var overlay: ColorRect
var panel: VBoxContainer
var status_label: Label
var progress: ProgressBar
var install_button: Button
var cancel_button: Button

func _ready() -> void:
	if OS.get_name() != "Android": return
	add_child(models)
	models.download_started.connect(_on_started)
	models.download_progress.connect(_on_progress)
	models.download_finished.connect(_on_finished)
	await get_tree().process_frame
	if not FileAccess.file_exists(LocalModelManager.ACTIVE_MODEL):
		_build_overlay()

func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0.015, 0.02, 0.055, 0.97)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 1000
	get_parent().add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(520, 360)
	center.add_child(frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	frame.add_child(margin)

	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 16)
	margin.add_child(panel)

	var title := Label.new()
	title.text = "AuroraFox • локальная модель"
	title.add_theme_font_size_override("font_size", 26)
	panel.add_child(title)

	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.text = "Для Android модель хранится на телефоне и после установки работает без облачного AI. Нужна только первая загрузка файла модели."
	panel.add_child(description)

	var recommended := models.recommend_profile()
	var profile: Dictionary = LocalModelManager.PROFILES[recommended]
	var profile_label := Label.new()
	profile_label.text = "Рекомендуется: %s • %.2f ГБ" % [profile.get("name", recommended), float(profile.get("bytes", 0)) / 1000000000.0]
	profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(profile_label)

	status_label = Label.new()
	status_label.text = "Готово к установке"
	panel.add_child(status_label)

	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = 100
	progress.value = 0
	progress.show_percentage = true
	panel.add_child(progress)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	install_button = Button.new()
	install_button.text = "Установить локальную модель"
	install_button.custom_minimum_size.y = 54
	install_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	install_button.pressed.connect(_install)
	row.add_child(install_button)

	cancel_button = Button.new()
	cancel_button.text = "Отмена"
	cancel_button.custom_minimum_size.y = 54
	cancel_button.visible = false
	cancel_button.pressed.connect(models.cancel_download)
	row.add_child(cancel_button)

func _install() -> void:
	install_button.disabled = true
	cancel_button.visible = true
	status_label.text = "Подготовка загрузки…"
	var result := await models.download_recommended()
	if not result.get("ok", false):
		status_label.text = "Ошибка: " + str(result.get("error", "Не удалось установить модель"))
		install_button.disabled = false
		cancel_button.visible = false

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
		status_label.text = "Модель установлена. AuroraFox готов."
		await get_tree().create_timer(0.7).timeout
		if overlay != null: overlay.queue_free()
	else:
		status_label.text = "Ошибка: " + message
		install_button.disabled = false
