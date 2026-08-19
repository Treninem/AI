class_name LocalModelManager
extends Node

signal download_started(profile: String, expected_bytes: int)
signal download_progress(profile: String, downloaded_bytes: int, expected_bytes: int)
signal download_finished(profile: String, ok: bool, message: String)

const MODEL_DIR := "user://models"
const ACTIVE_MODEL := "user://models/aurorafox-main.gguf"

const PROFILES := {
	"mobile_lite": {
		"name": "Qwen3 1.7B Q4_K_M",
		"url": "https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf?download=true",
		"bytes": 1282439264,
		"sha256": "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5",
		"min_ram_mb": 4096,
		"recommended_ram_mb": 6144
	},
	"mobile_standard": {
		"name": "Qwen3 4B Q4_K_M",
		"url": "https://huggingface.co/ggml-org/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf?download=true",
		"bytes": 2497280640,
		"sha256": "ab27b9bfa375a178d6cba48f3ad892b94b7739659dcc7aae8058ce0ffed6b328",
		"min_ram_mb": 6144,
		"recommended_ram_mb": 8192
	}
}

var android_runtime := AndroidLocalRuntime.new()
var current_request: HTTPRequest
var current_profile := ""
var progress_timer: Timer
var _completion_ready := false
var _completion: Array = []
var _cancel_requested := false
var _reported_total_bytes := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MODEL_DIR))
	add_child(android_runtime)
	progress_timer = Timer.new()
	progress_timer.wait_time = 0.5
	progress_timer.timeout.connect(_emit_progress)
	add_child(progress_timer)

func status() -> Dictionary:
	return {
		"ok": true,
		"installed": FileAccess.file_exists(ACTIVE_MODEL),
		"path": ACTIVE_MODEL,
		"size": _file_size(ACTIVE_MODEL),
		"recommended_profile": recommend_profile(),
		"profiles": PROFILES,
		"downloading": current_request != null,
		"device": android_runtime.capabilities() if OS.get_name() == "Android" else {"platform": OS.get_name()}
	}

func recommend_profile() -> String:
	if OS.get_name() != "Android": return "mobile_standard"
	var caps := android_runtime.capabilities()
	var ram_mb := int(caps.get("total_ram_mb", 0))
	var free_mb := int(caps.get("free_storage_mb", 0))
	if ram_mb >= 8192 and free_mb >= 4200: return "mobile_standard"
	return "mobile_lite"

func download_recommended() -> Dictionary:
	return await download_profile(recommend_profile())

func download_profile(profile_id: String) -> Dictionary:
	if not PROFILES.has(profile_id): return {"ok": false, "error": "Unknown model profile"}
	if current_request != null: return {"ok": false, "error": "A model download is already running"}
	var profile: Dictionary = PROFILES[profile_id]
	if OS.get_name() == "Android":
		var caps := android_runtime.capabilities()
		var free_mb := int(caps.get("free_storage_mb", 0))
		var required_mb := int(ceil(float(profile.get("bytes", 0)) / 1048576.0)) + 512
		if free_mb > 0 and free_mb < required_mb:
			return {"ok": false, "error": "Not enough free storage", "required_mb": required_mb, "free_mb": free_mb}

	var temp_path := ACTIVE_MODEL + ".download"
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(temp_path): DirAccess.remove_absolute(temp_absolute)
	current_profile = profile_id
	_completion_ready = false
	_completion.clear()
	_cancel_requested = false
	_reported_total_bytes = int(profile.get("bytes", 0))

	current_request = HTTPRequest.new()
	current_request.timeout = 0.0
	current_request.use_threads = true
	current_request.accept_gzip = false
	current_request.body_size_limit = -1
	current_request.download_chunk_size = 1024 * 1024
	current_request.download_file = temp_absolute
	current_request.request_completed.connect(_on_request_completed, CONNECT_ONE_SHOT)
	add_child(current_request)
	download_started.emit(profile_id, _reported_total_bytes)
	progress_timer.start()
	var err := current_request.request(
		str(profile.get("url", "")),
		PackedStringArray(["User-Agent: AuroraFox/0.4.0", "Accept-Encoding: identity"]),
		HTTPClient.METHOD_GET
	)
	if err != OK:
		progress_timer.stop()
		_cleanup_request()
		var start_error := "Download request failed: %s" % error_string(err)
		download_finished.emit(profile_id, false, start_error)
		return {"ok": false, "error": start_error}

	while not _completion_ready and not _cancel_requested:
		await get_tree().process_frame

	progress_timer.stop()
	if _cancel_requested:
		if current_request != null: current_request.cancel_request()
		_cleanup_request()
		if FileAccess.file_exists(temp_path): DirAccess.remove_absolute(temp_absolute)
		download_finished.emit(profile_id, false, "Download cancelled")
		return {"ok": false, "cancelled": true, "error": "Download cancelled"}

	var completed := _completion.duplicate()
	var final_body_size := current_request.get_body_size() if current_request != null else -1
	_cleanup_request()
	if completed.size() < 4:
		if FileAccess.file_exists(temp_path): DirAccess.remove_absolute(temp_absolute)
		var malformed := "Model download ended without a complete HTTP result"
		download_finished.emit(profile_id, false, malformed)
		return {"ok": false, "error": malformed}

	var result_code := int(completed[0])
	var http_code := int(completed[1])
	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		if FileAccess.file_exists(temp_path): DirAccess.remove_absolute(temp_absolute)
		var message := "Model download failed: result=%d http=%d" % [result_code, http_code]
		download_finished.emit(profile_id, false, message)
		return {"ok": false, "error": message}
	if not FileAccess.file_exists(temp_path):
		var missing := "Downloaded model file is missing"
		download_finished.emit(profile_id, false, missing)
		return {"ok": false, "error": missing}

	var actual_size := _file_size(temp_path)
	if final_body_size > 0 and actual_size != final_body_size:
		DirAccess.remove_absolute(temp_absolute)
		var size_error := "Downloaded byte count does not match HTTP body size"
		download_finished.emit(profile_id, false, size_error)
		return {"ok": false, "error": size_error, "expected_bytes": final_body_size, "actual_bytes": actual_size}

	var expected_hash := str(profile.get("sha256", "")).to_lower()
	var actual_hash := FileAccess.get_sha256(temp_path).to_lower()
	if expected_hash.is_empty() or actual_hash != expected_hash:
		DirAccess.remove_absolute(temp_absolute)
		var hash_error := "SHA-256 verification failed"
		download_finished.emit(profile_id, false, hash_error)
		return {"ok": false, "error": hash_error, "expected": expected_hash, "actual": actual_hash}

	var activation := _activate_temp_model(temp_path)
	if not activation.get("ok", false):
		download_finished.emit(profile_id, false, str(activation.get("error", "Cannot activate downloaded model")))
		return activation
	_write_metadata(profile_id, profile, actual_hash, actual_size)
	download_progress.emit(profile_id, actual_size, actual_size)
	download_finished.emit(profile_id, true, "Model installed")
	return {"ok": true, "profile": profile_id, "path": ACTIVE_MODEL, "sha256": actual_hash, "bytes": actual_size}

func install_local_gguf(source_path: String) -> Dictionary:
	if current_request != null: return {"ok": false, "error": "Wait for the current model download to finish"}
	if source_path.get_extension().to_lower() != "gguf": return {"ok": false, "error": "Only GGUF files are accepted"}
	var source_absolute := _absolute_path(source_path)
	var active_absolute := ProjectSettings.globalize_path(ACTIVE_MODEL)
	if source_absolute.is_empty() or not FileAccess.file_exists(source_absolute): return {"ok": false, "error": "Source GGUF not found"}
	if source_absolute.replace("\\", "/") == active_absolute.replace("\\", "/"):
		return {"ok": true, "path": ACTIVE_MODEL, "sha256": FileAccess.get_sha256(ACTIVE_MODEL), "bytes": _file_size(ACTIVE_MODEL), "already_active": true}

	var source := FileAccess.open(source_absolute, FileAccess.READ)
	if source == null: return {"ok": false, "error": "Cannot open selected GGUF"}
	var source_size := source.get_length()
	if source_size < 1024 * 1024:
		source.close()
		return {"ok": false, "error": "Selected file is too small to be a model"}
	var magic := source.get_buffer(4).get_string_from_ascii()
	if magic != "GGUF":
		source.close()
		return {"ok": false, "error": "Selected file has no GGUF header"}
	source.seek(0)

	if OS.get_name() == "Android":
		var caps := android_runtime.capabilities()
		var free_mb := int(caps.get("free_storage_mb", 0))
		var required_mb := int(ceil(float(source_size) / 1048576.0)) + 256
		if free_mb > 0 and free_mb < required_mb:
			source.close()
			return {"ok": false, "error": "Not enough free storage to import GGUF", "required_mb": required_mb, "free_mb": free_mb}

	var temp_path := ACTIVE_MODEL + ".import"
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(temp_path): DirAccess.remove_absolute(temp_absolute)
	var target := FileAccess.open(temp_path, FileAccess.WRITE)
	if target == null:
		source.close()
		return {"ok": false, "error": "Cannot create temporary model file"}
	while source.get_position() < source_size:
		var remaining := source_size - source.get_position()
		var block := source.get_buffer(mini(1024 * 1024, remaining))
		if block.is_empty():
			target.close()
			source.close()
			DirAccess.remove_absolute(temp_absolute)
			return {"ok": false, "error": "Selected GGUF ended unexpectedly during copy"}
		target.store_buffer(block)
	target.close()
	source.close()
	if _file_size(temp_path) != source_size:
		DirAccess.remove_absolute(temp_absolute)
		return {"ok": false, "error": "Imported GGUF byte count mismatch"}

	var hash := FileAccess.get_sha256(temp_path).to_lower()
	if hash.is_empty():
		DirAccess.remove_absolute(temp_absolute)
		return {"ok": false, "error": "Cannot calculate GGUF SHA-256"}
	var activation := _activate_temp_model(temp_path)
	if not activation.get("ok", false): return activation
	_write_metadata("custom", {"name": source_path.get_file()}, hash, source_size)
	return {"ok": true, "path": ACTIVE_MODEL, "sha256": hash, "bytes": source_size, "custom": true}

func cancel_download() -> void:
	if current_request == null: return
	_cancel_requested = true
	current_request.cancel_request()
	progress_timer.stop()

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_completion = [result, response_code, headers, body]
	_completion_ready = true

func _emit_progress() -> void:
	if current_request == null or current_profile.is_empty(): return
	var body_size := current_request.get_body_size()
	if body_size > 0: _reported_total_bytes = body_size
	var downloaded := current_request.get_downloaded_bytes()
	download_progress.emit(current_profile, downloaded, maxi(_reported_total_bytes, downloaded))

func _cleanup_request() -> void:
	if current_request != null:
		current_request.queue_free()
		current_request = null
	current_profile = ""
	_completion_ready = false
	_completion.clear()
	_cancel_requested = false
	_reported_total_bytes = 0

func _activate_temp_model(temp_path: String) -> Dictionary:
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	var active_absolute := ProjectSettings.globalize_path(ACTIVE_MODEL)
	if not FileAccess.file_exists(temp_path): return {"ok": false, "error": "Temporary model is missing"}
	var previous_path := ACTIVE_MODEL + ".previous"
	var previous_absolute := ProjectSettings.globalize_path(previous_path)
	if FileAccess.file_exists(previous_path): DirAccess.remove_absolute(previous_absolute)
	var had_active := FileAccess.file_exists(ACTIVE_MODEL)
	if had_active:
		var backup_error := DirAccess.rename_absolute(active_absolute, previous_absolute)
		if backup_error != OK: return {"ok": false, "error": "Cannot preserve current model before replacement", "code": backup_error}
	var rename_error := DirAccess.rename_absolute(temp_absolute, active_absolute)
	if rename_error != OK:
		if had_active and FileAccess.file_exists(previous_path): DirAccess.rename_absolute(previous_absolute, active_absolute)
		return {"ok": false, "error": "Cannot activate model", "code": rename_error}
	if FileAccess.file_exists(previous_path): DirAccess.remove_absolute(previous_absolute)
	return {"ok": true}

func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"): return ProjectSettings.globalize_path(path)
	return path

func _write_metadata(profile_id: String, profile: Dictionary, hash: String, bytes: int) -> void:
	var f := FileAccess.open(MODEL_DIR + "/active_model.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"profile": profile_id,
			"name": profile.get("name", ""),
			"sha256": hash,
			"bytes": bytes,
			"installed_at": Time.get_datetime_string_from_system(true)
		}, "  "))
		f.close()

func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return 0
	var size := f.get_length()
	f.close()
	return size
