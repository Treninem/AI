class_name SelfImprovementOverlay
extends Node

const HISTORY_PATH := "user://self_improvement_history.json"
const HISTORY_LIMIT := 50

var popup: PopupPanel
var goal_input: TextEdit
var status_label: Label
var proposal_view: RichTextLabel
var propose_button: Button
var verify_button: Button
var activate_button: Button
var extension_list: VBoxContainer
var confirmation: ConfirmationDialog

var current_proposal: Dictionary = {}
var staged_result: Dictionary = {}
var history: Array = []
var busy := false

func _ready() -> void:
	_load_history()
	_build_ui()
	call_deferred("_connect_signals")

func show_center() -> void:
	_refresh_extensions()
	_sync_platform_status()
	popup.popup_centered()

func _connect_signals() -> void:
	var improver := _improver()
	if improver != null:
		if not improver.improvement_stage.is_connected(_on_improvement_stage):
			improver.improvement_stage.connect(_on_improvement_stage)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	popup = PopupPanel.new()
	popup.size = Vector2i(820, 780)
	layer.add_child(popup)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	popup.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "Центр самоулучшения AuroraFox"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	var safety := Label.new()
	safety.text = "Горячее улучшение не заменяет ядро. AuroraFox создаёт новый модуль, проверяет полную копию проекта через Godot 4.7.1 и только после отдельного подтверждения может подключить его как ограниченное runtime-расширение."
	safety.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(safety)

	goal_input = TextEdit.new()
	goal_input.placeholder_text = "Например: добавь инструмент, который сравнивает две версии строки и возвращает различия…"
	goal_input.custom_minimum_size.y = 100
	goal_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(goal_input)

	var actions := HBoxContainer.new()
	box.add_child(actions)
	propose_button = Button.new()
	propose_button.text = "1. Создать предложение"
	propose_button.pressed.connect(_create_proposal)
	actions.add_child(propose_button)
	verify_button = Button.new()
	verify_button.text = "2. Проверить и подготовить"
	verify_button.disabled = true
	verify_button.pressed.connect(_verify_and_stage)
	actions.add_child(verify_button)
	activate_button = Button.new()
	activate_button.text = "3. Активировать"
	activate_button.disabled = true
	activate_button.pressed.connect(_request_activation)
	actions.add_child(activate_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)

	proposal_view = RichTextLabel.new()
	proposal_view.bbcode_enabled = true
	proposal_view.custom_minimum_size.y = 210
	proposal_view.fit_content = false
	box.add_child(proposal_view)

	box.add_child(HSeparator.new())
	var ext_title := Label.new()
	ext_title.text = "Runtime-расширения"
	ext_title.add_theme_font_size_override("font_size", 20)
	box.add_child(ext_title)
	var ext_hint := Label.new()
	ext_hint.text = "Активированное горячее расширение может добавлять только новые инструменты aurora_ext_* и не получает прямой доступ к OS, файлам, сети или настройкам движка."
	ext_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ext_hint)
	extension_list = VBoxContainer.new()
	extension_list.add_theme_constant_override("separation", 7)
	box.add_child(extension_list)

	box.add_child(HSeparator.new())
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(func(): popup.hide())
	box.add_child(close)

	confirmation = ConfirmationDialog.new()
	confirmation.title = "Активировать проверенное расширение?"
	confirmation.dialog_text = "Модуль уже прошёл sandbox/Godot-проверку. После активации его новые aurora_ext_* инструменты станут доступны агенту. Встроенные инструменты он заменить не может."
	confirmation.confirmed.connect(_activate_confirmed)
	layer.add_child(confirmation)

func _create_proposal() -> void:
	if busy: return
	var goal := goal_input.text.strip_edges()
	if goal.is_empty():
		status_label.text = "Сначала опиши, что AuroraFox должна улучшить."
		return
	var improver := _improver()
	if improver == null:
		status_label.text = "SelfImprover не подключён."
		return
	_set_busy(true)
	current_proposal.clear()
	staged_result.clear()
	verify_button.disabled = true
	activate_button.disabled = true
	proposal_view.clear()
	status_label.text = "Создаю одно небольшое безопасное расширение…"
	var result := await improver.propose_improvement(goal)
	if result.get("ok", false):
		current_proposal = result.get("proposal", {})
		_render_proposal()
		verify_button.disabled = OS.get_name() != "Windows"
		status_label.text = "Предложение создано. Следующий шаг — проверка полной копии проекта."
		_add_history("proposal", true, {"goal": goal, "path": current_proposal.get("path", ""), "reason": current_proposal.get("reason", "")})
	else:
		status_label.text = "Предложение отклонено: %s" % str(result.get("error", "unknown"))
		_add_history("proposal", false, {"goal": goal, "error": result.get("error", "unknown")})
	_set_busy(false)

func _verify_and_stage() -> void:
	if busy or current_proposal.is_empty(): return
	if OS.get_name() != "Windows":
		status_label.text = "Автоматическая Godot 4.7.1 проверка самоулучшений сейчас выполняется на Windows."
		return
	var improver := _improver()
	if improver == null: return
	_set_busy(true)
	verify_button.disabled = true
	activate_button.disabled = true
	status_label.text = "Создаю песочницу и проверяю проект…"
	var result := await improver.apply_generated_module(current_proposal)
	if result.get("ok", false):
		staged_result = result
		activate_button.disabled = false
		status_label.text = "Проверка пройдена. Модуль подготовлен, но ещё НЕ активирован."
		proposal_view.append_text("\n[color=#74ffb2][b]Godot 4.7.1: проверка пройдена[/b][/color]\nПодготовлено: %s\nSHA-256: %s\n" % [str(result.get("stage_path", "")), str(result.get("sha256", ""))])
		_add_history("verification", true, {"path": result.get("stage_path", ""), "sha256": result.get("sha256", "")})
	else:
		status_label.text = "Проверка не пройдена: %s" % str(result.get("error", "unknown"))
		verify_button.disabled = false
		_add_history("verification", false, {"stage": result.get("stage", ""), "error": result.get("error", "unknown")})
	_set_busy(false)

func _request_activation() -> void:
	if busy or staged_result.is_empty(): return
	confirmation.dialog_text = "Активировать проверенное расширение сейчас?\n\nФайл: %s\nSHA-256: %s\n\nОно сможет добавить только новые aurora_ext_* инструменты. Активацию можно отменить позже в этом окне." % [str(staged_result.get("stage_path", "")), str(staged_result.get("sha256", ""))]
	confirmation.popup_centered()

func _activate_confirmed() -> void:
	if busy or staged_result.is_empty(): return
	var manager := _extensions()
	if manager == null:
		status_label.text = "RuntimeExtensionManager не подключён."
		return
	_set_busy(true)
	status_label.text = "Компилирую и подключаю проверенное расширение…"
	var result := manager.activate_staged(str(staged_result.get("stage_path", "")), str(staged_result.get("sha256", "")))
	if result.get("ok", false):
		status_label.text = "Расширение активно: %s" % str(result.get("name", result.get("id", "")))
		activate_button.disabled = true
		_add_history("activation", true, {"id": result.get("id", ""), "tools": result.get("tools", [])})
		_refresh_extensions()
	else:
		status_label.text = "Активация отклонена: %s" % str(result.get("error", "unknown"))
		_add_history("activation", false, {"error": result.get("error", "unknown")})
	_set_busy(false)

func _render_proposal() -> void:
	proposal_view.clear()
	if current_proposal.is_empty(): return
	proposal_view.append_text("[b]Причина[/b]\n%s\n\n[b]Файл[/b]\n%s\n\n[b]Что будет проверено[/b]\n%s\n\n[b]Код[/b]\n[code]%s[/code]" % [
		str(current_proposal.get("reason", "")),
		str(current_proposal.get("path", "")),
		str(current_proposal.get("verification", "Godot 4.7.1 parse/import")),
		str(current_proposal.get("content", "")).replace("[", "[")
	])

func _on_improvement_stage(stage: String, details: Dictionary) -> void:
	if not busy: return
	status_label.text = {
		"workspace": "Создаю отдельную песочницу…",
		"import": "Копирую AuroraFox в песочницу…",
		"candidate": "Вношу кандидат только в рабочую копию…",
		"godot_test": "Запускаю Godot 4.7.1 headless-проверку…"
	}.get(stage, "Проверка: " + stage)
	if not details.is_empty(): status_label.tooltip_text = JSON.stringify(details)

func _refresh_extensions() -> void:
	if extension_list == null: return
	for child in extension_list.get_children(): child.queue_free()
	var manager := _extensions()
	if manager == null:
		var missing := Label.new()
		missing.text = "Менеджер runtime-расширений не подключён."
		extension_list.add_child(missing)
		return
	var items := manager.list_extensions()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "Активированных или сохранённых runtime-расширений пока нет."
		extension_list.add_child(empty)
		return
	for item in items:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.text = "%s • %s • %s" % [str(item.get("name", item.get("id", "extension"))), "активно" if bool(item.get("active", false)) else "выключено", ", ".join(PackedStringArray(item.get("tools", [])))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var id := str(item.get("id", ""))
		var toggle := Button.new()
		toggle.text = "Отключить" if bool(item.get("active", false)) else "Включить"
		toggle.pressed.connect(func(): _toggle_extension(id))
		row.add_child(toggle)
		var remove := Button.new()
		remove.text = "Удалить"
		remove.pressed.connect(func(): _remove_extension(id))
		row.add_child(remove)
		extension_list.add_child(row)

func _toggle_extension(id: String) -> void:
	var manager := _extensions()
	if manager == null: return
	var is_active := manager.active_instances.has(id)
	var result := manager.deactivate(id) if is_active else manager.enable(id)
	status_label.text = "Расширение %s" % ("отключено" if result.get("ok", false) and is_active else "включено" if result.get("ok", false) else "не изменено: " + str(result.get("error", "unknown")))
	_add_history("deactivate" if is_active else "enable", bool(result.get("ok", false)), {"id": id, "error": result.get("error", "")})
	_refresh_extensions()

func _remove_extension(id: String) -> void:
	var manager := _extensions()
	if manager == null: return
	var result := manager.remove_extension(id)
	status_label.text = "Расширение удалено." if result.get("ok", false) else "Не удалось удалить расширение: %s" % str(result.get("error", "unknown"))
	_add_history("remove", bool(result.get("ok", false)), {"id": id, "error": result.get("error", "")})
	_refresh_extensions()

func _sync_platform_status() -> void:
	if OS.get_name() == "Windows":
		status_label.text = "Готово. Автоматическая проверка использует отдельную песочницу и локальный Godot 4.7.1."
	else:
		status_label.text = "Создавать предложения можно, но автоматическая Godot 4.7.1 проверка горячих улучшений сейчас выполняется на Windows."
	verify_button.disabled = current_proposal.is_empty() or OS.get_name() != "Windows"
	activate_button.disabled = staged_result.is_empty()

func _set_busy(value: bool) -> void:
	busy = value
	propose_button.disabled = value
	if value:
		verify_button.disabled = true
		activate_button.disabled = true
	else:
		verify_button.disabled = current_proposal.is_empty() or OS.get_name() != "Windows"
		activate_button.disabled = staged_result.is_empty()

func _improver() -> SelfImprover:
	var main := get_parent()
	if main == null: return null
	var value = main.get("improver")
	return value as SelfImprover

func _extensions() -> RuntimeExtensionManager:
	var main := get_parent()
	if main == null: return null
	return main.get_node_or_null("RuntimeExtensions") as RuntimeExtensionManager

func _add_history(kind: String, ok: bool, details: Dictionary) -> void:
	history.push_front({"time": Time.get_datetime_string_from_system(true), "kind": kind, "ok": ok, "details": details})
	if history.size() > HISTORY_LIMIT: history.resize(HISTORY_LIMIT)
	_save_history()

func _load_history() -> void:
	var f := FileAccess.open(HISTORY_PATH, FileAccess.READ)
	if f == null: return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and parsed.get("history", []) is Array:
		history = parsed.get("history", [])

func _save_history() -> void:
	var f := FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"history": history}, "  "))
		f.close()
