extends SceneTree

var registry: ToolRegistry
var scope_path := "user://security-review-regression.json"
var scope_text := '{"urls":["https://example.invalid/"],"authorization_reference":"owner lab"}'

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	registry = ToolRegistry.new()
	root.add_child(registry)
	assert(registry._security_write_snapshot(ProjectSettings.globalize_path(scope_path), scope_text) or FileAccess.get_file_as_string(scope_path) == scope_text)
	var result: Dictionary = await registry._security_review_scope(scope_path, "")
	assert(result.error == "owner_review_unavailable", "No UI must fail closed")
	registry.security_owner_review = func(_text, _hash): return false
	result = await registry._security_review_scope(scope_path, "")
	assert(result.error == "owner_authorization_declined", "Owner denial lost")
	registry.security_owner_review = func(text, _hash): return text == scope_text
	result = await registry._security_review_scope(scope_path, "")
	assert(result.ok and result.scope_text == scope_text, "Exact scope not retained")
	registry.security_owner_review = func(_text, _hash):
		var f := FileAccess.open(scope_path, FileAccess.WRITE)
		f.store_string('{"urls":["https://changed.invalid/"]}')
		f.close()
		return true
	result = await registry._security_review_scope(scope_path, "")
	assert(result.error == "reviewed_inputs_changed", "Changed scope approved")
	assert(not registry._path_allowed("user://security/runs/abc/scope.json", true))
	assert(not registry._path_allowed("user://tmp/../security/runs/abc/evidence.json", true))
	assert(not registry._path_allowed("user://../outside", true))
	assert(registry._path_allowed("user://normal-owner-file.json", true))
	assert(not registry._security_write_snapshot(ProjectSettings.globalize_path(scope_path), "overwrite"))
	assert(FileAccess.get_file_as_string(scope_path).contains("changed.invalid"), "Existing file overwritten")
	var report := {"schema": "aurorafox.security-evidence.v1", "scope_file_sha256": scope_text.sha256_text(), "results": []}
	assert(not registry._security_validate_evidence(report, scope_text).ok, "Empty evidence accepted")
	report.results = [{"target_sha256": JSON.stringify("https://example.invalid/").sha256_text(), "outcome": "checked"}]
	assert(registry._security_validate_evidence(report, scope_text).all_checked)
	report.scope_file_sha256 = "b".repeat(64)
	assert(not registry._security_validate_evidence(report, scope_text).ok, "Wrong scope accepted")
	report.scope_file_sha256 = scope_text.sha256_text()
	report.results[0].outcome = "transport_failure"
	assert(not registry._security_validate_evidence(report, scope_text).all_checked, "Failed request reported checked")
	assert(not registry._security_execution_allowed(func(_stage, _details): return {"allowed": false}))
	assert(registry._security_execution_allowed(func(_stage, _details): return true))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scope_path))
	registry.queue_free()
	print("AURORA_SECURITY_OWNER_REVIEW_OK denied=true changed_scope=true reserved_storage=true no_overwrite=true evidence=true cancellation=true")
	quit(0)
