class_name DeveloperRuntimeManager
extends Node

const GODOT_VERSION := "4.7.1"
const GODOT_ZIP_URL := "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_win64.exe.zip"
const RUNTIME_DIR := "user://developer_runtime"
const ZIP_PATH := "user://developer_runtime/godot-4.7.1.zip"
const EXE_PATH := "user://developer_runtime/godot.exe"
const STATE_PATH := "user://developer_runtime/state.json"

signal progress(stage: String, value: int, message: String)

var developer_godot := ""

func _ready() -> void:
	_detect_existing()

func ensure_ready() -> Dictionary:
	_detect_existing()
	if not developer_godot.is_empty():
		_configure_environment()
		return {"ok": true, "path": developer_godot, "downloaded": false}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Bundled developer Godot runtime is currently prepared for Windows only"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUNTIME_DIR))
	_emit("download", 10, "Загрузка Godot 4.7.1 developer runtime")
	var downloaded := await _download()
	if not downloaded.get("ok", false): return downloaded
	_emit("extract", 65, "Распаковка Godot 4.7.1")
	var extracted := _extract()
	if not extracted.get("ok", false): return extracted
	_detect_existing()
	if developer_godot.is_empty(): return {"ok": false, "error": "Developer Godot executable was not found after extraction"}
	_configure_environment()
	_emit("verify", 90, "Проверка developer runtime")
	var output: Array = []
	var code := OS.execute(developer_godot, PackedStringArray(["--version"]), output, true, false)
	if code != 0:
		return {"ok": false, "error": "Developer Godot failed --version", "output": "\n".join(output)}
	var version_text := "\n".join(output)
	if not version_text.contains(GODOT_VERSION):
		return {"ok": false, "error": "Unexpected Godot version", "output": version_text}
	_emit("ready", 100, "Godot %s developer runtime готов" % GODOT_VERSION)
	_save_state({"version": GODOT_VERSION, "path": developer_godot, "ready": true})
	return {"ok": true, "path": developer_godot, "downloaded": true, "version": version_text.strip_edges()}

func has_runtime() -> bool:
	_detect_existing()
	return not developer_godot.is_empty()

func path() -> String:
	_detect_existing()
	return developer_godot

func _detect_existing() -> void:
	developer_godot = ""
	if OS.get_name() != "Windows": return
	if OS.has_feature("editor"):
		var editor := OS.get_executable_path()
		if FileAccess.file_exists(editor): developer_godot = editor
		return
	var local := ProjectSettings.globalize_path(EXE_PATH)
	if FileAccess.file_exists(local):
		developer_godot = local
		return
	var packaged := OS.get_executable_path().get_base_dir().path_join("runtime/developer/godot.exe")
	if FileAccess.file_exists(packaged): developer_godot = packaged

func _configure_environment() -> void:
	if developer_godot.is_empty(): return
	var bin_dir := developer_godot.get_base_dir().replace("/", "\\")
	var current := OS.get_environment("PATH")
	var found := false
	for entry in current.split(";", false):
		if entry.strip_edges().to_lower() == bin_dir.to_lower():
			found = true
			break
	if not found: OS.set_environment("PATH", bin_dir + (";" + current if not current.is_empty() else ""))
	OS.set_environment("AURORAFOX_GODOT_BIN", developer_godot.replace("/", "\\"))

func _download() -> Dictionary:
	var absolute := ProjectSettings.globalize_path(ZIP_PATH)
	if FileAccess.file_exists(ZIP_PATH): DirAccess.remove_absolute(absolute)
	var request := HTTPRequest.new()
	request.timeout = 1800.0
	request.download_file = absolute
	add_child(request)
	var err := request.request(GODOT_ZIP_URL, PackedStringArray(["User-Agent: AuroraFox-DeveloperRuntime/%s" % GODOT_VERSION]))
	if err != OK:
		request.queue_free()
		return {"ok": false, "error": "Cannot start Godot runtime download: %s" % error_string(err)}
	var result: Array = await request.request_completed
	request.queue_free()
	var code := int(result[1])
	if code < 200 or code >= 300:
		DirAccess.remove_absolute(absolute)
		return {"ok": false, "error": "Godot runtime download HTTP %d" % code}
	if not FileAccess.file_exists(ZIP_PATH): return {"ok": false, "error": "Downloaded Godot archive is missing"}
	return {"ok": true}

func _extract() -> Dictionary:
	var reader := ZIPReader.new()
	var err := reader.open(ProjectSettings.globalize_path(ZIP_PATH))
	if err != OK: return {"ok": false, "error": "Cannot open downloaded Godot ZIP: %s" % error_string(err)}
	var selected := ""
	for file_name in reader.get_files():
		var lower := file_name.to_lower()
		if lower.ends_with(".exe") and not lower.ends_with("_console.exe") and lower.contains("godot_v4.7.1"):
			selected = file_name
			break
	if selected.is_empty():
		reader.close()
		return {"ok": false, "error": "Godot executable was not found inside ZIP"}
	var data := reader.read_file(selected)
	reader.close()
	if data.is_empty(): return {"ok": false, "error": "Godot executable inside ZIP is empty"}
	var out := FileAccess.open(EXE_PATH, FileAccess.WRITE)
	if out == null: return {"ok": false, "error": "Cannot write local developer Godot"}
	out.store_buffer(data)
	out.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ZIP_PATH))
	return {"ok": true, "entry": selected, "bytes": data.size()}

func _emit(stage: String, value: int, message: String) -> void:
	progress.emit(stage, value, message)
	_save_state({"stage": stage, "progress": value, "message": message, "version": GODOT_VERSION})

func _save_state(value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUNTIME_DIR))
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify(value, "  "))
	f.close()
