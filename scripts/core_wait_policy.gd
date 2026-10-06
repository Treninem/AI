class_name CoreWaitPolicy
extends RefCounted

const PATH := "user://core_wait.cfg"
const DEFAULTS := {"stall_timeout_seconds": 90.0, "total_timeout_seconds": 0.0, "response_max_bytes": 4194304}

static func limits(path: String = PATH) -> Dictionary:
	var file := ConfigFile.new()
	file.load(path)
	var out := DEFAULTS.duplicate()
	for key in DEFAULTS:
		var value = file.get_value("core", key, DEFAULTS[key])
		if ProjectSettings.has_setting("aurorafox/core/" + str(key)):
			value = ProjectSettings.get_setting("aurorafox/core/" + str(key))
		if (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) < (9223372036854775807.0 if key == "response_max_bytes" else 9223372036854775.0):
			out[key] = int(value) if key == "response_max_bytes" else float(value)
	return out

static func save(values: Dictionary, path: String = PATH) -> Error:
	var file := ConfigFile.new()
	for key in DEFAULTS:
		var value = values.get(key, DEFAULTS[key])
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) >= (9223372036854775807.0 if key == "response_max_bytes" else 9223372036854775.0):
			return ERR_INVALID_PARAMETER
		file.set_value("core", key, int(value) if key == "response_max_bytes" else float(value))
	var err := file.save(path)
	if err == OK:
		for key in DEFAULTS: ProjectSettings.set_setting("aurorafox/core/" + str(key), file.get_value("core", key))
	return err
