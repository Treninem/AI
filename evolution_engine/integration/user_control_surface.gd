class_name AuroraEvolutionUserControlSurface
extends Node

signal action_finished(action: String, result: Dictionary)

const MIN_MUTATIONS := 3
const MAX_MUTATIONS := 10

var runtime
var _pending_action := ""
var _pending_payload: Dictionary = {}
var _busy := false

var _layer: CanvasLayer
var _open_button: Button
var _popup: PopupPanel
var _confirmation: ConfirmationDialog
var _level_selector: OptionButton
var _goal_input: LineEdit
var _mode_selector: OptionButton
var _target_input: LineEdit
var _population_input: SpinBox
var _status_label: Label
var _result_view: RichTextLabel
var _apply_button: Button
var _run_button: Button
var _end_button: Button

func _ready() -> void:
	runtime = get_parent()
	_build_ui()
	call_deferred("refresh_status")

func show_center() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_popup.size = Vector2i(
		mini(760, maxi(320, int(viewport_size.x) - 32)),
		mini(760, maxi(420, int(viewport_size.y) - 32))
	)
	refresh_status()
	_popup.popup_centered()

func status() -> Dictionary:
	return {
		"ok": runtime != null,
		"busy": _busy,
		"pending_confirmation": not _pending_action.is_empty(),
		"pending_action": _pending_action,
		"runtime": _runtime_status()
	}

func request_session_level(level: int) -> Dictionary:
	if _busy:
		return _error("busy", "Evolution control surface is busy")
	if level < AuroraEvolutionPolicy.LEVEL_ANALYSIS or level > AuroraEvolutionPolicy.LEVEL_VERIFIED_ACTIVATION:
		return _error("permission", "Evolution permission level must be within 0..4")
	if level == AuroraEvolutionPolicy.LEVEL_ANALYSIS:
		return end_session_from_user()
	var label := _level_name(level)
	return _stage_confirmation(
		"session_level",
		{"level": level},
		"Разрешить %s только для текущей сессии?\n\nРазрешение не сохраняется после закрытия AuroraFox. Уровни 2–4 включают managed mode и отключают прежнюю автоматическую hot-активацию." % label
	)

func request_experiment(goal: String, mode: String, requested_target: String, requested_count: int) -> Dictionary:
	if _busy:
		return _error("busy", "Evolution control surface is busy")
	var clean_goal := goal.strip_edges()
	var clean_mode := mode.strip_edges().to_lower()
	if clean_goal.is_empty():
		return _error("goal", "Укажите цель эксперимента")
	if clean_mode not in ["hot", "core"]:
		return _error("cycle_mode", "Evolution cycle mode must be hot or core")
	if requested_count < MIN_MUTATIONS or requested_count > MAX_MUTATIONS:
		return _error("population", "Mutation population must be within 3..10")
	var current := _runtime_status()
	if not bool(current.get("managed_session", false)) or int(current.get("session_permission_level", 0)) < AuroraEvolutionPolicy.LEVEL_SANDBOX_EXPERIMENT:
		return _error("permission", "Сначала подтвердите managed session уровня 2 или выше")
	return _stage_confirmation(
		"experiment",
		{
			"goal": clean_goal,
			"mode": clean_mode,
			"requested_target": requested_target.strip_edges(),
			"requested_count": requested_count
		},
		"Запустить изолированный %s-эксперимент с %d независимыми мутациями?\n\nЦель: %s\n\nНи одна мутация не получит release authority. Победитель останется внутри защищённого Evolution lifecycle." % [clean_mode, requested_count, clean_goal]
	)

func cancel_pending_action() -> Dictionary:
	var cancelled := _pending_action
	_clear_pending()
	if _confirmation != null:
		_confirmation.hide()
	return {"ok": true, "cancelled": cancelled, "executed": false}

func confirm_pending_action() -> Dictionary:
	if _busy:
		return _error("busy", "Evolution control surface is busy")
	if _pending_action.is_empty():
		return _error("user_confirmation", "No pending user-confirmed Evolution action")
	var action := _pending_action
	var payload := _pending_payload.duplicate(true)
	_clear_pending()
	if _confirmation != null:
		_confirmation.hide()
	_set_busy(true)
	var result: Dictionary
	if action == "session_level":
		result = _apply_confirmed_level(int(payload.get("level", 0)))
	elif action == "experiment":
		result = await runtime.run_cycle_from_user(
			str(payload.get("goal", "")),
			str(payload.get("mode", "hot")),
			str(payload.get("requested_target", "")),
			int(payload.get("requested_count", 5)),
			true
		)
	else:
		result = _error("action", "Unknown pending Evolution action")
	_set_busy(false)
	_render_result(action, result)
	action_finished.emit(action, result)
	return result

func end_session_from_user() -> Dictionary:
	if _busy:
		return _error("busy", "Evolution control surface is busy")
	if runtime == null:
		return _error("runtime", "Evolution runtime is unavailable")
	_clear_pending()
	var current := _runtime_status()
	var result: Dictionary
	if bool(current.get("managed_session", false)):
		result = runtime.end_managed_session()
	else:
		result = runtime.authorize_session_level(AuroraEvolutionPolicy.LEVEL_ANALYSIS, true)
	_render_result("end_session", result)
	action_finished.emit("end_session", result)
	return result

func refresh_status() -> Dictionary:
	var current := _runtime_status()
	if _status_label != null:
		_status_label.text = "Runtime: %s | Level %d — %s | managed=%s | session-only | release authority=false" % [
			"подключён" if bool(current.get("bound", false)) else "ожидание foundation",
			int(current.get("session_permission_level", 0)),
			_level_name(int(current.get("session_permission_level", 0))),
			str(bool(current.get("managed_session", false)))
		]
	_update_actions(current)
	return current

func _apply_confirmed_level(level: int) -> Dictionary:
	if runtime == null:
		return _error("runtime", "Evolution runtime is unavailable")
	if level >= AuroraEvolutionPolicy.LEVEL_SANDBOX_EXPERIMENT:
		return runtime.begin_managed_session(level, true)
	return runtime.authorize_session_level(level, true)

func _stage_confirmation(action: String, payload: Dictionary, message: String) -> Dictionary:
	if runtime == null:
		return _error("runtime", "Evolution runtime is unavailable")
	_pending_action = action
	_pending_payload = payload.duplicate(true)
	_confirmation.dialog_text = message
	var viewport_size := get_viewport().get_visible_rect().size
	_confirmation.popup_centered(Vector2i(
		mini(620, maxi(300, int(viewport_size.x) - 32)),
		mini(360, maxi(260, int(viewport_size.y) - 32))
	))
	return {"ok": false, "pending_confirmation": true, "action": action, "executed": false}

func _clear_pending() -> void:
	_pending_action = ""
	_pending_payload.clear()

func _runtime_status() -> Dictionary:
	if runtime == null or not runtime.has_method("status"):
		return {"ok": false, "bound": false, "session_permission_level": 0, "managed_session": false}
	var value = runtime.status()
	return value if value is Dictionary else {"ok": false, "bound": false}

func _set_busy(value: bool) -> void:
	_busy = value
	_update_actions(_runtime_status())

func _update_actions(current: Dictionary) -> void:
	if _apply_button != null:
		_apply_button.disabled = _busy or not bool(current.get("bound", false))
	if _run_button != null:
		_run_button.disabled = _busy or not bool(current.get("managed_session", false)) or int(current.get("session_permission_level", 0)) < AuroraEvolutionPolicy.LEVEL_SANDBOX_EXPERIMENT
	if _end_button != null:
		_end_button.disabled = _busy

func _render_result(action: String, result: Dictionary) -> void:
	refresh_status()
	if _result_view != null:
		_result_view.text = "%s\n%s" % [action, JSON.stringify(result, "  ")]

func _error(stage: String, message: String) -> Dictionary:
	var result := {"ok": false, "stage": stage, "error": message}
	if _status_label != null:
		_status_label.text = message
	return result

func _level_name(level: int) -> String:
	return {
		0: "Анализ",
		1: "Предложения",
		2: "Sandbox-эксперименты",
		3: "Подготовка promotion handoff",
		4: "Проверенная активация"
	}.get(level, "Неизвестный уровень")

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 121
	add_child(_layer)

	_open_button = Button.new()
	_open_button.text = "Evolution Engine"
	_open_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_open_button.position = Vector2(-210, -64)
	_open_button.size = Vector2(194, 48)
	_open_button.pressed.connect(show_center)
	_layer.add_child(_open_button)

	_popup = PopupPanel.new()
	_layer.add_child(_popup)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	_popup.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "Контролируемая эволюция AuroraFox"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var safety := Label.new()
	safety.text = "Все разрешения действуют только в текущей сессии. Каждый эксперимент требует отдельного подтверждения. Evolution Engine не может публиковать release или обходить rollback, master stop и update guard."
	safety.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	safety.modulate = Color(0.82, 0.9, 1.0)
	box.add_child(safety)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status_label)

	_level_selector = OptionButton.new()
	for level in range(5):
		_level_selector.add_item("Level %d — %s" % [level, _level_name(level)], level)
	box.add_child(_level_selector)
	var level_actions := VBoxContainer.new()
	box.add_child(level_actions)
	_apply_button = Button.new()
	_apply_button.text = "Подтвердить уровень для сессии"
	_apply_button.pressed.connect(func(): request_session_level(_level_selector.get_selected_id()))
	level_actions.add_child(_apply_button)
	_end_button = Button.new()
	_end_button.text = "Завершить сессию и вернуть Level 0"
	_end_button.pressed.connect(end_session_from_user)
	level_actions.add_child(_end_button)

	box.add_child(HSeparator.new())
	_goal_input = LineEdit.new()
	_goal_input.placeholder_text = "Цель улучшения"
	box.add_child(_goal_input)
	_mode_selector = OptionButton.new()
	_mode_selector.add_item("Hot extension — sandbox", 0)
	_mode_selector.add_item("Core candidate — Windows verification", 1)
	box.add_child(_mode_selector)
	_target_input = LineEdit.new()
	_target_input.placeholder_text = "Core target (необязательно; используется только в core mode)"
	box.add_child(_target_input)
	_population_input = SpinBox.new()
	_population_input.min_value = MIN_MUTATIONS
	_population_input.max_value = MAX_MUTATIONS
	_population_input.step = 1
	_population_input.value = 5
	box.add_child(_population_input)
	_run_button = Button.new()
	_run_button.text = "Подтвердить и запустить sandbox-эксперимент"
	_run_button.pressed.connect(func():
		request_experiment(
			_goal_input.text,
			"hot" if _mode_selector.selected == 0 else "core",
			_target_input.text,
			int(_population_input.value)
		)
	)
	box.add_child(_run_button)

	_result_view = RichTextLabel.new()
	_result_view.custom_minimum_size.y = 220
	_result_view.selection_enabled = true
	box.add_child(_result_view)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(func(): _popup.hide())
	box.add_child(close)

	_confirmation = ConfirmationDialog.new()
	_confirmation.title = "Подтверждение Evolution Engine"
	_confirmation.ok_button_text = "Подтвердить"
	_confirmation.cancel_button_text = "Отмена"
	_confirmation.confirmed.connect(_on_confirmation_confirmed)
	_confirmation.canceled.connect(cancel_pending_action)
	_layer.add_child(_confirmation)

func _on_confirmation_confirmed() -> void:
	await confirm_pending_action()
