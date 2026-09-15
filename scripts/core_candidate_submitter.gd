class_name CoreCandidateSubmitter
extends Node

signal candidate_submission_started(candidate_id: String)
signal candidate_submitted(candidate_id: String, response: Dictionary)
signal candidate_submission_failed(candidate_id: String, error: String)

const CANDIDATE_ROOT := "user://core_candidates"
const SUBMISSION_STATE_NAME := "submission.json"
const API_URL_ENV := "AURORAFOX_PROMOTION_API_URL"
const API_TOKEN_ENV := "AURORAFOX_PROMOTION_API_TOKEN"
const MAX_SOURCE_BYTES := 1024 * 1024
const SCAN_INTERVAL_SECONDS := 60.0
const MAX_SCAN_CANDIDATES := 50
const MIN_RETRY_SECONDS := 30.0
const MAX_RETRY_SECONDS := 3600.0

var _timer: Timer
var _busy := false

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = SCAN_INTERVAL_SECONDS
	_timer.one_shot = false
	_timer.timeout.connect(_scan_once)
	add_child(_timer)
	_timer.start()
	call_deferred("_scan_once")

func configured() -> bool:
	var endpoint := _endpoint()
	var token := _token()
	return not endpoint.is_empty() and not token.is_empty() and _endpoint_allowed(endpoint)

func configuration_status() -> Dictionary:
	var endpoint := _endpoint()
	return {
		"configured": configured(),
		"endpoint": endpoint,
		"token_present": not _token().is_empty(),
		"network_enabled": configured(),
		"token_source": "environment" if not _token().is_empty() else "none",
		"candidate_root": CANDIDATE_ROOT
	}

func scan_now() -> Dictionary:
	return await _scan_once()

func build_submission(manifest_path: String, candidate_path: String, source := "") -> Dictionary:
	if not FileAccess.file_exists(manifest_path):
		return {"ok": false, "error": "candidate manifest missing"}
	if not FileAccess.file_exists(candidate_path):
		return {"ok": false, "error": "candidate source missing"}
	var manifest_text := FileAccess.get_file_as_string(manifest_path)
	var parsed = JSON.parse_string(manifest_text)
	if not parsed is Dictionary:
		return {"ok": false, "error": "candidate manifest is invalid JSON"}
	var manifest: Dictionary = parsed
	if not bool(manifest.get("verified", false)):
		return {"ok": false, "error": "candidate is not locally verified"}
	if str(manifest.get("promotion", "")) != "signed_update":
		return {"ok": false, "error": "candidate is not staged for signed update"}
	var target := str(manifest.get("target", ""))
	if target.is_empty() or target.begins_with("/") or target.contains("..") or target.contains("\\"):
		return {"ok": false, "error": "candidate target is invalid"}
	var bytes := FileAccess.get_file_as_bytes(candidate_path)
	if bytes.is_empty():
		return {"ok": false, "error": "candidate source is empty"}
	if bytes.size() > MAX_SOURCE_BYTES:
		return {"ok": false, "error": "candidate source exceeds submission size limit"}
	var expected_sha := str(manifest.get("candidate_sha256", "")).to_lower()
	var actual_sha := _sha256_bytes(bytes)
	if expected_sha.length() != 64 or expected_sha != actual_sha:
		return {"ok": false, "error": "candidate SHA-256 does not match manifest", "actual_sha256": actual_sha}
	var device_source := source.strip_edges()
	if device_source.is_empty():
		device_source = "%s-client" % OS.get_name().to_lower().replace(" ", "-")
	return {
		"ok": true,
		"payload": {
			"manifest": manifest,
			"content_base64": Marshalls.raw_to_base64(bytes),
			"source": device_source
		}
	}

func submit_candidate(manifest_path: String, candidate_path: String, source := "") -> Dictionary:
	if not configured():
		return {"ok": false, "pending": true, "error": "Core candidate promotion endpoint/token is not configured"}
	var built := build_submission(manifest_path, candidate_path, source)
	if not bool(built.get("ok", false)):
		return built
	var manifest: Dictionary = (built.get("payload", {}) as Dictionary).get("manifest", {})
	var candidate_id := str(manifest.get("candidate_id", ""))
	candidate_submission_started.emit(candidate_id)
	var request := HTTPRequest.new()
	request.timeout = 25.0
	add_child(request)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"Authorization: Bearer " + _token(),
		"User-Agent: AuroraFox-Core-Candidate/%s" % str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	])
	var err := request.request(_endpoint() + "/v1/core-candidates", headers, HTTPClient.METHOD_POST, JSON.stringify(built.get("payload", {})))
	if err != OK:
		request.queue_free()
		var message := "candidate submission request failed: %s" % error_string(err)
		candidate_submission_failed.emit(candidate_id, message)
		return {"ok": false, "pending": true, "error": message}
	var response: Array = await request.request_completed
	request.queue_free()
	var code := int(response[1])
	var raw: PackedByteArray = response[3]
	var text := raw.get_string_from_utf8().strip_edges()
	var parsed = JSON.parse_string(text) if not text.is_empty() else {}
	var body: Dictionary = parsed if parsed is Dictionary else {"raw": text.substr(0, 2000)}
	if code < 200 or code >= 300 or not bool(body.get("ok", false)):
		var message := "candidate submission HTTP %d: %s" % [code, str(body.get("detail", body.get("error", "server rejected candidate"))).substr(0, 1200)]
		candidate_submission_failed.emit(candidate_id, message)
		return {"ok": false, "pending": code >= 500 or code == 429, "http": code, "error": message, "response": body}
	candidate_submitted.emit(candidate_id, body)
	return {"ok": true, "http": code, "response": body}

func _scan_once() -> Dictionary:
	if _busy:
		return {"ok": false, "busy": true}
	if not configured():
		return {"ok": true, "configured": false, "submitted": 0, "pending": 0}
	_busy = true
	var submitted := 0
	var pending := 0
	var failed := 0
	var scanned := 0
	var now := Time.get_unix_time_from_system()
	var root := DirAccess.open(CANDIDATE_ROOT)
	if root == null:
		_busy = false
		return {"ok": true, "configured": true, "submitted": 0, "pending": 0}
	root.list_dir_begin()
	while scanned < MAX_SCAN_CANDIDATES:
		var name := root.get_next()
		if name.is_empty():
			break
		if not root.current_is_dir() or name.begins_with("."):
			continue
		scanned += 1
		var candidate_root := CANDIDATE_ROOT.path_join(name)
		var manifest_path := candidate_root.path_join("candidate.json")
		if not FileAccess.file_exists(manifest_path):
			continue
		var manifest_parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not manifest_parsed is Dictionary:
			continue
		var manifest: Dictionary = manifest_parsed
		if not bool(manifest.get("verified", false)) or str(manifest.get("promotion", "")) != "signed_update":
			continue
		var target := str(manifest.get("target", ""))
		if target.is_empty() or target.contains(".."):
			continue
		var candidate_path := candidate_root.path_join(target)
		if not FileAccess.file_exists(candidate_path):
			continue
		var state_path := candidate_root.path_join(SUBMISSION_STATE_NAME)
		var state := _read_state(state_path)
		if bool(state.get("submitted", false)):
			continue
		if float(state.get("next_retry_unix", 0.0)) > now:
			pending += 1
			continue
		var result := await submit_candidate(manifest_path, candidate_path)
		if bool(result.get("ok", false)):
			submitted += 1
			_write_state(state_path, {
				"submitted": true,
				"candidate_id": str(manifest.get("candidate_id", name)),
				"submitted_at": Time.get_datetime_string_from_system(true),
				"server": result.get("response", {}),
				"attempts": int(state.get("attempts", 0)) + 1,
				"next_retry_unix": 0.0
			})
		else:
			failed += 1
			var attempts := int(state.get("attempts", 0)) + 1
			var retry := minf(MAX_RETRY_SECONDS, MIN_RETRY_SECONDS * pow(2.0, float(mini(attempts - 1, 7))))
			var retryable := bool(result.get("pending", true))
			_write_state(state_path, {
				"submitted": false,
				"candidate_id": str(manifest.get("candidate_id", name)),
				"attempts": attempts,
				"last_attempt_at": Time.get_datetime_string_from_system(true),
				"last_error": str(result.get("error", "submission failed")).substr(0, 2000),
				"retryable": retryable,
				"next_retry_unix": now + retry if retryable else 0.0
			})
			if retryable:
				pending += 1
	root.list_dir_end()
	_busy = false
	return {"ok": true, "configured": true, "scanned": scanned, "submitted": submitted, "pending": pending, "failed": failed}

func _read_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _write_state(path: String, state: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(state, "  "))
	file.close()
	var absolute := ProjectSettings.globalize_path(path)
	var temp_absolute := ProjectSettings.globalize_path(temp)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute)
	DirAccess.rename_absolute(temp_absolute, absolute)

func _endpoint() -> String:
	return OS.get_environment(API_URL_ENV).strip_edges().trim_suffix("/")

func _token() -> String:
	return OS.get_environment(API_TOKEN_ENV).strip_edges()

func _endpoint_allowed(endpoint: String) -> bool:
	if endpoint.begins_with("https://"):
		return true
	return endpoint.begins_with("http://127.0.0.1") or endpoint.begins_with("http://localhost")

func _sha256_bytes(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if ctx.update(data) != OK:
		return ""
	return ctx.finish().hex_encode()
