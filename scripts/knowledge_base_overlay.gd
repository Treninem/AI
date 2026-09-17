class_name KnowledgeBaseOverlay
extends Node

var popup: PopupPanel
var stats_label: Label
var progress_label: Label
var sources_box: VBoxContainer
var file_picker: FileDialog
var folder_picker: FileDialog
var import_busy := false
var import_cancel_requested := false
var add_files_button: Button
var add_folder_button: Button
var compact_button: Button
var refresh_button: Button
var cancel_import_button: Button
const MAX_FOLDER_FILES := 750

func _ready() -> void:
	_build_ui()

func show_knowledge_base() -> void:
	_refresh()
	_fit_popup()
	popup.popup_centered()

func _fit_popup() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var gap := 28.0 if OS.get_name() == "Android" else 48.0
	popup.size = Vector2i(
		maxi(360, mini(900, int(viewport.x - gap))),
		maxi(520, mini(760, int(viewport.y - gap)))
	)

func _main_ai() -> AIClient:
	var main := get_parent()
	if main == null:
		return null
	var value = main.get("ai")
	return value if value is AIClient else null

func _attachments() -> AttachmentManager:
	var main := get_parent()
	if main == null:
		return null
	var value = main.get("attachments")
	return value if value is AttachmentManager else null

func _apply_main_button(button: Button, danger := false) -> void:
	var main := get_parent()
	if main != null and main.has_method("_apply_button"):
		main.call("_apply_button", button, false, danger, false)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.022, 0.027, 0.048, 0.995)
	style.border_color = Color(0.38, 0.61, 0.92, 0.78)
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.72)
	style.shadow_size = 18
	return style

func _source_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.047, 0.075, 0.96)
	style.border_color = Color(0.25, 0.31, 0.45, 0.62)
	style.set_border_width_all(1)
	style.set_corner_radius_all(11)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	return style

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 112
	add_child(layer)
	popup = PopupPanel.new()
	popup.name = "KnowledgeBasePopup"
	popup.size = Vector2i(900, 760)
	popup.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(popup)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	popup.add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.name = "KnowledgeHeader"
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	var title := Label.new()
	title.text = "База знаний AuroraFox"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 26)
	header.add_child(title)
	var close := Button.new()
	close.name = "KnowledgeCloseButton"
	close.text = "Готово"
	close.custom_minimum_size = Vector2(96, 42)
	close.pressed.connect(func(): popup.hide())
	_apply_main_button(close)
	header.add_child(close)

	var intro := Label.new()
	intro.text = "Добавляйте JSON, TXT/Markdown/CSV/YAML/XML, Word, PDF, Excel, PowerPoint, ODT/ODS, RTF/EPUB и исходный код. AuroraFox локально извлекает содержимое и сохраняет полезные знания, факты, шаблоны, алгоритмы, примеры и навыки."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(intro)
	var safety := Label.new()
	safety.text = "Импортированный материал — данные Core Knowledge. Код и инструкции из файлов не выполняются автоматически и не получают системных полномочий. Извлечение документов для обучения работает локально и не требует Ollama."
	safety.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	safety.add_theme_font_size_override("font_size", 12)
	safety.add_theme_color_override("font_color", Color("9fabc0"))
	root.add_child(safety)

	var actions := HFlowContainer.new()
	actions.name = "KnowledgeActions"
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	root.add_child(actions)
	add_files_button = Button.new()
	add_files_button.text = "Добавить файлы…"
	add_files_button.pressed.connect(func(): file_picker.popup_centered_ratio(0.78))
	_apply_main_button(add_files_button)
	actions.add_child(add_files_button)
	add_folder_button = Button.new()
	add_folder_button.text = "Добавить папку…"
	add_folder_button.visible = OS.get_name() == "Windows"
	add_folder_button.pressed.connect(func(): folder_picker.popup_centered_ratio(0.78))
	_apply_main_button(add_folder_button)
	actions.add_child(add_folder_button)
	compact_button = Button.new()
	compact_button.text = "Очистить дубликаты"
	compact_button.pressed.connect(_compact)
	_apply_main_button(compact_button)
	actions.add_child(compact_button)
	refresh_button = Button.new()
	refresh_button.text = "Обновить"
	refresh_button.pressed.connect(_refresh)
	_apply_main_button(refresh_button)
	actions.add_child(refresh_button)
	cancel_import_button = Button.new()
	cancel_import_button.name = "KnowledgeCancelImportButton"
	cancel_import_button.text = "Остановить после текущего файла"
	cancel_import_button.visible = false
	cancel_import_button.tooltip_text = "Текущий файл завершается безопасно; следующие файлы не запускаются."
	cancel_import_button.pressed.connect(_request_import_cancel)
	_apply_main_button(cancel_import_button, true)
	actions.add_child(cancel_import_button)

	stats_label = Label.new()
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(stats_label)
	progress_label = Label.new()
	progress_label.name = "KnowledgeProgress"
	progress_label.text = "Готово к импорту."
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(progress_label)
	root.add_child(HSeparator.new())
	var source_title := Label.new()
	source_title.text = "Источники знаний"
	source_title.add_theme_font_size_override("font_size", 19)
	root.add_child(source_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	sources_box = VBoxContainer.new()
	sources_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sources_box.add_theme_constant_override("separation", 7)
	scroll.add_child(sources_box)

	file_picker = FileDialog.new()
	file_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_picker.access = FileDialog.ACCESS_FILESYSTEM
	file_picker.use_native_dialog = true
	file_picker.files_selected.connect(_on_files_selected)
	add_child(file_picker)
	folder_picker = FileDialog.new()
	folder_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_picker.access = FileDialog.ACCESS_FILESYSTEM
	folder_picker.use_native_dialog = true
	folder_picker.dir_selected.connect(_on_folder_selected)
	add_child(folder_picker)

func _set_import_busy(value: bool) -> void:
	import_busy = value
	if add_files_button != null:
		add_files_button.disabled = value
	if add_folder_button != null:
		add_folder_button.disabled = value
	if compact_button != null:
		compact_button.disabled = value
	if cancel_import_button != null:
		cancel_import_button.visible = value
		cancel_import_button.disabled = not value
	if not value:
		import_cancel_requested = false

func _request_import_cancel() -> void:
	if not import_busy:
		return
	import_cancel_requested = true
	if cancel_import_button != null:
		cancel_import_button.disabled = true
	if progress_label != null:
		progress_label.text = "Остановка запрошена • текущий файл будет завершён безопасно."

func _on_files_selected(paths: PackedStringArray) -> void:
	var selected: Array = []
	for path in paths:
		selected.append(path)
	await _import_paths(selected)

func _on_folder_selected(path: String) -> void:
	if import_busy:
		return
	var paths: Array = []
	_collect_supported(path, paths, MAX_FOLDER_FILES)
	if paths.is_empty():
		progress_label.text = "В выбранной папке не найдено поддерживаемых файлов."
		return
	await _import_paths(paths)

func _collect_supported(path: String, out: Array, limit: int) -> void:
	if out.size() >= limit:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while out.size() < limit:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name in [".", ".."] or name.begins_with("."):
			continue
		var is_directory := dir.current_is_dir()
		var full := path.path_join(name)
		if is_directory:
			_collect_supported(full, out, limit)
		elif _is_supported(full):
			out.append(full)
	dir.list_dir_end()

func _is_supported(path: String) -> bool:
	var ai := _main_ai()
	return ai != null and ai.supported_learning_files().has(path.get_extension().to_lower())

func _import_paths(paths: Array) -> void:
	if import_busy:
		return
	var ai := _main_ai()
	if ai == null:
		progress_label.text = "AuroraFox Core не подключён."
		return
	_set_import_busy(true)
	var ok_count := 0
	var duplicate_count := 0
	var failures: PackedStringArray = PackedStringArray()
	var processed_count := 0
	for i in range(paths.size()):
		if import_cancel_requested:
			break
		var path := str(paths[i])
		progress_label.text = "Импорт %d/%d • %s" % [i + 1, paths.size(), path.get_file()]
		await get_tree().process_frame
		var result := await _import_one(path)
		processed_count += 1
		if bool(result.get("ok", false)):
			ok_count += 1
			if bool(result.get("duplicate", false)) or bool(result.get("skipped", false)):
				duplicate_count += 1
		else:
			failures.append("%s: %s" % [path.get_file(), str(result.get("error", "ошибка"))])
		await get_tree().process_frame
	var stopped := import_cancel_requested
	_set_import_busy(false)
	var failure_text := ""
	if not failures.is_empty():
		var visible_failures := failures.slice(0, mini(4, failures.size()))
		failure_text = " • Ошибки: " + " | ".join(visible_failures)
		if failures.size() > visible_failures.size():
			failure_text += " • ещё %d" % (failures.size() - visible_failures.size())
	var duplicate_text := ""
	if duplicate_count > 0:
		duplicate_text = " • Уже были в базе: %d" % duplicate_count
	var stop_text := " • Остановлено пользователем" if stopped else ""
	progress_label.text = "Обработано: %d/%d • успешно %d%s%s%s" % [processed_count, paths.size(), ok_count, duplicate_text, stop_text, failure_text]
	_refresh()

func _import_one(path: String, force_reindex := false) -> Dictionary:
	var ai := _main_ai()
	if ai == null:
		return {"ok": false, "error": "AIClient недоступен"}
	if not _is_supported(path):
		return {"ok": false, "error": "Формат не поддерживается для базы знаний"}
	var base_meta := {"scope": "core_knowledge", "imported_by": "knowledge_base", "force_reindex": force_reindex}
	var direct := ai.learn_from_file(path, base_meta)
	if bool(direct.get("ok", false)):
		return direct
	if not bool(direct.get("requires_extractor", false)):
		return direct
	var files := _attachments()
	if files == null:
		return {"ok": false, "error": "File Intelligence не подключён"}
	var analyzed: Dictionary = await files.extract_for_knowledge(path)
	if not bool(analyzed.get("ok", false)) or not bool(analyzed.get("analyzed", false)):
		return {"ok": false, "error": str(analyzed.get("analysis_error", analyzed.get("error", "Не удалось извлечь содержимое")))}
	var content := str(analyzed.get("content", "")).strip_edges()
	if content.is_empty():
		return {"ok": false, "error": "File Intelligence не извлёк текст"}
	return ai.learn_from_extracted_file(path, content, {
		"scope": "core_knowledge",
		"imported_by": "file_intelligence_local",
		"detected_kind": analyzed.get("kind", "document"),
		"document_metadata": analyzed.get("metadata", {}),
		"truncated": analyzed.get("truncated", false),
		"visual_used": false,
		"external_ai_required": false,
		"force_reindex": force_reindex
	})

func _refresh() -> void:
	var ai := _main_ai()
	if ai == null or stats_label == null:
		return
	var stats: Dictionary = ai.knowledge_stats()
	stats_label.text = "Источников: %d • копий/alias: %d • ревизий: %d • фрагментов: %d • структурированных записей: %d • хранилище: %s • категории: %s" % [
		int(stats.get("sources", 0)), int(stats.get("source_aliases", 0)), int(stats.get("source_revisions_total", 0)), int(stats.get("chunks", 0)), int(stats.get("structured_records", 0)), _human_size(int(stats.get("bytes", 0))), _format_kinds(stats.get("kinds", {}))
	]
	for child in sources_box.get_children():
		child.queue_free()
	var sources: Array = ai.knowledge_sources()
	if sources.is_empty():
		var empty := Label.new()
		empty.text = "База знаний пока пуста. Добавьте файл или папку."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sources_box.add_child(empty)
		return
	for source in sources:
		if source is Dictionary:
			_add_source_card(source)

func _add_source_card(source: Dictionary) -> void:
	var source_path := str(source.get("source", "manual"))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _source_style())
	sources_box.add_child(panel)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 9)
	panel.add_child(card)

	var name := Label.new()
	name.text = source_path.get_file() if source_path != "manual" else "Ручные знания"
	name.tooltip_text = source_path
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.add_theme_font_size_override("font_size", 16)
	card.add_child(name)
	var registry_details := ""
	var fingerprint := str(source.get("fingerprint_sha256", ""))
	if not fingerprint.is_empty():
		registry_details = " • rev:%d • SHA:%s" % [int(source.get("revision", 1)), fingerprint.substr(0, 10)]
	var aliases = source.get("aliases", [])
	if aliases is Array and not aliases.is_empty():
		registry_details += " • копий:%d" % aliases.size()
	var details := Label.new()
	details.text = "%s\n%d фрагм. • %s%s" % [source_path, int(source.get("chunks", 0)), _format_kinds(source.get("kinds", {})), registry_details]
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_theme_font_size_override("font_size", 11)
	details.add_theme_color_override("font_color", Color("a9b4c8"))
	card.add_child(details)

	var source_actions := HFlowContainer.new()
	source_actions.add_theme_constant_override("h_separation", 8)
	source_actions.add_theme_constant_override("v_separation", 7)
	card.add_child(source_actions)
	if source_path != "manual":
		var reindex := Button.new()
		reindex.text = "Переиндексировать"
		reindex.disabled = not FileAccess.file_exists(source_path)
		reindex.pressed.connect(_reindex.bind(source_path))
		_apply_main_button(reindex)
		source_actions.add_child(reindex)
	var remove := Button.new()
	remove.text = "Удалить"
	remove.pressed.connect(_delete_source.bind(source_path))
	_apply_main_button(remove, true)
	source_actions.add_child(remove)

func _delete_source(source: String) -> void:
	var ai := _main_ai()
	if ai == null or import_busy:
		return
	var result := ai.remove_knowledge_source(source)
	progress_label.text = "Источник удалён." if bool(result.get("ok", false)) else "Не удалось удалить источник."
	_refresh()

func _reindex(source: String) -> void:
	if import_busy:
		return
	_set_import_busy(true)
	progress_label.text = "Принудительная переиндексация • %s" % source.get_file()
	await get_tree().process_frame
	var result := await _import_one(source, true)
	_set_import_busy(false)
	progress_label.text = "Переиндексация завершена." if bool(result.get("ok", false)) else "Ошибка переиндексации: %s" % str(result.get("error", ""))
	_refresh()

func _compact() -> void:
	var ai := _main_ai()
	if ai == null or import_busy:
		return
	var result := ai.compact_knowledge()
	progress_label.text = "Удалено дубликатов: %d" % int(result.get("duplicates_removed", 0))
	_refresh()

func _format_kinds(value: Variant) -> String:
	if not value is Dictionary or value.is_empty():
		return "knowledge"
	var parts: PackedStringArray = PackedStringArray()
	for key in value.keys():
		parts.append("%s:%d" % [str(key), int(value.get(key, 0))])
	parts.sort()
	return ", ".join(parts)

func _human_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	if bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (float(bytes) / 1048576.0)
	return "%.2f GB" % (float(bytes) / 1073741824.0)
