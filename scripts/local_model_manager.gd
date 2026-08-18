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
		"bytes": 1280000000,
		"sha256": "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5",
		"min_ram_mb": 4096,
		"recommended_ram_mb": 6144
	},
	"mobile_standard": {
		"name": "Qwen3 4B Q4_K_M",
		"url": "https://huggingface.co/ggml-org/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf?download=true",
		"bytes": 2500000000,
		"sha256": "ab27b9bfa375a178d6cba48f3ad892b94b7739659dcc7aae8058ce0ffed6b328",
		"min_ram_mb": 6144,
		"recommended_ram_mb": 8192
	}
}

var android_runtime := AndroidLocalRuntime.new()
var current_request: HTTPRequest
var current_profile := ""
var progress_timer: Timer

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MODEL_DIR))
	add_child(android_runtime)
	progress_timer = Timer.new()
	progress_timer.wait_time = 0.5
	progress_timer.timeout.connect(_emit_progress)
	add_child(progress_timer)

func status() -> Dictionary:
	var recommendation := recommend_profile()
	return {
		"ok": true,
		"installed": FileAccess.file_exists(ACTIVE_MODEL),
		"path": ACTIVE_MODEL,
		"size": FileAccess.get_file_as_bytes(ACTIVE_MODEL).size() if FileAccess.file_exists(ACTIVE_MODEL) and _small_enough_for_size_probe() else _file_size(ACTIVE_MODEL),
		"recommended_profile": recommendation,
		"profiles": PROFILES,
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
	if FileAccess.file_exists(temp_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	current_profile = profile_id
	current_request = HTTPRequest.new()
	current_request.timeout = 0.0
	current_request.use_threads = true
	current_request.body_size_limit = -1
	current_request.download_chunk_size = 1024 * 1024
	current_request.download_file = temp_path
	add_child(current_request)
	download_started.emit(profile_id, int(profile.get("bytes", 0)))
	progress_timer.start()
	var err := current_request.request(str(profile.get("url", "")), PackedStringArray(["User-Agent: AuroraFox/0.3"]), HTTPClient.METHOD_GET)
	if err != OK:
		_cleanup_request()
		return {"ok": false, "error": "Download request failed: %s" % err}
	var completed: Array = await current_request.request_completed
	var result_code := int(completed[0])
	var http_code := int(completed[1])
	progress_timer.stop()
	_cleanup_request()
	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		var message := "Model download failed: result=%d http=%d" % [result_code, http_code]
		download_finished.emit(profile_id, false, message)
		return {"ok": false, "error": message}

	var expected_hash := str(profile.get("sha256", "")).to_lower()
	var actual_hash := FileAccess.get_sha256(temp_path).to_lower()
	if not expected_hash.is_empty() and actual_hash != expected_hash:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		var message := "SHA-256 verification failed"
		download_finished.emit(profile_id, false, message)
		return {"ok": false, "error": message, "expected": expected_hash, "actual": actual_hash}

	if FileAccess.file_exists(ACTIVE_MODEL): DirAccess.remove_absolute(ProjectSettings.globalize_path(ACTIVE_MODEL))
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(ACTIVE_MODEL))
	if rename_error != OK:
		download_finished.emit(profile_id, false, "Cannot activate downloaded model")
		return {"ok": false, "error": "Cannot activate downloaded model", "code": rename_error}
	_write_metadata(profile_id, profile, actual_hash)
	download_finished.emit(profile_id, true, "Model installed")
	return {"ok": true, "profile": profile_id, "path": ACTIVE_MODEL, "sha256": actual_hash}

func install_local_gguf(source_path: String) -> Dictionary:
	if not FileAccess.file_exists(source_path): return {"ok": false, "error": "Source GGUF not found"}
	if source_path.get_extension().to_lower() != "gguf": return {"ok": false, "error": "Only GGUF files are accepted"}
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(source_path), ProjectSettings.globalize_path(ACTIVE_MODEL))
	if err != OK: return {"ok": false, "error": "Cannot copy GGUF", "code": err}
	return {"ok": true, "path": ACTIVE_MODEL, "sha256": FileAccess.get_sha256(ACTIVE_MODEL)}

func cancel_download() -> void:
	if current_request != null: current_request.cancel_request()
	progress_timer.stop()
	_cleanup_request()

func _emit_progress() -> void:
	if current_request == null or current_profile.is_empty(): return
	var expected := int(PROFILES.get(current_profile, {}).get("bytes", 0))
	download_progress.emit(current_profile, current_request.get_downloaded_bytes(), expected)

func _cleanup_request() -> void:
	if current_request != null:
		current_request.queue_free()
		current_request = null
	current_profile = ""

func _write_metadata(profile_id: String, profile: Dictionary, hash: String) -> void:
	var f := FileAccess.open(MODEL_DIR + "/active_model.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"profile": profile_id, "name": profile.get("name", ""), "sha256": hash, "installed_at": Time.get_datetime_string_from_system(true)}, "  "))

func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0

func _small_enough_for_size_probe() -> bool:
	return false
