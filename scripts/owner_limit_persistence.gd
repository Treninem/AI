class_name OwnerLimitPersistence
extends RefCounted

const PATH := "user://owner_operation_limits.cfg"

static func load_group(group: String, path: String = PATH) -> Dictionary:
	var file := ConfigFile.new()
	var error := file.load(path)
	if error == ERR_FILE_NOT_FOUND: return {"ok": true, "values": {}}
	if error != OK: return {"ok": false, "values": {}, "error": error_string(error)}
	var values: Dictionary = {}
	if file.has_section(group):
		for key in file.get_section_keys(group): values[key] = file.get_value(group, key)
	return {"ok": true, "values": values}

static func save_group(group: String, values: Dictionary, path: String = PATH) -> Error:
	var file := ConfigFile.new()
	var error := file.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND: return error
	for key in values: file.set_value(group, key, values[key])
	var temporary := path + ".%d.tmp" % Time.get_ticks_usec()
	error = file.save(temporary)
	if error != OK: return error
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK: DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	return error

static func valid_number(value: Variant, minimum: float, integral := true) -> bool:
	if not (value is int or value is float): return false
	var number := float(value)
	return is_finite(number) and number >= minimum and number < 9223372036854775807.0 and (not integral or number == floor(number))
