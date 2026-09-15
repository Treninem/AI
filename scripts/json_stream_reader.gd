class_name AuroraJsonStreamReader
extends RefCounted

const BUFFER_BYTES := 64 * 1024
const MAX_DEPTH := 256
const MAX_SCALAR_BYTES := 16 * 1024 * 1024
const MAX_RECORDS := 5_000_000

var _file: FileAccess
var _buffer := PackedByteArray()
var _buffer_pos := 0
var _byte_offset := 0
var _records := 0
var _max_depth_seen := 0
var _error := ""
var _on_value: Callable

func parse_file(path: String, on_value: Callable) -> Dictionary:
	_reset()
	_file = FileAccess.open(path, FileAccess.READ)
	if _file == null:
		return {"ok": false, "error": "Не удалось открыть JSON для потокового чтения", "path": path}
	_on_value = on_value
	_skip_ws()
	var ok := _parse_value("$", 0)
	if ok:
		_skip_ws()
		if _peek_byte() >= 0:
			_fail("После корневого JSON-значения обнаружены лишние данные")
			ok = false
	_file.close()
	_file = null
	if not ok:
		return {
			"ok": false,
			"error": _error if not _error.is_empty() else "Ошибка потокового разбора JSON",
			"path": path,
			"byte_offset": _byte_offset,
			"records": _records,
			"max_depth": _max_depth_seen
		}
	return {
		"ok": true,
		"path": path,
		"records": _records,
		"max_depth": _max_depth_seen,
		"bytes_read": _byte_offset,
		"parser": "aurora_json_stream_v1"
	}

func _reset() -> void:
	_file = null
	_buffer = PackedByteArray()
	_buffer_pos = 0
	_byte_offset = 0
	_records = 0
	_max_depth_seen = 0
	_error = ""
	_on_value = Callable()

func _parse_value(path: String, depth: int) -> bool:
	if depth > MAX_DEPTH:
		return _fail("JSON превышает допустимую глубину вложенности %d" % MAX_DEPTH)
	_max_depth_seen = maxi(_max_depth_seen, depth)
	_skip_ws()
	var b := _peek_byte()
	if b < 0:
		return _fail("Неожиданный конец JSON")
	match b:
		123:
			return _parse_object(path, depth + 1)
		91:
			return _parse_array(path, depth + 1)
		34:
			var string_result := _parse_string()
			if not bool(string_result.get("ok", false)):
				return false
			return _emit(path, string_result.get("value", ""))
		_:
			var scalar_result := _parse_scalar()
			if not bool(scalar_result.get("ok", false)):
				return false
			return _emit(path, scalar_result.get("value"))

func _parse_object(path: String, depth: int) -> bool:
	_get_byte() # {
	_skip_ws()
	if _peek_byte() == 125:
		_get_byte()
		return _emit(path, {})
	while true:
		if _peek_byte() != 34:
			return _fail("Ожидался строковый ключ объекта")
		var key_result := _parse_string()
		if not bool(key_result.get("ok", false)):
			return false
		var key := str(key_result.get("value", ""))
		_skip_ws()
		if _get_byte() != 58:
			return _fail("После ключа JSON ожидался ':'")
		var child_path := "%s[%s]" % [path, JSON.stringify(key)]
		if not _parse_value(child_path, depth):
			return false
		_skip_ws()
		var separator := _get_byte()
		if separator == 125:
			return true
		if separator != 44:
			return _fail("В объекте JSON ожидалась ',' или '}'")
		_skip_ws()

func _parse_array(path: String, depth: int) -> bool:
	_get_byte() # [
	_skip_ws()
	if _peek_byte() == 93:
		_get_byte()
		return _emit(path, [])
	var index := 0
	while true:
		if not _parse_value("%s[%d]" % [path, index], depth):
			return false
		index += 1
		_skip_ws()
		var separator := _get_byte()
		if separator == 93:
			return true
		if separator != 44:
			return _fail("В массиве JSON ожидалась ',' или ']'")
		_skip_ws()

func _parse_string() -> Dictionary:
	if _get_byte() != 34:
		_fail("Ожидалась строка JSON")
		return {"ok": false}
	var raw := PackedByteArray([34])
	var escaped := false
	while true:
		var b := _get_byte()
		if b < 0:
			_fail("Незавершённая строка JSON")
			return {"ok": false}
		raw.append(b)
		if raw.size() > MAX_SCALAR_BYTES:
			_fail("Одна строка JSON превышает лимит %d байт" % MAX_SCALAR_BYTES)
			return {"ok": false}
		if escaped:
			escaped = false
			continue
		if b == 92:
			escaped = true
			continue
		if b == 34:
			break
		if b < 32:
			_fail("Недопустимый управляющий символ внутри JSON-строки")
			return {"ok": false}
	var parser := JSON.new()
	if parser.parse(raw.get_string_from_utf8()) != OK:
		_fail("Некорректная JSON-строка: %s" % parser.get_error_message())
		return {"ok": false}
	return {"ok": true, "value": parser.data}

func _parse_scalar() -> Dictionary:
	var raw := PackedByteArray()
	while true:
		var b := _peek_byte()
		if b < 0 or _is_value_delimiter(b):
			break
		raw.append(_get_byte())
		if raw.size() > MAX_SCALAR_BYTES:
			_fail("Одно JSON-значение превышает лимит %d байт" % MAX_SCALAR_BYTES)
			return {"ok": false}
	if raw.is_empty():
		_fail("Пустое JSON-значение")
		return {"ok": false}
	var token := raw.get_string_from_utf8()
	var parser := JSON.new()
	if parser.parse(token) != OK:
		_fail("Некорректное JSON-значение '%s': %s" % [token.substr(0, 120), parser.get_error_message()])
		return {"ok": false}
	return {"ok": true, "value": parser.data}

func _emit(path: String, value: Variant) -> bool:
	if _records >= MAX_RECORDS:
		return _fail("JSON содержит больше %d потоковых записей" % MAX_RECORDS)
	if _on_value.is_valid():
		var result = _on_value.call(path, value)
		if result is Dictionary and not bool(result.get("ok", true)):
			return _fail(str(result.get("error", "Обработчик знания отклонил JSON-запись")))
		if result is bool and not result:
			return _fail("Обработчик знания отклонил JSON-запись")
	_records += 1
	return true

func _skip_ws() -> void:
	while true:
		var b := _peek_byte()
		if b not in [9, 10, 13, 32]:
			return
		_get_byte()

func _is_value_delimiter(b: int) -> bool:
	return b in [9, 10, 13, 32, 44, 93, 125]

func _peek_byte() -> int:
	if not _ensure_buffer():
		return -1
	return int(_buffer[_buffer_pos])

func _get_byte() -> int:
	if not _ensure_buffer():
		return -1
	var value := int(_buffer[_buffer_pos])
	_buffer_pos += 1
	_byte_offset += 1
	return value

func _ensure_buffer() -> bool:
	if _file == null:
		return false
	if _buffer_pos < _buffer.size():
		return true
	if _file.eof_reached():
		return false
	var remaining := _file.get_length() - _file.get_position()
	if remaining <= 0:
		return false
	_buffer = _file.get_buffer(mini(BUFFER_BYTES, remaining))
	_buffer_pos = 0
	return not _buffer.is_empty()

func _fail(message: String) -> bool:
	if _error.is_empty():
		_error = "%s (байт %d)" % [message, _byte_offset]
	return false
