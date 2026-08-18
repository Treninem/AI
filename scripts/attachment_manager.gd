class_name AttachmentManager
extends Node

const TEXT_EXTENSIONS := ["txt", "md", "json", "csv", "gd", "py", "js", "ts", "html", "css", "xml", "yaml", "yml", "toml", "ini", "cfg", "log", "shader", "glsl", "cpp", "c", "h", "hpp", "cs", "java", "rs"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "gif", "svg"]
const DOCUMENT_EXTENSIONS := ["pdf", "docx", "xlsx", "xls", "pptx", "odt", "ods"]
const AUDIO_EXTENSIONS := ["wav", "mp3", "ogg", "flac", "m4a"]
const VIDEO_EXTENSIONS := ["mp4", "mkv", "webm", "mov", "avi"]
const ARCHIVE_EXTENSIONS := ["zip", "7z", "rar", "tar", "gz"]
const MAX_TEXT_BYTES := 2 * 1024 * 1024

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
		"content": ""
	}
	if ext in TEXT_EXTENSIONS and size <= MAX_TEXT_BYTES:
		result["content"] = file.get_as_text()
	elif ext in TEXT_EXTENSIONS:
		result["content"] = "[Текстовый файл слишком большой для полного чтения: %d байт]" % size
	else:
		result["content"] = _processing_hint(kind)
	return result

func build_context(attachments: Array) -> String:
	if attachments.is_empty(): return ""
	var parts: Array[String] = []
	for item in attachments:
		parts.append("Файл: %s\nТип: %s\nРазмер: %s\nСодержимое/статус:\n%s" % [
			item.get("name", "file"),
			item.get("kind", "unknown"),
			_human_size(int(item.get("size", 0))),
			item.get("content", "")
		])
	return "\n\n--- ПРИКРЕПЛЕННЫЕ ФАЙЛЫ ---\n" + "\n\n".join(parts)

func supported_extensions() -> PackedStringArray:
	var all: Array = TEXT_EXTENSIONS + IMAGE_EXTENSIONS + DOCUMENT_EXTENSIONS + AUDIO_EXTENSIONS + VIDEO_EXTENSIONS + ARCHIVE_EXTENSIONS
	return PackedStringArray(all)

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
		"image": return "Изображение принято. Для визуального анализа подключается vision-модель/локальный анализатор."
		"document": return "Документ принят. Для извлечения PDF/DOCX/XLSX будет использоваться локальный парсер."
		"audio": return "Аудио принято. Для расшифровки подключается локальный speech-to-text модуль."
		"video": return "Видео принято. Для анализа будут извлечены кадры и аудиодорожка."
		"archive": return "Архив принят. Распаковка должна выполняться в изолированную временную папку с лимитами."
		_: return "Файл принят как бинарный ресурс."

func _human_size(bytes: int) -> String:
	if bytes < 1024: return "%d B" % bytes
	if bytes < 1024 * 1024: return "%.1f KB" % (float(bytes) / 1024.0)
	return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
