class_name AttachmentManager
extends Node

signal file_setup_required

const TEXT_EXTENSIONS := ["txt", "md", "json", "csv", "tsv", "gd", "py", "js", "ts", "tsx", "jsx", "html", "css", "xml", "yaml", "yml", "toml", "ini", "cfg", "log", "shader", "glsl", "cpp", "c", "h", "hpp", "cs", "java", "kt", "rs", "go", "php", "rb", "lua", "swift", "dart", "sql", "sh", "ps1", "r", "jl"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "gif", "svg", "tif", "tiff"]
const DOCUMENT_EXTENSIONS := ["pdf", "docx", "xlsx", "xls", "pptx", "odt", "ods"]
const AUDIO_EXTENSIONS := ["wav", "mp3", "ogg", "flac", "m4a", "aac", "opus"]
const VIDEO_EXTENSIONS := ["mp4", "mkv", "webm", "mov", "avi", "m4v"]
const ARCHIVE_EXTENSIONS := ["zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz"]
const MAX_TEXT_BYTES := 2 * 1024 * 1024

var intelligence := FileIntelligenceClient.new()

func _ready() -> void:
	add_child(intelligence)

func describe(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {"ok": false, "path": path, "error": "Не удалось открыть файл"}
	var size := file.get_length()
	var ext := path.get_extension().to_lower()
	var kind := _kind_for_extension(ext)
	var result := {
		"ok": true,
		"path": path,
		"name": path.get_file(),
		"extension": ext,
		"kind": kind,
		"size": size,
		"content": "",
		"warnings": [],
		"analyzed": false
	}
	if ext in TEXT_EXTENSIONS and size <= MAX_TEXT_BYTES:
		result["content"] = file.get_as_text()
		result["analyzed"] = true
	elif ext in TEXT_EXTENSIONS:
		result["content"] = "[Текстовый файл большой; будет прочитан локальным File Intelligence с лимитом контекста.]"
	else:
		result["content"] = "[Ожидает локального анализа файла]"
	file.close()
	return result

func analyze(path: String, question := "") -> Dictionary:
	var item := describe(path)
	if not item.get("ok", false): return item
	if bool(item.get("analyzed", false)):
		return item

	if OS.get_name() not in ["Windows", "Android"]:
		item["content"] = _processing_hint(str(item.get("kind", "binary")))
		item["warnings"] = ["Расширенный File Intelligence на этой платформе пока не подключён."]
		return item

	var result := await intelligence.analyze_file(path, question, true)
	if not result.get("ok", false):
		item["content"] = _processing_hint(str(item.get("kind", "binary")))
		item["analysis_error"] = str(result.get("error", "File Intelligence недоступен"))
		item["needs_setup"] = OS.get_name() == "Windows" and not intelligence.runtime_is_installed()
		item["warnings"] = [str(result.get("error", "File Intelligence недоступен"))]
		if bool(item["needs_setup"]): file_setup_required.emit()
		return item

	item["content"] = str(result.get("content", ""))
	item["kind"] = str(result.get("kind", item.get("kind", "binary")))
	item["metadata"] = result.get("metadata", {})
	item["warnings"] = result.get("warnings", [])
	item["truncated"] = bool(result.get("truncated", false))
	item["cached"] = bool(result.get("cached", false))
	item["elapsed_ms"] = int(result.get("elapsed_ms", 0))
	item["private_copy"] = result.get("private_copy", "")
	item["analyzed"] = true
	return item

func build_context(attachments: Array) -> String:
	if attachments.is_empty(): return ""
	var parts: Array[String] = []
	for item in attachments:
		var warning_text := ""
		var warnings: Array = item.get("warnings", [])
		if not warnings.is_empty():
			warning_text = "\nПредупреждения: " + " | ".join(PackedStringArray(warnings))
		parts.append("Файл: %s\nТип: %s\nРазмер: %s\nРезультат локального анализа:\n%s%s" % [
			item.get("name", "file"),
			item.get("kind", "unknown"),
			_human_size(int(item.get("size", 0))),
			item.get("content", ""),
			warning_text
		])
	return "\n\n--- ПРИКРЕПЛЕННЫЕ ФАЙЛЫ ---\n" + "\n\n".join(parts)

func supported_extensions() -> PackedStringArray:
	var all: Array = TEXT_EXTENSIONS + IMAGE_EXTENSIONS + DOCUMENT_EXTENSIONS + AUDIO_EXTENSIONS + VIDEO_EXTENSIONS + ARCHIVE_EXTENSIONS
	return PackedStringArray(all)

func file_runtime_ready() -> bool:
	return intelligence.runtime_is_installed()

func file_installer_path() -> String:
	return intelligence.installer_path()

func restart_file_backend() -> void:
	intelligence.restart_backend()

func clear_file_cache() -> Dictionary:
	return await intelligence.clear_cache()

func _kind_for_extension(ext: String) -> String:
	if ext in TEXT_EXTENSIONS: return "text/code"
	if ext in IMAGE_EXTENSIONS: return "image"
	if ext in DOCUMENT_EXTENSIONS: return "document"
	if ext in AUDIO_EXTENSIONS: return "audio"
	if ext in VIDEO_EXTENSIONS: return "video"
	if ext in ARCHIVE_EXTENSIONS: return "archive"
	return "binary"

func _processing_hint(kind: String) -> String:
	match kind:
		"image": return "Изображение принято, но расширенный локальный визуальный анализ сейчас недоступен."
		"document": return "Документ принят, но локальный парсер сейчас недоступен."
		"audio": return "Аудио принято, но локальная расшифровка сейчас недоступна."
		"video": return "Видео принято, но извлечение кадров/аудио сейчас недоступно."
		"archive": return "Архив принят, но безопасный анализ содержимого сейчас недоступен."
		_: return "Файл принят как бинарный ресурс."

func _human_size(bytes: int) -> String:
	if bytes < 1024: return "%d B" % bytes
	if bytes < 1024 * 1024: return "%.1f KB" % (float(bytes) / 1024.0)
	if bytes < 1024 * 1024 * 1024: return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
	return "%.2f GB" % (float(bytes) / (1024.0 * 1024.0 * 1024.0))
