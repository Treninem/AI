extends SceneTree

func _init() -> void:
	var web := PublicWebManager.new()
	root.add_child(web)
	var urls := web.extract_urls("Прочитай https://example.com/wiki?q=1, затем https://example.org/x.")
	_assert(urls == ["https://example.com/wiki?q=1", "https://example.org/x"], "URL extraction lost punctuation boundary")
	_assert(not bool(web.validate_public_url("http://127.0.0.1/admin").get("ok", false)), "loopback SSRF address was accepted")
	_assert(not bool(web.validate_public_url("http://169.254.169.254/latest/meta-data").get("ok", false)), "cloud metadata address was accepted")
	_assert(not bool(web.validate_public_url("http://10.0.0.1/private").get("ok", false)), "private IPv4 address was accepted")
	_assert(not bool(web.validate_public_url("http://[::1]/private").get("ok", false)), "IPv6 loopback was accepted")
	_assert(bool(web.validate_public_url("https://8.8.8.8:8443/public").get("ok", false)), "public non-standard port was artificially blocked")
	var html := "<html><head><title>Fox &amp; Knowledge</title><style>hidden</style></head><body><h1>Факт</h1><script>ignore()</script><p>Полезный текст.</p></body></html>"
	_assert(web._extract_title(html) == "Fox & Knowledge", "HTML title extraction failed")
	var extracted := web._extract_text(html, "text/html")
	_assert(extracted.contains("Факт") and extracted.contains("Полезный текст"), "readable HTML text was lost")
	_assert(not extracted.contains("hidden") and not extracted.contains("ignore()"), "active page content leaked into readable text")
	var failure := web._failure("https://example.com", "unsupported_content_type", "need decision", [], 200)
	_assert(bool(failure.get("owner_decision_required", false)) and not bool(failure.get("saved_to_knowledge", true)), "blocked page does not request an honest owner decision")
	var limits := web.apply_owner_limits({"max_redirects": 12, "max_response_bytes": 16 * 1024 * 1024}, false)
	_assert(int(limits.get("max_redirects", 0)) == 12 and int(limits.get("max_response_bytes", 0)) == 16 * 1024 * 1024, "owner could not change soft web limits")
	_assert(bool(limits.get("owner_adjustable", false)), "soft limits are not marked owner-adjustable")
	print("AURORA_PUBLIC_WEB_MANAGER_OK urls=true ssrf=true nonstandard_port=true html=true owner_decision=true owner_limits=true")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
