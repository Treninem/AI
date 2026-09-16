class_name AuroraBundledCoreModel
extends RefCounted

# Internal AuroraFox Core weights. These are an implementation detail of the
# application, not a user-selected external provider/model.
const ACTIVE_MODEL := "user://models/aurorafox-main.gguf"
const BUNDLED_RESOURCE := "res://models/bundled/aurorafox-core.gguf"
const BUNDLED_WINDOWS_RELATIVE := "models/aurorafox-core.gguf"
const EXPECTED_BYTES := 1282439264
const EXPECTED_SHA256 := "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5"
const METADATA_PATH := "user://models/bundled_core.json"

static func runtime_candidate() -> String:
	# A developer-installed override remains supported, but normal users never
	# need to know about GGUF files. The shipped Core is always the fallback.
	if _valid_gguf(ACTIVE_MODEL):
		return ACTIVE_MODEL
	if OS.get_name() == "Windows":
		var packaged := windows_packaged_path()
		return packaged if _valid_bundled_file(packaged) else ""
	if OS.get_name() == "Android":
		var ready := ensure_android_private_copy()
		return str(ready.get("path", "")) if bool(ready.get("ok", false)) else ""
	return ""

static func windows_packaged_path() -> String:
	if OS.get_name() != "Windows":
		return ""
	return OS.get_executable_path().get_base_dir().path_join(BUNDLED_WINDOWS_RELATIVE)

static func bundled_available() -> bool:
	if OS.get_name() == "Windows":
		return _valid_bundled_file(windows_packaged_path())
	if OS.get_name() == "Android":
		return FileAccess.file_exists(BUNDLED_RESOURCE)
	return false

static func ensure_android_private_copy() -> Dictionary:
	if OS.get_name() != "Android":
		return {"ok": false, "error": "android-only provisioner"}
	if _valid_gguf(ACTIVE_MODEL):
		return {"ok": true, "path": ACTIVE_MODEL, "already_ready": true}
	if not FileAccess.file_exists(BUNDLED_RESOURCE):
		return {"ok": false, "error": "bundled AuroraFox Core asset missing"}

	var source := FileAccess.open(BUNDLED_RESOURCE, FileAccess.READ)
	if source == null:
		return {"ok": false, "error": "cannot open bundled AuroraFox Core asset"}
	var source_size := source.get_length()
	if source_size != EXPECTED_BYTES:
		source.close()
		return {"ok": false, "error": "bundled AuroraFox Core size mismatch", "expected": EXPECTED_BYTES, "actual": source_size}
	var magic := source.get_buffer(4).get_string_from_ascii()
	if magic != "GGUF":
		source.close()
		return {"ok": false, "error": "bundled AuroraFox Core header invalid"}
	source.seek(0)

	var target_abs := ProjectSettings.globalize_path(ACTIVE_MODEL)
	DirAccess.make_dir_recursive_absolute(target_abs.get_base_dir())
	var temp := ACTIVE_MODEL + ".bundled"
	var temp_abs := ProjectSettings.globalize_path(temp)
	if FileAccess.file_exists(temp):
		DirAccess.remove_absolute(temp_abs)
	var target := FileAccess.open(temp, FileAccess.WRITE)
	if target == null:
		source.close()
		return {"ok": false, "error": "cannot create private AuroraFox Core file"}

	while source.get_position() < source_size:
		var remaining := source_size - source.get_position()
		var block := source.get_buffer(mini(4 * 1024 * 1024, remaining))
		if block.is_empty():
			target.close()
			source.close()
			DirAccess.remove_absolute(temp_abs)
			return {"ok": false, "error": "bundled AuroraFox Core copy ended unexpectedly"}
		target.store_buffer(block)
	target.close()
	source.close()

	var temp_file := FileAccess.open(temp, FileAccess.READ)
	if temp_file == null:
		return {"ok": false, "error": "private AuroraFox Core copy missing"}
	var copied_size := temp_file.get_length()
	temp_file.close()
	if copied_size != EXPECTED_BYTES:
		DirAccess.remove_absolute(temp_abs)
		return {"ok": false, "error": "private AuroraFox Core size mismatch", "actual": copied_size}
	var copied_hash := FileAccess.get_sha256(temp).to_lower()
	if copied_hash != EXPECTED_SHA256:
		DirAccess.remove_absolute(temp_abs)
		return {"ok": false, "error": "private AuroraFox Core integrity check failed", "actual": copied_hash}

	if FileAccess.file_exists(ACTIVE_MODEL):
		DirAccess.remove_absolute(target_abs)
	var move_error := DirAccess.rename_absolute(temp_abs, target_abs)
	if move_error != OK:
		DirAccess.remove_absolute(temp_abs)
		return {"ok": false, "error": "cannot activate bundled AuroraFox Core", "code": move_error}
	_write_metadata()
	return {"ok": true, "path": ACTIVE_MODEL, "sha256": EXPECTED_SHA256, "bytes": EXPECTED_BYTES, "bundled": true}

static func _valid_bundled_file(path: String) -> bool:
	if path.is_empty() or not _valid_gguf(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var size := file.get_length()
	file.close()
	return size == EXPECTED_BYTES

static func _valid_gguf(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	if file.get_length() < 1024 * 1024:
		file.close()
		return false
	var magic := file.get_buffer(4).get_string_from_ascii()
	file.close()
	return magic == "GGUF"

static func _write_metadata() -> void:
	var file := FileAccess.open(METADATA_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"source": "bundled_aurorafox_core",
		"sha256": EXPECTED_SHA256,
		"bytes": EXPECTED_BYTES,
		"provisioned_at": Time.get_datetime_string_from_system(true)
	}, "  "))
	file.close()
