class_name KnowledgeBaseOverlay
extends Node

var popup: PopupPanel
var stats_label: Label
var progress_label: Label
var sources_box: VBoxContainer
var file_picker: FileDialog
var folder_picker: FileDialog
var import_busy := false
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
	var title := Label.new()
	title.text = "База знаний AuroraFox"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)
	var intro := Label.new()
	intro.text = "Добавляйте JSON, TXT/Markdown/CSV/YAML/XML, Word, PDF, Excel, PowerPoint, ODT/ODS, RTF/EPUB и исходный код. AuroraFox локально извлекает содержимое и сохраняет полезные знания, факты, шаблоны, алгоритмы, примеры и навыки."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(intro)
	var safety := Label.new()
	safety.text = "Импортированные файлы считаются данными: содержащийся в них код и инструкции автоматически не выполняются и не получают системных полномочий."
	safety.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	safety.add_theme_font_size_override("font_size", 12)
	safety.add_theme_color_override("font_color", Color("9fabc0"))
	root.add_child(safety)

	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	root.add_child(actions)
	var add_files := Button.new()
	add_files.text = "Добавить файлы…"
	add_files.pressed.connect(func(): file_picker.popup_centered_ratio(0.78))
	_apply_main_button(add_files)
	actions.add_child(add_files)
	var add_folder := Button.new()
	add_folder.text = "Добавить папку…"
	add_folder.visible = OS.get_name() == "Windows"
	add_folder.pressed.connect(func(): folder_picker.popup_centered_ratio(0.78))
	_apply_main_button(add_folder)
	actions.add_child(add_folder)
	var compact := Button.new()
	compact.text = "Очистить дубликаты"
	compact.pressed.connect(_compact)
	_apply_main_button(compact)
	actions.add_child(compact)
	var refresh := Button.new()
	refresh.text = "Обновить"
	refresh.pressed.connect(_refresh)
	_apply_main_button(refresh)
	actions.add_child(refresh)

	stats_label = Label.new()
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(stats_label)
	progress_label = Label.new()
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
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(func(): popup.hide())
	_apply_main_button(close)
	root.add_child(close)

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

func _on_files_selected(paths: PackedStringArray) -> void:
	if import_busy or paths.is_empty():
		return
	import_busy = true
	var ai := _main_ai()
	var attachments := _attachments()
	var failures := 0
	var imported := 0
	for path in paths:
		progress_label.text = "Импортирую %s…" % path.get_file()
		var result := await ai.import_knowledge_file(path, attachments) if ai != null else {"ok": false, "error": "AI client unavailable"}
		if result.get("ok", false):
			imported += 1
		else:
			failures += 1
	progress_label.text = "Импорт завершён • успешно %d • ошибок %d" % [imported, failures]
	import_busy = false
	_refresh()

func _on_folder_selected(path: String) -> void:
	if import_busy or path.is_empty():
		return
	import_busy = true
	var files := _collect_files(path)
	var ai := _main_ai()
	var attachments := _attachments()
	var imported := 0
	var failures := 0
	for i in range(files.size()):
		var file_path := str(files[i])
		progress_label.text = "Папка: %d/%d • %s" % [i + 1, files.size(), file_path.get_file()]
		var result := await ai.import_knowledge_file(file_path, attachments) if ai != null else {"ok": false, "error": "AI client unavailable"}
		if result.get("ok", false):
			imported += 1
		else:
			failures += 1
	progress_label.text = "Папка обработана • успешно %d • ошибок %d" % [imported, failures]
	import_busy = false
	_refresh()

func _collect_files(path: String) -> Array[String]:
	var out: Array[String] = []
	_collect_files_into(path, out)
	return out

func _collect_files_into(path: String, out: Array[String]) -> void:
	if out.size() >= MAX_FOLDER_FILES:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var full := path.path_join(name)
		if dir.current_is_dir():
			_collect_files_into(full, out)
		elif _supported(full):
			out.append(full)
		if out.size() >= MAX_FOLDER_FILES:
			break
	dir.list_dir_end()

func _supported(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext in ["json", "jsonl", "txt", "md", "markdown", "csv", "tsv", "yaml", "yml", "xml", "docx", "odt", "rtf", "epub", "pdf", "xls", "xlsx", "ods", "pptx", "py", "gd", "cs", "js", "ts", "java", "kt", "kts", "c", "h", "cpp", "hpp", "cc", "rs", "go", "rb", "php", "sh", "bash", "zsh", "ps1", "sql", "html", "htm", "css", "scss", "sass", "less", "vue", "svelte", "jsx", "tsx", "toml", "ini", "cfg", "conf", "env", "log", "ndjson", "geojson", "json5"]

func _compact() -> void:
	var ai := _main_ai()
	if ai == null:
		progress_label.text = "AuroraFox Core недоступен."
		return
	var result := ai.compact_knowledge()
	progress_label.text = "Дубликаты очищены." if result.get("ok", false) else "Не удалось очистить: %s" % str(result.get("error", "unknown"))
	_refresh()

func _refresh() -> void:
	if stats_label == null or sources_box == null:
		return
	for child in sources_box.get_children():
		child.queue_free()
	var ai := _main_ai()
	if ai == null:
		stats_label.text = "AuroraFox Core не подключён."
		return
	var status := ai.knowledge_status()
	var total := int(status.get("entries", 0))
	var sources: Array = status.get("sources", [])
	var registry: Dictionary = status.get("registry", {})
	stats_label.text = "Знаний: %d • источников: %d • ревизия реестра: %s" % [total, sources.size(), str(registry.get("version", 1))]
	if sources.is_empty():
		var empty := Label.new()
		empty.text = "База знаний пока пуста. Добавь файл или папку."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sources_box.add_child(empty)
		return
	for item in sources:
		if not item is Dictionary:
			continue
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.04, 0.047, 0.075, 0.96)
		style.border_color = Color(0.25, 0.31, 0.45, 0.62)
		style.set_border_width_all(1)
		style.set_corner_radius_all(11)
		card.add_theme_stylebox_override("panel", style)
		sources_box.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var state := str(item.get("state", "active"))
		label.text = "%s\n%s • %s • записей %d" % [str(item.get("display_name", item.get("source_id", "Источник"))), str(item.get("kind", "document")), state, int(item.get("entry_count", 0))]
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Удалить"
		remove.tooltip_text = "Удалить знания только из этого источника"
		_apply_main_button(remove, true)
		var source_id := str(item.get("source_id", ""))
		remove.pressed.connect(_remove_source.bind(source_id))
		row.add_child(remove)

func _remove_source(source_id: String) -> void:
	if source_id.is_empty():
		return
	var ai := _main_ai()
	if ai == null:
		return
	var result := ai.remove_knowledge_source(source_id)
	progress_label.text = "Источник удалён." if result.get("ok", false) else "Не удалось удалить источник: %s" % str(result.get("error", "unknown"))
	_refresh()
