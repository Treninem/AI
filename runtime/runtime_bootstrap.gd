class_name AuroraRuntimeBootstrap
extends Node

var developer_godot := ""

func _ready() -> void:
	if OS.get_name() != "Windows": return
	var executable := OS.get_executable_path().replace("\\", "/")
	if OS.has_feature("editor"):
		developer_godot = executable
	else:
		var candidate := executable.get_base_dir().path_join("runtime/developer/godot.exe")
		if FileAccess.file_exists(candidate): developer_godot = candidate
	if developer_godot.is_empty(): return
	var bin_dir := developer_godot.get_base_dir().replace("/", "\\")
	var current := OS.get_environment("PATH")
	var exists := false
	for entry in current.split(";", false):
		if entry.strip_edges().to_lower() == bin_dir.to_lower():
			exists = true
			break
	if not exists:
		OS.set_environment("PATH", bin_dir + (";" + current if not current.is_empty() else ""))
	OS.set_environment("AURORAFOX_GODOT_BIN", developer_godot.replace("/", "\\"))

func has_developer_godot() -> bool:
	return not developer_godot.is_empty() and FileAccess.file_exists(developer_godot)

func godot_path() -> String:
	return developer_godot
