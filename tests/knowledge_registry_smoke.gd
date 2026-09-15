extends SceneTree

var _paths: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _fail(message: String, code: int) -> void:
	push_error(message)
	_cleanup()
	quit(code)

func _run() -> void:
	var store := KnowledgeStore.new()
	var txn := KnowledgeImportTransaction.new()
	var manager := KnowledgeManager.new()
	var registry := KnowledgeSourceRegistry.new()

	var source_a := "user://knowledge_registry_primary.txt"
	var source_copy := "user://knowledge_registry_copy.txt"
	_paths.append_array([source_a, source_copy])
	_write(source_a, "AuroraFox unique registry alpha knowledge")
	_write(source_copy, "AuroraFox unique registry alpha knowledge")
	manager.remove_source(source_a)
	manager.remove_source(source_copy)

	var first := txn.import_file(store, source_a, {"imported_by": "registry_smoke"})
	if not bool(first.get("ok", false)) or bool(first.get("skipped", false)):
		_fail("Initial fingerprinted knowledge import failed: " + JSON.stringify(first), 2)
		return
	if int(first.get("revision", 0)) != 1 or str(first.get("fingerprint_sha256", "")).length() != 64:
		_fail("Initial source registry metadata is incomplete", 3)
		return
	var chunks_before := int(manager.stats().get("chunks", 0))

	var duplicate := txn.import_file(store, source_copy, {"imported_by": "registry_smoke"})
	if not bool(duplicate.get("ok", false)) or not bool(duplicate.get("skipped", false)) or not bool(duplicate.get("duplicate", false)):
		_fail("Byte-identical renamed source was not deduplicated: " + JSON.stringify(duplicate), 4)
		return
	if int(manager.stats().get("chunks", 0)) != chunks_before:
		_fail("Duplicate alias created additional knowledge chunks", 5)
		return
	var row := registry.record_for_source(source_a)
	var aliases = row.get("aliases", [])
	if not aliases is Array or source_copy not in aliases:
		_fail("Duplicate file was not recorded as source alias", 6)
		return

	# Changing the canonical source must create a new revision and detach aliases
	# whose bytes still represent the previous revision.
	_write(source_a, "AuroraFox unique registry beta changed knowledge")
	var changed := txn.import_file(store, source_a, {"imported_by": "registry_smoke"})
	if not bool(changed.get("ok", false)) or int(changed.get("revision", 0)) != 2:
		_fail("Changed source did not become revision 2: " + JSON.stringify(changed), 7)
		return
	row = registry.record_for_source(source_a)
	aliases = row.get("aliases", [])
	if aliases is Array and source_copy in aliases:
		_fail("Stale alias survived canonical content change", 8)
		return
	var search := store.search("beta changed knowledge", 4)
	if search.is_empty():
		_fail("Revised source is not searchable", 9)
		return

	# DOCX extraction is built into AuroraFox and does not depend on Python/Ollama.
	var docx := "user://knowledge_builtin_test.docx"
	_paths.append(docx)
	if not _make_zip(docx, {
		"[Content_Types].xml": "<Types></Types>",
		"word/document.xml": "<w:document><w:body><w:p><w:r><w:t>AuroraFox DOCX builtin knowledge</w:t></w:r></w:p></w:body></w:document>"
	}):
		_fail("Could not create DOCX smoke fixture", 10)
		return
	var importer := KnowledgeDocumentImporter.new()
	var docx_result := importer.extract(docx)
	if not bool(docx_result.get("ok", false)) or not str(docx_result.get("text", "")).contains("DOCX builtin knowledge"):
		_fail("Built-in DOCX extraction failed: " + JSON.stringify(docx_result), 11)
		return
	if str(docx_result.get("extractor", "")) != "aurora_builtin_docx":
		_fail("DOCX unexpectedly required an external extractor", 12)
		return

	var epub := "user://knowledge_builtin_test.epub"
	_paths.append(epub)
	if not _make_zip(epub, {
		"mimetype": "application/epub+zip",
		"OEBPS/chapter1.xhtml": "<html><body><h1>AuroraFox EPUB</h1><p>offline knowledge chapter</p></body></html>"
	}):
		_fail("Could not create EPUB smoke fixture", 13)
		return
	var epub_result := importer.extract(epub)
	if not bool(epub_result.get("ok", false)) or not str(epub_result.get("text", "")).contains("offline knowledge chapter"):
		_fail("Built-in EPUB extraction failed: " + JSON.stringify(epub_result), 14)
		return

	var rtf := "user://knowledge_builtin_test.rtf"
	_paths.append(rtf)
	_write(rtf, "{\\rtf1\\ansi AuroraFox RTF \\u1055?\\u1088?\\u1080?\\u1074?\\u1077?\\u1090?\\par local knowledge}")
	var rtf_result := importer.extract(rtf)
	if not bool(rtf_result.get("ok", false)) or not str(rtf_result.get("text", "")).contains("AuroraFox RTF"):
		_fail("Built-in RTF extraction failed: " + JSON.stringify(rtf_result), 15)
		return

	manager.remove_source(source_a)
	manager.remove_source(source_copy)
	_cleanup()
	print("AURORA_KNOWLEDGE_REGISTRY_SMOKE_OK fingerprint=true aliases=true revision=true docx=true epub=true rtf=true")
	quit(0)

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()

func _make_zip(path: String, files: Dictionary) -> bool:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var packer := ZIPPacker.new()
	if packer.open(ProjectSettings.globalize_path(path)) != OK:
		return false
	for name in files.keys():
		if packer.start_file(str(name)) != OK:
			packer.close()
			return false
		if packer.write_file(str(files[name]).to_utf8_buffer()) != OK:
			packer.close_file()
			packer.close()
			return false
		if packer.close_file() != OK:
			packer.close()
			return false
	return packer.close() == OK

func _cleanup() -> void:
	for path in _paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
