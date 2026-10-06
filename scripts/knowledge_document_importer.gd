class_name KnowledgeDocumentImporter
extends RefCounted

const TEXT_EXTENSIONS := ["txt", "md", "csv", "tsv", "jsonl", "ndjson", "yaml", "yml", "xml", "html", "htm", "log", "ini", "cfg", "conf", "toml", "gd", "py", "js", "ts", "tsx", "jsx", "java", "kt", "kts", "c", "h", "cpp", "hpp", "cs", "go", "rs", "sql", "sh", "ps1", "bat", "php", "rb", "lua", "swift", "dart", "r", "jl"]
const WORD_EXTENSIONS := ["docx", "odt", "rtf"]
const DATA_EXTENSIONS := ["json", "jsonl", "ndjson", "csv", "tsv", "yaml", "yml", "xml", "xlsx", "xls", "ods"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "tif", "tiff"]
const DOCUMENT_EXTENSIONS := ["pdf", "docx", "odt", "rtf", "epub", "xlsx", "xls", "ods", "pptx"]
const BUILTIN_RICH_EXTENSIONS := ["docx", "odt", "rtf", "epub"]

func supported_extensions() -> PackedStringArray:
	var result := PackedStringArray(["json"])
	for ext in TEXT_EXTENSIONS + DOCUMENT_EXTENSIONS + IMAGE_EXTENSIONS:
		if not result.has(ext): result.append(ext)
	return result

func inspect(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	return {
		"path": path,
		"name": path.get_file(),
		"extension": ext,
		"supported": supported_extensions().has(ext),
		"kind_hint": _kind_hint(ext),
		"requires_extractor": (ext in DOCUMENT_EXTENSIONS and ext not in BUILTIN_RICH_EXTENSIONS) or ext in IMAGE_EXTENSIONS,
		"builtin_extractor": ext in BUILTIN_RICH_EXTENSIONS
	}

func extract(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": false, "error": "Файл не найден", "path": path}
	var ext := path.get_extension().to_lower()
	if ext == "json": return {"ok": true, "mode": "json", "path": path}
	if ext in TEXT_EXTENSIONS: return _read_text(path, ext)
	match ext:
		"docx": return _extract_zip_xml(path, ext, "word/document.xml", ["</w:p>", "</w:tr>", "<w:br/>", "<w:tab/>"])
		"odt": return _extract_zip_xml(path, ext, "content.xml", ["</text:p>", "</text:h>", "</table:table-row>"])
		"rtf": return _extract_rtf(path)
		"epub": return _extract_epub(path)
	# OCR can be expensive on large scans. Always route PDF/images through the
	# async FileIntelligenceClient path so Android can poll/cancel instead of
	# blocking the Godot thread via the compatibility extractDocumentText call.
	if ext == "pdf" or ext in IMAGE_EXTENSIONS:
		return {
			"ok": false,
			"error": "Для формата %s требуется асинхронный File Intelligence AuroraFox" % ext,
			"path": path,
			"extension": ext,
			"requires_extractor": true,
			"async_extractor_required": true,
			"kind_hint": _kind_hint(ext)
		}
	var native := _extract_native(path, ext)
	if bool(native.get("ok", false)): return native
	return {"ok": false, "error": "Для формата %s требуется File Intelligence AuroraFox" % ext, "path": path, "extension": ext, "requires_extractor": true, "kind_hint": _kind_hint(ext)}

func _read_text(path: String, ext: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "Не удалось прочитать файл", "path": path}
	var text := file.get_as_text()
	file.close()
	return {"ok": true, "mode": "text", "text": text, "path": path, "extension": ext, "kind_hint": _kind_hint(ext), "extractor": "godot_text"}

func _extract_zip_xml(path: String, ext: String, inner_path: String, line_markers: Array) -> Dictionary:
	var text_cap := OwnerResourcePolicy.value("knowledge_rich_chars")
	var directory := KnowledgeZipPreflight.new().inspect(path, OwnerResourcePolicy.value("knowledge_zip_entries"))
	if not directory.ok: return directory
	var xml_cap := OwnerResourcePolicy.value("knowledge_xml_member_bytes")
	var declared := int(directory.sizes.get(inner_path, -1))
	if declared < 0: return {"ok": false, "error": "Document XML member is missing", "path": path}
	if xml_cap > 0 and declared > xml_cap: return {"ok": false, "error": "Document XML exceeds owner byte budget", "path": path, "requires_extractor": true}
	var zip := ZIPReader.new()
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var err := zip.open(absolute)
	if err != OK:
		return {"ok": false, "error": "Не удалось открыть %s-контейнер" % ext.to_upper(), "path": path, "code": err}
	var files := zip.get_files()
	if inner_path not in files:
		zip.close()
		return {"ok": false, "error": "В %s отсутствует %s" % [ext.to_upper(), inner_path], "path": path}
	var raw := zip.read_file(inner_path)
	zip.close()
	if raw.size() != declared:
		return {"ok": false, "error": "Document XML expanded size differs from ZIP directory", "path": path}
	if raw.is_empty():
		return {"ok": false, "error": "%s не содержит извлекаемого XML" % ext.to_upper(), "path": path}
	var xml := raw.get_string_from_utf8()
	for marker in line_markers:
		xml = xml.replace(str(marker), "\n")
	var text := _markup_to_text(xml)
	if text.is_empty():
		return {"ok": false, "error": "%s не содержит извлекаемого текста" % ext.to_upper(), "path": path}
	return {
		"ok": true,
		"mode": "text",
		"text": text if text_cap == 0 else text.substr(0, text_cap),
		"path": path,
		"extension": ext,
		"kind_hint": _kind_hint(ext),
		"extractor": "aurora_builtin_%s" % ext,
		"truncated": text_cap > 0 and text.length() > text_cap
	}

func _extract_epub(path: String) -> Dictionary:
	var text_cap := OwnerResourcePolicy.value("knowledge_rich_chars")
	var entry_cap := OwnerResourcePolicy.value("knowledge_epub_items")
	var byte_cap := OwnerResourcePolicy.value("knowledge_epub_bytes")
	var truncated := false
	var directory := KnowledgeZipPreflight.new().inspect(path, OwnerResourcePolicy.value("knowledge_zip_entries"))
	if not directory.ok: return directory
	var zip := ZIPReader.new()
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var err := zip.open(absolute)
	if err != OK:
		return {"ok": false, "error": "Не удалось открыть EPUB", "path": path, "code": err}
	var parts: Array[String] = []
	var entries := 0
	var expanded := 0
	for name in zip.get_files():
		var lower := str(name).to_lower()
		if not (lower.ends_with(".xhtml") or lower.ends_with(".html") or lower.ends_with(".htm")):
			continue
		if entry_cap > 0 and entries >= entry_cap:
			truncated = true
			break
		var declared := int(directory.sizes.get(str(name), -1))
		if declared < 0:
			zip.close()
			return {"ok": false, "error": "EPUB member identity differs from ZIP directory", "path": path}
		if byte_cap > 0 and declared > byte_cap - expanded:
			truncated = true
			break
		var raw := zip.read_file(str(name))
		if raw.size() != declared:
			zip.close()
			return {"ok": false, "error": "EPUB expanded size differs from ZIP directory", "path": path}
		entries += 1
		expanded += raw.size()
		var html := raw.get_string_from_utf8()
		html = html.replace("</p>", "\n").replace("</div>", "\n").replace("</h1>", "\n").replace("</h2>", "\n").replace("</h3>", "\n").replace("<br/>", "\n").replace("<br />", "\n")
		var clean := _markup_to_text(html)
		if not clean.is_empty():
			parts.append(clean)
		if text_cap > 0 and _joined_length(parts) >= text_cap:
			truncated = true
			break
	zip.close()
	var text := "\n\n".join(parts)
	if text.is_empty():
		return {"ok": false, "error": "EPUB exceeds owner extraction budget" if truncated else "EPUB не содержит извлекаемого XHTML/HTML текста", "path": path, "truncated": truncated}
	return {
		"ok": true,
		"mode": "text",
		"text": text if text_cap == 0 else text.substr(0, text_cap),
		"path": path,
		"extension": "epub",
		"kind_hint": "document",
		"extractor": "aurora_builtin_epub",
		"entries_read": entries,
		"expanded_bytes": expanded,
		"truncated": truncated or (text_cap > 0 and text.length() > text_cap)
	}

func _extract_rtf(path: String) -> Dictionary:
	var text_cap := OwnerResourcePolicy.value("knowledge_rich_chars")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Не удалось прочитать RTF", "path": path}
	var raw := file.get_as_text()
	file.close()
	var out := ""
	var i := 0
	var skip_group_depth := 0
	var group_depth := 0
	while i < raw.length() and (text_cap == 0 or out.length() < text_cap):
		var c := raw.substr(i, 1)
		if c == "{":
			group_depth += 1
			i += 1
			continue
		if c == "}":
			if skip_group_depth == group_depth:
				skip_group_depth = 0
			group_depth = maxi(0, group_depth - 1)
			i += 1
			continue
		if skip_group_depth > 0:
			i += 1
			continue
		if c != "\\":
			out += c
			i += 1
			continue
		if i + 1 >= raw.length():
			break
		var next := raw.substr(i + 1, 1)
		if next in ["\\", "{", "}"]:
			out += next
			i += 2
			continue
		if next == "*":
			skip_group_depth = group_depth
			i += 2
			continue
		if next == "'" and i + 3 < raw.length():
			# Hex escapes are preserved as a replacement marker when no Unicode \uN
			# equivalent is present; modern RTF generally carries Unicode controls.
			i += 4
			continue
		var j := i + 1
		while j < raw.length() and _is_ascii_letter(raw.substr(j, 1)):
			j += 1
		var word := raw.substr(i + 1, j - (i + 1))
		var sign := 1
		if j < raw.length() and raw.substr(j, 1) == "-":
			sign = -1
			j += 1
		var number_start := j
		while j < raw.length() and raw.substr(j, 1).is_valid_int():
			j += 1
		var has_number := j > number_start
		var number := int(raw.substr(number_start, j - number_start)) * sign if has_number else 0
		if j < raw.length() and raw.substr(j, 1) == " ":
			j += 1
		match word:
			"par", "line": out += "\n"
			"tab": out += "\t"
			"emdash": out += "—"
			"endash": out += "–"
			"bullet": out += "•"
			"u":
				if has_number:
					var code := number
					if code < 0: code += 65536
					out += String.chr(code)
		i = j
	var text := _cleanup_text(out)
	if text.is_empty():
		return {"ok": false, "error": "RTF не содержит извлекаемого текста", "path": path}
	return {"ok": true, "mode": "text", "text": text, "path": path, "extension": "rtf", "kind_hint": "document", "extractor": "aurora_builtin_rtf", "truncated": i < raw.length()}

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

func _markup_to_text(markup: String) -> String:
	var out := ""
	var in_tag := false
	for i in range(markup.length()):
		var c := markup.substr(i, 1)
		if c == "<":
			in_tag = true
			continue
		if c == ">":
			in_tag = false
			out += " "
			continue
		if not in_tag:
			out += c
	out = out.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&#39;", "'").replace("&nbsp;", " ")
	return _cleanup_text(out)

func _cleanup_text(text: String) -> String:
	var lines: Array[String] = []
	for raw_line in text.replace("\r", "\n").split("\n", false):
		var clean := " ".join(str(raw_line).split(" ", false)).strip_edges()
		if not clean.is_empty():
			lines.append(clean)
	return "\n".join(lines)

func _joined_length(parts: Array[String]) -> int:
	var total := 0
	for index in range(parts.size()):
		total += parts[index].length() + (2 if index > 0 else 0)
	return total

func _is_ascii_letter(value: String) -> bool:
	if value.is_empty(): return false
	var code := value.unicode_at(0)
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122)

func _kind_hint(ext: String) -> String:
	if ext in DATA_EXTENSIONS: return "dataset"
	if ext in IMAGE_EXTENSIONS: return "image"
	if ext in WORD_EXTENSIONS or ext in DOCUMENT_EXTENSIONS: return "document"
	if ext in ["gd", "py", "js", "ts", "tsx", "jsx", "java", "kt", "kts", "c", "h", "cpp", "hpp", "cs", "go", "rs", "sql", "sh", "ps1", "bat", "php", "rb", "lua", "swift", "dart", "r", "jl"]: return "code"
	return "knowledge"
