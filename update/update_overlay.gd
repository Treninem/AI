class_name AuroraUpdateOverlay
extends Node

var layer: CanvasLayer
var popup: PopupPanel
var status_label: Label
var details_label: Label
var apply_button: Button
var auto_check_box: CheckBox
var auto_download_box: CheckBox
var interval: SpinBox

func _ready() -> void:
	if OS.get_name() not in ["Windows", "Android"]:
		return
	_build_ui()
	AuroraUpdate.update_check_started.connect(_on_check_started)
	AuroraUpdate.update_available.connect(_on_update_available)
	AuroraUpdate.no_update.connect(_on_no_update)
	AuroraUpdate.download_started.connect(_on_download_started)
	AuroraUpdate.update_ready.connect(_on_update_ready)
	AuroraUpdate.update_error.connect(_on_update_error)
	AuroraUpdate.update_applying.connect(_on_update_applying)
	AuroraUpdate.settings_changed.connect(_sync_settings)
	_sync_settings(AuroraUpdate.get_settings())

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.022, 0.027, 0.048, 0.995)
	style.border_color = Color(0.37, 0.63, 0.94, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.72)
	style.shadow_size = 18
	return style

func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 75
	add_child(layer)

	popup = PopupPanel.new()
	popup.name = "UpdatePopup"
	popup.size = Vector2i(620, 500)
	popup.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(popup)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	popup.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Обновления AuroraFox"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var version := Label.new()
	version.text = "Текущая версия: %s" % AuroraUpdate.current_version
	box.add_child(version)

	status_label = Label.new()
	status_label.text = "Автоматические обновления готовы"
	status_label.add_theme_font_size_override("font_size", 17)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)

	details_label = Label.new()
	details_label.text = "Stable-канал. Пакеты проверяются перед установкой."
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(details_label)

	box.add_child(HSeparator.new())

	auto_check_box = CheckBox.new()
	auto_check_box.text = "Автоматически проверять обновления"
	auto_check_box.toggled.connect(func(v): AuroraUpdate.set_auto_check(v))
	box.add_child(auto_check_box)

	auto_download_box = CheckBox.new()
	auto_download_box.text = "Автоматически загружать найденные обновления"
	auto_download_box.toggled.connect(func(v): AuroraUpdate.set_auto_download(v))
	box.add_child(auto_download_box)

	var interval_row := HBoxContainer.new()
	interval_row.add_theme_constant_override("separation", 8)
	box.add_child(interval_row)
	var interval_label := Label.new()
	interval_label.text = "Проверять каждые, часов:"
	interval_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interval_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	interval_row.add_child(interval_label)
	interval = SpinBox.new()
	interval.min_value = 1
	interval.max_value = 168
	interval.step = 1
	interval.custom_minimum_size.x = 110
	interval.value_changed.connect(func(v): AuroraUpdate.set_check_interval_hours(int(v)))
	interval_row.add_child(interval)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if OS.get_name() == "Android":
		hint.text = "Android показывает системное подтверждение установки APK. AuroraFox проверяет пакет, но не обходит подтверждение ОС."
	else:
		hint.text = "Windows устанавливает обновление отдельным helper после закрытия AuroraFox и сохраняет возможность возврата при неудачном старте."
	box.add_child(hint)

	var actions := HFlowContainer.new()
	actions.alignment = FlowContainer.ALIGNMENT_END
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	box.add_child(actions)
	var check_button := Button.new()
	check_button.text = "Проверить сейчас"
	check_button.pressed.connect(func(): AuroraUpdate.check_for_updates(true))
	actions.add_child(check_button)
	apply_button = Button.new()
	apply_button.text = "Установить обновление"
	apply_button.disabled = true
	apply_button.pressed.connect(_apply_or_download)
	actions.add_child(apply_button)

func show_updates() -> void:
	if popup == null:
		return
	_fit_popup()
	popup.popup_centered()

func _fit_popup() -> void:
	var viewport := get_viewport().get_visible_rect().size
	popup.size = Vector2i(
		maxi(340, mini(620, int(viewport.x - 36.0))),
		maxi(460, mini(500, int(viewport.y - 36.0)))
	)

func _sync_settings(value: Dictionary) -> void:
	if auto_check_box == null:
		return
	auto_check_box.set_pressed_no_signal(bool(value.get("auto_check", true)))
	auto_download_box.set_pressed_no_signal(bool(value.get("auto_download", true)))
	interval.set_value_no_signal(float(value.get("check_interval_hours", 6)))

func _on_check_started() -> void:
	status_label.text = "Проверяю обновления…"
	details_label.text = "Проверяется подписанный stable-релиз."

func _on_update_available(info: Dictionary) -> void:
	var version := str(info.get("version", ""))
	status_label.text = "Доступна версия %s" % version
	details_label.text = str(info.get("notes", "Обновление готово к загрузке."))
	apply_button.disabled = false
	apply_button.text = "Загрузить обновление"
	if bool(info.get("mandatory", false)):
		show_updates()

func _on_no_update(version: String) -> void:
	status_label.text = "Установлена актуальная версия %s" % version
	details_label.text = "Новых stable-релизов нет."
	apply_button.disabled = true

func _on_download_started(info: Dictionary) -> void:
	status_label.text = "Загружаю AuroraFox %s…" % str(info.get("version", ""))
	details_label.text = "После загрузки пакет будет проверен перед установкой."
	apply_button.disabled = true

func _on_update_ready(info: Dictionary, _path: String) -> void:
	status_label.text = "Обновление проверено и готово"
	details_label.text = "Версия %s загружена. Можно установить сейчас." % str(info.get("version", ""))
	apply_button.disabled = false
	apply_button.text = "Установить сейчас"
	show_updates()

func _on_update_error(message: String) -> void:
	status_label.text = "Обновление не выполнено"
	details_label.text = message
	apply_button.disabled = AuroraUpdate.latest_info.is_empty()

func _on_update_applying(info: Dictionary) -> void:
	status_label.text = "Устанавливаю AuroraFox %s…" % str(info.get("version", ""))
	apply_button.disabled = true

func _apply_or_download() -> void:
	if AuroraUpdate.downloaded_path.is_empty():
		var download_result := await AuroraUpdate.download_update()
		if not download_result.get("ok", false):
			return
	var result := AuroraUpdate.apply_downloaded_update()
	if OS.get_name() == "Android" and bool(result.get("requires_permission", false)):
		status_label.text = "Нужно разрешение Android"
		details_label.text = str(result.get("message", "Разрешите установку из AuroraFox, затем нажмите «Установить сейчас» ещё раз."))
		apply_button.disabled = false
		apply_button.text = "Установить сейчас"
