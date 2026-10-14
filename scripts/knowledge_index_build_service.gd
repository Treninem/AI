class_name KnowledgeIndexBuildService
extends Node

const IndexClientScript = preload("res://scripts/knowledge_index_client.gd")

# Owns one disposable Python build process. No build starts until a caller
# explicitly requests one after a successful Knowledge mutation.
var _pid := 0
var _cancel_path := ""
var _temp_prefix := ""
var _pending := false

func request_rebuild() -> bool:
	if OS.get_name() != "Windows" or not FileAccess.file_exists(KnowledgeStore.DB_PATH):
		return false
	if _pid > 0 and OS.is_process_running(_pid):
		_pending = true
		_cancel_current()
		return true
	if _pid > 0:
		_cleanup_job_files()
		_pid = 0
	return _start_build()

func is_building() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)

func _process(_delta: float) -> void:
	if _pid <= 0 or OS.is_process_running(_pid):
		return
	_cleanup_job_files()
	_pid = 0
	if _pending:
		_pending = false
		_start_build()

func _exit_tree() -> void:
	_pending = false
	if _pid > 0 and OS.is_process_running(_pid):
		_cancel_current()
		var deadline := Time.get_ticks_msec() + 2000
		while OS.is_process_running(_pid) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(20)
		if OS.is_process_running(_pid):
			OS.kill(_pid)
			var killed_deadline := Time.get_ticks_msec() + 1000
			while OS.is_process_running(_pid) and Time.get_ticks_msec() < killed_deadline:
				OS.delay_msec(20)
	_cleanup_job_files()
	_pid = 0

func _start_build() -> bool:
	var runtime := IndexClientScript._runtime_paths()
	if runtime.is_empty():
		return false
	var source := ProjectSettings.globalize_path(KnowledgeStore.DB_PATH)
	var index := ProjectSettings.globalize_path(IndexClientScript.INDEX_PATH)
	DirAccess.make_dir_recursive_absolute(index.get_base_dir())
	var job_id := str(Time.get_ticks_usec()) + "-" + str(randi())
	_cancel_path = index + "." + job_id + ".cancel"
	_temp_prefix = index.get_file() + "." + _cancel_path.get_file().get_basename() + "."
	var args := PackedStringArray([
		str(runtime["script"]), "build", "--source", source,
		"--index", index, "--cancel-file", _cancel_path,
	])
	_pid = OS.create_process(str(runtime["python"]), args, false)
	if _pid <= 0:
		_cleanup_job_files()
		_pid = 0
		return false
	return true

func _cancel_current() -> void:
	if _cancel_path.is_empty():
		return
	var file := FileAccess.open(_cancel_path, FileAccess.WRITE)
	if file != null:
		file.store_string("cancel\n")
		file.close()

func _cleanup_job_files() -> void:
	if not _cancel_path.is_empty():
		DirAccess.remove_absolute(_cancel_path)
		var folder := DirAccess.open(_cancel_path.get_base_dir())
		if folder != null:
			for name in folder.get_files():
				if name.begins_with(_temp_prefix) and name.ends_with(".building"):
					DirAccess.remove_absolute(_cancel_path.get_base_dir().path_join(name))
	_cancel_path = ""
	_temp_prefix = ""
