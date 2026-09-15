extends SceneTree

func _init() -> void:
	var submitter := CoreCandidateSubmitter.new()
	root.add_child(submitter)
	var fixture_root := "user://core_candidate_submitter_smoke"
	var target := "scripts/memory_store.gd"
	var candidate_path := fixture_root.path_join(target)
	var manifest_path := fixture_root.path_join("candidate.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(candidate_path.get_base_dir()))

	var source := "class_name SmokeCandidate\nextends RefCounted\nfunc search(q):\n\treturn q\n"
	var sha := _sha256_text(source)
	var candidate := FileAccess.open(candidate_path, FileAccess.WRITE)
	if candidate == null:
		_fail("cannot create candidate source", 2)
		return
	candidate.store_string(source)
	candidate.close()
	var manifest := {
		"candidate_id": "submitter_smoke_001",
		"target": target,
		"base_sha256": "a".repeat(64),
		"candidate_sha256": sha,
		"verified": true,
		"promotion": "signed_update",
		"verification": {
			"source_contract": {"ok": true},
			"comparative_review": {"ok": true, "improvement": 2.0}
		}
	}
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("cannot create candidate manifest", 3)
		return
	file.store_string(JSON.stringify(manifest))
	file.close()

	var built := submitter.build_submission(manifest_path, candidate_path, "ci-smoke")
	if not bool(built.get("ok", false)):
		_fail("valid candidate submission payload rejected: %s" % JSON.stringify(built), 4)
		return
	var payload: Dictionary = built.get("payload", {})
	if str(payload.get("source", "")) != "ci-smoke":
		_fail("submission source marker lost", 5)
		return
	var decoded := Marshalls.base64_to_raw(str(payload.get("content_base64", ""))).get_string_from_utf8()
	if decoded != source:
		_fail("candidate payload changed source bytes", 6)
		return
	var sent_manifest: Dictionary = payload.get("manifest", {})
	if str(sent_manifest.get("candidate_sha256", "")) != sha:
		_fail("candidate hash lost from payload", 7)
		return

	# The transport must never accept arbitrary insecure remote HTTP endpoints.
	if submitter._endpoint_allowed("http://example.com"):
		_fail("remote plaintext Core candidate endpoint was accepted", 8)
		return
	if not submitter._endpoint_allowed("https://aurorafox.example"):
		_fail("HTTPS Core candidate endpoint was rejected", 9)
		return
	if not submitter._endpoint_allowed("http://127.0.0.1:8768"):
		_fail("local development endpoint was rejected", 10)
		return

	# Tampering after manifest verification must be caught before any request.
	var tampered := FileAccess.open(candidate_path, FileAccess.WRITE)
	tampered.store_string(source + "# tampered\n")
	tampered.close()
	var rejected := submitter.build_submission(manifest_path, candidate_path, "ci-smoke")
	if bool(rejected.get("ok", false)) or not str(rejected.get("error", "")).contains("SHA-256"):
		_fail("tampered candidate passed client-side SHA gate", 11)
		return

	# No credential is ever stored in the local submission state contract.
	var script_source := FileAccess.get_file_as_string("res://scripts/core_candidate_submitter.gd")
	if not script_source.contains("AURORAFOX_PROMOTION_API_TOKEN"):
		_fail("credential source contract missing", 12)
		return
	if script_source.contains("token\":") or script_source.contains("api_key\":"):
		_fail("submitter appears to persist a credential field", 13)
		return

	_cleanup(fixture_root)
	submitter.queue_free()
	print("CORE_CANDIDATE_SUBMITTER_SMOKE_OK credential_gated=true sha_guard=true")
	quit(0)

func _sha256_text(text: String) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if ctx.update(text.to_utf8_buffer()) != OK:
		return ""
	return ctx.finish().hex_encode()

func _cleanup(root_path: String) -> void:
	var absolute := ProjectSettings.globalize_path(root_path)
	if DirAccess.dir_exists_absolute(absolute):
		_remove_tree(absolute)

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		var child := path.path_join(name)
		if dir.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
