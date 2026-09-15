class_name KnowledgeDocumentImporter
extends RefCounted

const TEXT_EXTENSIONS := ["txt", "md", "csv", "tsv", "jsonl", "ndjson", "yaml", "yml", "xml", "html", "htm", "log", "ini", "cfg", "conf", "toml", "gd", "py", "js", "ts", "tsx", "jsx", "java", "kt", "kts", "c", "h", "cpp", "hpp", "cs", "go", "rs", "sql", "sh", "ps1", "bat", "php", "rb", "lua", "swift", "dart", "r", "jl"]
const WORD_EXTENSIONS := ["docx", "odt", "rtf"]
const DATA_EXTENSIONS := ["json", "jsonl", "ndjson", "csv", "tsv", "yaml", "yml", "xml", "xlsx", "xls", "ods"]
const DOCUMENT_EXTENSIONS := ["pdf", "docx", "odt", "rtf", "epub", "xlsx", "xls", "ods", "pptx"]

func supported_extensions() -> PackedStringArray:
	var result := PackedStringArray(["json"])
	for ext in TEXT_EXTENSIONS + DOCUMENT_EXTENSIONS:
		if not result.has(ext): result.append(ext)
	return result

func inspect(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	return {"path": path, "name": path.get_file(), "extension": ext, "supported": supported_extensions().has(ext), "kind_hint": _kind_hint(ext), "requires_extractor": ext in DOCUMENT_EXTENSIONS}

func extract(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": false, "error": "Файл не найден", "path": path}
	var ext := path.get_extension().to_lower()
	if ext == "json": return {"ok": true, "mode": "json", "path": path}
	if ext in TEXT_EXTENSIONS: return _read_text(path, ext)
	var native := _extract_native(path, ext)
	if bool(native.get("ok", false)): return native
	return {"ok": false, "error": "Для формата %s требуется File Intelligence AuroraFox" % ext, "path": path, "extension": ext, "requires_extractor": true, "kind_hint": _kind_hint(ext)}

func _read_text(path: String, ext: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "Не удалось прочитать файл", "path": path}
	var text := file.get_as_text()
	file.close()
	return {"ok": true, "mode": "text", "text": text, "path": path, "extension": ext, "kind_hint": _kind_hint(ext)}

func _extract_native(path: String, ext: String) -> Dictionary:
	if Engine.has_singleton("AuroraFoxRuntime"):
		var runtime := Engine.get_singleton("AuroraFoxRuntime")
		if runtime != null and runtime.has_method("extractDocumentText"):
			var raw = runtime.call("extractDocumentText", ProjectSettings.globalize_path(path))
			var parsed = JSON.parse_string(str(raw)) if raw is String else raw
			if parsed is Dictionary:
				parsed["extension"] = ext
				parsed["mode"] = "text"
				return parsed
	return {"ok": false}

func _kind_hint(ext: String) -> String:
	if ext in DATA_EXTENSIONS: return "dataset"
	if ext in WORD_EXTENSIONS or ext in DOCUMENT_EXTENSIONS: return "document"
	if ext in ["gd", "py", "js", "ts", "tsx", "jsx", "java", "kt", "kts", "c", "h", "cpp", "hpp", "cs", "go", "rs", "sql", "sh", "ps1", "bat", "php", "rb", "lua", "swift", "dart", "r", "jl"]: return "code"
	return "knowledge"
