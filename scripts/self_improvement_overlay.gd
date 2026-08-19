class_name SelfImprovementOverlay
extends Node

const HISTORY_PATH := "user://self_improvement_history.json"
const HISTORY_LIMIT := 100

var popup: PopupPanel
var goal_input: TextEdit
var status_label: Label
var proposal_view: RichTextLabel
var tournament_button: Button
var extension_list: VBoxContainer

var history: Array = []
var busy := false
var tournament_requested := 0
var tournament_completed := 0
var tournament_verified := 0

func _ready() -> void:
	_load_history()
	_build_ui()
	call_deferred("_connect_signals")

func show_center() -> void:
	_refresh_extensions()
	_sync_autonomy_status()
	popup.popup_centered()

func _connect_signals() -> void:
	var improver := _improver()
	if improver != null:
		if not improver.improvement_stage.is_connected(_on_improvement_stage):
			improver.improvement_stage.connect(_on_improvement_stage)
		if not improver.mutation_population_started.is_connected(_on_mutation_population_started):
			improver.mutation_population_started.connect(_on_mutation_population_started)
		if not improver.mutation_candidate_completed.is_connected(_on_mutation_candidate_completed):
			improver.mutation_candidate_completed.connect(_on_mutation_candidate_completed)
		if not improver.mutation_tournament_completed.is_connected(_on_mutation_tournament_completed):
			improver.mutation_tournament_completed.connect(_on_mutation_tournament_completed)
	var coordinator := _coordinator()
	if coordinator != null:
		if not coordinator.autonomous_cycle_completed.is_connected(_on_autonomous_cycle_completed):
			coordinator.autonomous_cycle_completed.connect(_on_autonomous_cycle_completed)
		if not coordinator.autonomous_cycle_failed.is_connected(_on_autonomous_cycle_failed):
			coordinator.autonomous_cycle_failed.connect(_on_autonomous_cycle_failed)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	popup = PopupPanel.new()
	popup.size = Vector2i(860, 800)
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
	title.text = "Эволюция AuroraFox"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	var autonomous := Label.new()
	autonomous.text = "Автономный режим включён: AuroraFox сама собирает знания, создаёт 3–10 разных мутаций, проверяет каждую в отдельной копии, проводит соревнование, повторно тестирует победителя и автоматически активирует его без запроса подтверждения."
	autonomous.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(autonomous)

	var safety := Label.new()
	safety.text = "Непрошедшая тесты мутация не активируется. Горячие мутации работают как ограниченные RefCounted-расширения aurora_ext_* без прямого доступа к OS, файлам, сети и системным singleton API."
	safety.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	safety.modulate = Color(0.82, 0.88, 0.95)
	box.add_child(safety)

	goal_input = TextEdit.new()
	goal_input.placeholder_text = "Необязательно: задай цель для внеочередного турнира. Если поле пустое — AuroraFox сама выберет цель по состоянию, ошибкам и знаниям."
	goal_input.custom_minimum_size.y = 92
	goal_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(goal_input)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(actions)
	tournament_button = Button.new()
	tournament_button.text = "Запустить внеочередной турнир сейчас"
	tournament_button.pressed.connect(_run_tournament_now)
	actions.add_child(tournament_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 17)
	box.add_child(status_label)

	proposal_view = RichTextLabel.new()
	proposal_view.bbcode_enabled = false
	proposal_view.custom_minimum_size.y = 260
	proposal_view.fit_content = false
	proposal_view.selection_enabled = true
	box.add_child(proposal_view)

	box.add_child(HSeparator.new())
	var ext_title := Label.new()
	ext_title.text = "Активные и сохранённые победители"
	ext_title.add_theme_font_size_override("font_size", 20)
	box.add_child(ext_title)
	var ext_hint := Label.new()
	ext_hint.text = "Победители сохраняются между запусками. Здесь можно вручную отключить или удалить конкретное расширение для отката, но подтверждение перед автоматической эволюцией не требуется."
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

func _run_tournament_now() -> void:
	if busy: return
	var improver := _improver()
	var coordinator := _coordinator()
	if improver == null or coordinator == null:
		status_label.text = "Автономный контур ещё не подключён."
		return
	if OS.get_name() != "Windows":
		status_label.text = "Полная sandbox/Godot-проверка мутаций сейчас выполняется на Windows; Android продолжает использовать уже проверенные релизные и runtime-компоненты."
		return
	_set_busy(true)
	proposal_view.clear()
	var custom_goal := goal_input.text.strip_edges()
	if custom_goal.is_empty():
		status_label.text = "Запускаю внеочередной полный автономный цикл…"
		var cycle: Dictionary = await coordinator.run_autonomous_cycle()
		_render_cycle(cycle)
		_add_history("manual_autonomous_cycle", bool(cycle.get("ok", false)), _compact(cycle))
	else:
		var population := clampi(int(coordinator.mutation_population_size), SelfImprover.MIN_MUTATIONS, SelfImprover.MAX_MUTATIONS)
		status_label.text = "Запускаю турнир из %d+ разных мутаций для заданной цели…" % population
		var tournament: Dictionary = await improver.run_mutation_tournament(custom_goal, population)
		if tournament.get("ok", false):
			var manager := _extensions()
			if manager == null:
				tournament = {"ok": false, "error": "RuntimeExtensionManager не подключён", "tournament": tournament}
			else:
				var activation := manager.activate_staged(str(tournament.get("stage_path", "")), str(tournament.get("sha256", "")))
				tournament["activation"] = activation
				tournament["mutation_applied"] = bool(activation.get("ok", false))
		_render_tournament(tournament)
		_add_history("manual_tournament", bool(tournament.get("ok", false)), _compact(tournament))
	_refresh_extensions()
	_set_busy(false)

func _on_mutation_population_started(goal: String, requested: int) -> void:
	tournament_requested = requested
	tournament_completed = 0
	tournament_verified = 0
	status_label.text = "Эволюция: создаю %d независимых мутаций. Цель: %s" % [requested, goal]
	proposal_view.text = "Турнир запущен\nЦель: %s\nПлан: 3–10 мутаций → отдельный Godot-тест каждой → соревнование → повторный тест победителя → автоматическая активация.\n" % goal
	_add_history("population_started", true, {"goal": goal, "requested": requested})

func _on_mutation_candidate_completed(candidate: Dictionary) -> void:
	tournament_completed += 1
	if bool(candidate.get("verified", false)):
		tournament_verified += 1
	status_label.text = "Эволюция: проверено %d/%d, прошли тесты %d. Последняя: %s — %s" % [
		tournament_completed,
		maxi(tournament_requested, tournament_completed),
		tournament_verified,
		str(candidate.get("mutation_tag", "mutation")),
		"допущена" if bool(candidate.get("verified", false)) else "выбыла"
	]
	proposal_view.append_text("\n%s | %s | verified=%s | score=%.2f\n%s\n" % [
		str(candidate.get("mutation_tag", "mutation")),
		str(candidate.get("strategy", "")),
		str(candidate.get("verified", false)),
		float(candidate.get("score", 0.0)),
		str(candidate.get("reason", "")).substr(0, 700)
	])

func _on_mutation_tournament_completed(result: Dictionary) -> void:
	_render_tournament(result)
	_add_history("tournament", bool(result.get("ok", false)), _compact(result))

func _on_improvement_stage(stage: String, details: Dictionary) -> void:
	status_label.text = {
		"mutation_population": "Эволюция: создаю разные мутации…",
		"candidate_test": "Эволюция: запускаю отдельный тест очередной мутации…",
		"workspace": "Эволюция: создаю отдельную песочницу…",
		"import": "Эволюция: копирую AuroraFox в песочницу…",
		"candidate": "Эволюция: вношу мутацию только в рабочую копию…",
		"godot_test": "Эволюция: Godot 4.7.1 тестирует мутацию…",
		"competition": "Эволюция: прошедшие мутации соревнуются…",
		"winner_final_test": "Эволюция: победитель проходит финальный повторный тест…"
	}.get(stage, "Эволюция: " + stage)
	if not details.is_empty(): status_label.tooltip_text = JSON.stringify(details)

func _on_autonomous_cycle_completed(report: Dictionary) -> void:
	_render_cycle(report)
	_add_history("autonomous_cycle", bool(report.get("ok", false)), _compact(report))
	_refresh_extensions()

func _on_autonomous_cycle_failed(report: Dictionary) -> void:
	status_label.text = "Автономный цикл не применил изменение: %s" % str(report.get("error", report.get("stage", "проверка совместимости")))
	proposal_view.text = JSON.stringify(_compact(report), "  ")
	_add_history("autonomous_cycle_failed", false, _compact(report))

func _render_tournament(result: Dictionary) -> void:
	if result.is_empty(): return
	var ok := bool(result.get("ok", false))
	var applied := bool(result.get("mutation_applied", result.get("staged", false)))
	var winner: Dictionary = result.get("winner", {}) if result.get("winner", {}) is Dictionary else {}
	if ok:
		status_label.text = "Турнир завершён: %d мутаций, тесты прошли %d. Победитель %s. %s" % [
			int(result.get("population_size", 0)),
			int(result.get("verified_count", 0)),
			str(winner.get("mutation_tag", winner.get("path", "winner"))),
			"Победитель активирован автоматически." if applied else "Победитель проверен и подготовлен к автоматической активации."
		]
	else:
		status_label.text = "Турнир отклонён — обновление не применено: %s" % str(result.get("error", "не прошёл обязательные тесты"))
	var lines: Array[String] = []
	lines.append("Результат турнира")
	lines.append("ok=%s population=%s verified=%s" % [str(ok), str(result.get("population_size", 0)), str(result.get("verified_count", 0))])
	if not winner.is_empty():
		lines.append("Победитель: %s" % str(winner.get("path", "")))
		lines.append("Стратегия: %s" % str(winner.get("strategy", "")))
		lines.append("Итоговый score: %.2f" % float(winner.get("score", 0.0)))
		lines.append("Причина: %s" % str(winner.get("reason", "")))
	lines.append("\nТаблица соревнования:")
	for item in result.get("scoreboard", []):
		if item is Dictionary:
			lines.append("%s | %.2f | base %.2f | judge %.2f | %s" % [
				str(item.get("mutation_tag", "mutation")),
				float(item.get("score", 0.0)),
				float(item.get("base_score", 0.0)),
				float(item.get("judge_score", 0.0)),
				str(item.get("strategy", ""))
			])
	proposal_view.text = "\n".join(lines)

func _render_cycle(report: Dictionary) -> void:
	if report.is_empty(): return
	var tournament = report.get("tournament", {})
	if tournament is Dictionary and not tournament.is_empty():
		var view: Dictionary = tournament.duplicate(true)
		view["mutation_applied"] = bool(report.get("mutation_applied", false))
		if report.get("activation", {}) is Dictionary:
			view["activation"] = report.get("activation", {})
		_render_tournament(view)
		return
	status_label.text = "Автономный цикл завершён. Обучение=%s, турнир=%s, обновление=%s" % [
		str(report.get("research_attempted", false)),
		str(report.get("mutation_attempted", false)),
		str(report.get("mutation_applied", false))
	]
	proposal_view.text = JSON.stringify(_compact(report), "  ")

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
		empty.text = "Победителей пока нет — первый автономный турнир запускается после старта AuroraFox."
		extension_list.add_child(empty)
		return
	for item in items:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		var tool_names: PackedStringArray = PackedStringArray(item.get("tools", []))
		label.text = "%s • %s • %s" % [str(item.get("name", item.get("id", "extension"))), "активно" if bool(item.get("active", false)) else "выключено", ", ".join(tool_names)]
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
	var was_active := manager.active_instances.has(id)
	var result := manager.deactivate(id) if was_active else manager.enable(id)
	if result.get("ok", false):
		status_label.text = "Расширение отключено вручную." if was_active else "Расширение включено вручную."
	else:
		status_label.text = "Не удалось изменить расширение: %s" % str(result.get("error", "unknown"))
	_add_history("deactivate" if was_active else "enable", bool(result.get("ok", false)), {"id": id, "error": result.get("error", "")})
	_refresh_extensions()

func _remove_extension(id: String) -> void:
	var manager := _extensions()
	if manager == null: return
	var result := manager.remove_extension(id)
	if result.get("ok", false):
		status_label.text = "Расширение удалено вручную."
	else:
		status_label.text = "Не удалось удалить расширение: %s" % str(result.get("error", "unknown"))
	_add_history("remove", bool(result.get("ok", false)), {"id": id, "error": result.get("error", "")})
	_refresh_extensions()

func _sync_autonomy_status() -> void:
	var coordinator := _coordinator()
	if coordinator == null:
		status_label.text = "Автономный координатор ещё не подключён."
		return
	var platform_note := "Полный эволюционный sandbox активен." if OS.get_name() == "Windows" else "На этой платформе горячая мутация ограничена текущими возможностями runtime."
	status_label.text = "Автономность=%s • цикл каждые %.0f с • турнир %d–10 мутаций • %s" % [
		str(coordinator.autonomous_enabled),
		float(coordinator.cycle_interval_seconds),
		maxi(SelfImprover.MIN_MUTATIONS, int(coordinator.mutation_population_size)),
		platform_note
	]

func _set_busy(value: bool) -> void:
	busy = value
	tournament_button.disabled = value

func _improver() -> SelfImprover:
	var main := get_parent()
	if main == null: return null
	var value = main.get("improver")
	return value as SelfImprover

func _extensions() -> RuntimeExtensionManager:
	var main := get_parent()
	if main == null: return null
	return main.get_node_or_null("RuntimeExtensions") as RuntimeExtensionManager

func _coordinator() -> AuroraAutonomousCoordinator:
	var main := get_parent()
	if main == null: return null
	return main.get_node_or_null("AutonomousCoordinator") as AuroraAutonomousCoordinator

func _compact(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = value.duplicate(true)
		for key in out.keys():
			if key in ["content", "proposal"]:
				var text := str(out[key])
				if text.length() > 2500: out[key] = text.substr(0, 2500) + "…"
		return out
	if value is Array:
		var arr: Array = value
		return arr.slice(0, mini(arr.size(), 30))
	return value

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
