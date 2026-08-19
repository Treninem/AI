class_name AuroraPremiumAssetPack
extends RefCounted

const PART_ROOT := "res://assets/ui/AuroraFox_UI/runtime_parts/"
const USER_ZIP := "user://aurorafox_ui_v1.1.2.2.zip"
const EXPECTED_SHA256 := "b1ac114d1125cc1b6fbfaa15ba80e65f8aed64101af3e7c7a4c8268b94af0da1"
const EXPECTED_PNG_COUNT := 75
const PART_FILES: Array[String] = [
	"part_01.txt", "part_02.txt", "part_03.txt", "part_04.txt",
	"part_05.txt", "part_06.txt", "part_07.txt", "part_08.txt",
	"suffix_09_16.txt"
]

var _reader: ZIPReader
var _files: Dictionary = {}
var _textures: Dictionary = {}
var _ready := false
var _error := ""

func prepare() -> bool:
	if _ready:
		return true
	_error = ""
	var encoded := ""
	for filename in PART_FILES:
		var path := PART_ROOT + filename
		if not FileAccess.file_exists(path):
			_error = "missing_pack_part:%s" % filename
			return false
		encoded += FileAccess.get_file_as_string(path).strip_edges()
	if encoded.is_empty():
		_error = "empty_pack"
		return false

	var bytes := Marshalls.base64_to_raw(encoded)
	if bytes.is_empty():
		_error = "base64_decode_failed"
		return false
	if _sha256(bytes) != EXPECTED_SHA256:
		_error = "sha256_mismatch"
		return false

	var out := FileAccess.open(USER_ZIP, FileAccess.WRITE)
	if out == null:
		_error = "cannot_write_runtime_zip"
		return false
	out.store_buffer(bytes)
	out.close()

	_reader = ZIPReader.new()
	var open_error := _reader.open(USER_ZIP)
	if open_error != OK:
		_error = "zip_open_failed:%s" % open_error
		_reader = null
		return false

	_files.clear()
	var png_count := 0
	for member in _reader.get_files():
		_files[str(member)] = true
		if str(member).to_lower().ends_with(".png"):
			png_count += 1
	if png_count != EXPECTED_PNG_COUNT:
		_error = "png_count:%d" % png_count
		close()
		return false

	for required in [
		"icons/aurorafox_logo.png",
		"icons/aurorafox_app_icon.png",
		"backgrounds/aurorafox_chat_background.png",
		"buttons/btn_new_chat_normal.png",
		"buttons/btn_new_chat_hover.png",
		"buttons/btn_new_chat_pressed.png",
		"buttons/btn_new_chat_disabled.png"
	]:
		if not _files.has(required):
			_error = "missing_member:%s" % required
			close()
			return false

	_ready = true
	return true

func has(relative_path: String) -> bool:
	return _ready and _files.has(relative_path)

func texture(relative_path: String) -> Texture2D:
	if not _ready and not prepare():
		return null
	if _textures.has(relative_path):
		return _textures[relative_path] as Texture2D
	if _reader == null or not _files.has(relative_path):
		return null
	var data := _reader.read_file(relative_path)
	if data.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(data) != OK:
		return null
	var result := ImageTexture.create_from_image(image)
	_textures[relative_path] = result
	return result

func image_size(relative_path: String) -> Vector2i:
	var tex := texture(relative_path)
	if tex == null:
		return Vector2i.ZERO
	return Vector2i(tex.get_width(), tex.get_height())

func png_count() -> int:
	if not _ready and not prepare():
		return 0
	var count := 0
	for member in _files.keys():
		if str(member).to_lower().ends_with(".png"):
			count += 1
	return count

func status() -> Dictionary:
	return {
		"ready": _ready,
		"error": _error,
		"png_count": png_count() if _ready else 0,
		"expected_png_count": EXPECTED_PNG_COUNT,
		"zip_sha256": EXPECTED_SHA256
	}

func close() -> void:
	if _reader != null:
		_reader.close()
		_reader = null
	_ready = false
	_textures.clear()
	_files.clear()

func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()
