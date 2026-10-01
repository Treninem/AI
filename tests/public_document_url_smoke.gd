extends SceneTree

class FixtureReader extends PublicWebManager:
	var fixture := {}
	func validate_public_url(_url: String) -> Dictionary:
		return {"ok": true}
	func _request_once(_url: String) -> Dictionary:
		await get_tree().process_frame
		return fixture.duplicate(true)

class FixtureAnalyzer extends Node:
	var expected := PackedByteArray()
	var seen_path := ""
	var seen_bytes := PackedByteArray()
	var reply := {"ok": true, "kind": "document", "content": "Уникальный факт Aurora URL: давление 5 бар.", "metadata": {"pages": 1}}
	func analyze_file(path: String, _question := "", _visual := true, _max_chars := 160000) -> Dictionary:
		seen_path = path
		seen_bytes = FileAccess.get_file_as_bytes(path)
		await get_tree().process_frame
		return reply.duplicate(true)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var reader := FixtureReader.new()
	root.add_child(reader)
	var analyzer := FixtureAnalyzer.new()
	reader.add_child(analyzer)
	reader.file_client = analyzer
	var bytes := PackedByteArray([37, 80, 68, 70, 45, 49, 46, 55, 0, 255, 128])
	reader.fixture = {"transport_ok": true, "status": 200, "content_type": "application/octet-stream", "body_bytes": bytes}
	var url := "https://example.org/aurora-doc-fixture-%d" % Time.get_ticks_usec()
	var result := await reader.process_user_message("Прочитай " + url)
	var item: Dictionary = result.get("items", [])[0]
	_assert(bool(item.get("ok", false)), "document read failed")
	_assert(analyzer.seen_bytes == bytes, "download bytes corrupted")
	_assert(analyzer.seen_path.begins_with("user://web_inputs/") and analyzer.seen_path.ends_with(".pdf"), "signature/private routing failed")
	_assert(not FileAccess.file_exists(analyzer.seen_path), "temporary file leaked")
	_assert(bool(item.get("knowledge_import", {}).get("ok", false)), "actual Knowledge import failed")
	_assert(reader.knowledge.search("Aurora URL давление", 10).any(func(hit): return str(hit.get("source", "")) == url), "Knowledge retrieval lost URL provenance")
	_assert(item.get("download_sha256", "") == reader._sha256_bytes(bytes), "raw-byte provenance hash differs")
	_assert(not bool(item.get("instruction_authority", true)), "document gained instruction authority")
	var forbidden := await reader.process_user_message("Прочитай, но не запоминай " + url + "?no-save=1")
	_assert(not bool(forbidden.get("durable_write_authorized", true)), "explicit no-save ignored")
	_assert(not forbidden.get("items", [])[0].has("knowledge_import"), "no-save instruction wrote Knowledge")
	# Generic ZIP MIME plus an extensionless URL must still select Office parser.
	var office_path := "user://office-fixture.zip"
	var packer := ZIPPacker.new()
	_assert(packer.open(office_path) == OK, "ZIP fixture creation failed")
	packer.start_file("word/document.xml")
	packer.write_file("<document>fact</document>".to_utf8_buffer())
	packer.close_file()
	packer.close()
	reader.fixture["body_bytes"] = FileAccess.get_file_as_bytes(office_path)
	reader.fixture["content_type"] = "application/zip"
	var office := await reader.read_public_url(url)
	_assert(bool(office.get("ok", false)) and analyzer.seen_path.ends_with(".docx"), "generic ZIP Office content not detected")
	_assert(not FileAccess.file_exists(analyzer.seen_path), "typed staging file leaked")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(office_path))
	analyzer.reply = {"ok": true, "kind": "archive", "content": "only member names", "metadata": {"text_entries_extracted": 0}}
	var listing := await reader.read_public_url(url)
	_assert(not bool(listing.get("ok", true)) and listing.get("error", "") == "unsupported_content_extraction", "listing-only archive reported success")
	_assert(not FileAccess.file_exists(analyzer.seen_path), "failed extraction leaked file")
	analyzer.reply = {"ok": false, "error": "backend unavailable"}
	var failed := await reader.read_public_url(url)
	_assert(not bool(failed.get("ok", true)) and bool(failed.get("owner_decision_required", false)), "backend failure not reported")
	_assert(not FileAccess.file_exists(analyzer.seen_path), "backend failure leaked file")
	reader.fixture = {"transport_ok": true, "status": 200, "content_type": "text/html", "body_bytes": "<html>captcha verify challenge</html>".to_utf8_buffer()}
	var challenged := await reader.read_public_url(url + ".pdf")
	_assert(challenged.get("error", "") == "interactive_access_required", "HTML challenge at document URL bypassed")
	_assert(reader._document_extension(PackedByteArray(), "application/octet-stream", "https://example.org/download", 'attachment; filename="../../report.docx"') == "docx", "disposition type selection failed")
	_assert(reader._document_extension(PackedByteArray(), "application/vnd.oasis.opendocument.spreadsheet", url, "") == "ods", "ODS MIME selection failed")
	reader.apply_owner_limits({"max_urls_per_message": 1, "max_extracted_chars": 360000})
	var skipped := await reader.process_user_message("Прочитай " + url + " https://example.org/second")
	_assert(skipped.get("items", []).size() == 2 and skipped.get("items", [])[1].get("error", "") == "url_limit_exceeded", "URL cap silently omitted sources")
	_assert(reader.max_extracted_chars == 360000, "extraction budget not adjustable")
	print("AURORA_PUBLIC_DOCUMENT_URL_OK bytes=true private=true cleanup=true knowledge=true nosave=true listing_rejected=true access=true limits=true")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
