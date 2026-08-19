class_name AuroraUpdateOverlay
extends Node

const ICON_UPDATE: Texture2D = preload("res://assets/ui/icon_update.svg")

var layer: CanvasLayer
var open_button: Button
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

func _style(fill: Color, border: Color, radius := 11) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _apply_button(button: Button, active := false) -> void:
	var border := Color(0.30, 0.34, 0.46, 0.58)
	if active:
		border = Color(0.39, 1.0, 0.62, 0.74)
	button.add_theme_stylebox_override("normal", _style(Color(0.055, 0.066, 0.10, 0.96), border))
	button.add_theme_stylebox_override("hover", _style(Color(0.10, 0.12, 0.18, 1.0), border))
	button.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.11, 0.22, 1.0), Color(0.66, 0.54, 1.0, 0.86)))
	button.add_theme_stylebox_override("focus", _style(Color(0.10, 0.12, 0.18, 1.0), Color(0.66, 0.54, 1.0, 0.86)))
	button.add_theme_color_override("font_color", Color("eef5ff"))
	button.expand_icon = true
	button.icon_max_width = 18

func _build_ui() -> void:
	var main := get_parent()
	var host := main.find_child("MainHeaderActions", true, false) as HBoxContainer if main != null else null
	if host != null:
		open_button = Button.new()
		open_button.name = "UpdateButton"
		open_button.icon = ICON_UPDATE
		open_button.tooltip_text = "Обновления AuroraFox"
		open_button.custom_minimum_size = Vector2(40, 38)
		open_button.pressed.connect(func(): popup.popup_centered())
		_apply_button(open_button, false)
		host.add_child(open_button)
	else:
		layer = CanvasLayer.new()
		layer.layer = 75
		add_child(layer)
		open_button = Button.new()
		open_button.icon = ICON_UPDATE
		open_button.tooltip_text = "Обновления AuroraFox"
		open_button.custom_minimum_size = Vector2(40, 38)
		open_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		open_button.position = Vector2(-56, 14)
		open_button.pressed.connect(func(): popup.popup_centered())
		_apply_button(open_button, false)
		layer.add_child(open_button)

	popup = PopupPanel.new()
	popup.size = Vector2i(620, 500)
	if layer != null:
		layer.add_child(popup)
	elif main != null:
		main.add_child(popup)
	else:
		add_child(popup)

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
	box.add_child(status_label)

	details_label = Label.new()
	details_label.text = "Stable-канал. Пакеты проверяются SHA-256 перед установкой."
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
	box.add_child(interval_row)
	var interval_label := Label.new()
	interval_label.text = "Проверять каждые, часов:"
	interval_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interval_row.add_child(interval_label)
	interval = SpinBox.new()
	interval.min_value = 1
	interval.max_value = 168
	interval.step = 1
	interval.value_changed.connect(func(v): AuroraUpdate.set_check_interval_hours(int(v)))
	interval_row.add_child(interval)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if OS.get_name() == "Android":
		hint.text = "Android показывает системное подтверждение установки APK. AuroraFox проверяет и скачивает пакет, но не обходит подтверждение ОС."
	else:
		hint.text = "Windows-обновление устанавливается отдельным helper после закрытия AuroraFox. Если новая версия не проходит стартовую проверку, helper возвращает предыдущую версию."
	box.add_child(hint)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
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

func _sync_settings(value: Dictionary) -> void:
	if auto_check_box == null:
		return
	auto_check_box.set_pressed_no_signal(bool(value.get("auto_check", true)))
	auto_download_box.set_pressed_no_signal(bool(value.get("auto_download", true)))
	interval.set_value_no_signal(float(value.get("check_interval_hours", 6)))

func _on_check_started() -> void:
	status_label.text = "Проверяю обновления…"
	details_label.text = "Запрос к стабильному каналу GitHub Releases."

func _on_update_available(info: Dictionary) -> void:
	var version := str(info.get("version", ""))
	open_button.tooltip_text = "Доступно обновление %s" % version
	_apply_button(open_button, true)
	status_label.text = "Доступна версия %s" % version
	details_label.text = str(info.get("notes", "Обновление готово к загрузке."))
	apply_button.disabled = false
	apply_button.text = "Загрузить обновление"
	if bool(info.get("mandatory", false)):
		popup.popup_centered()

func _on_no_update(version: String) -> void:
	open_button.tooltip_text = "AuroraFox %s — актуальная версия" % version
	_apply_button(open_button, false)
	status_label.text = "Установлена актуальная версия %s" % version
	details_label.text = "Новых stable-релизов нет."
	apply_button.disabled = true

func _on_download_started(info: Dictionary) -> void:
	status_label.text = "Загружаю AuroraFox %s…" % str(info.get("version", ""))
	details_label.text = "После загрузки пакет будет проверен SHA-256."
	apply_button.disabled = true

func _on_update_ready(info: Dictionary, _path: String) -> void:
	open_button.tooltip_text = "Обновление %s готово" % str(info.get("version", ""))
	_apply_button(open_button, true)
	status_label.text = "Обновление проверено и готово"
	details_label.text = "Версия %s загружена. Можно установить сейчас." % str(info.get("version", ""))
	apply_button.disabled = false
	apply_button.text = "Установить сейчас"
	popup.popup_centered()

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
	var apply_result := AuroraUpdate.apply_downloaded_update()
	if OS.get_name() == "Android" and bool(apply_result.get("requires_permission", false)):
		status_label.text = "Нужно разрешение Android"
		details_label.text = str(apply_result.get("message", "Разрешите установку из AuroraFox, затем нажмите «Установить сейчас» ещё раз."))
		apply_button.disabled = false
		apply_button.text = "Установить сейчас"
