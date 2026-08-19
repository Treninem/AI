class_name WindowsTrustedProjectBridge
extends Node

const COMPUTER_URL := "http://127.0.0.1:8766"
const BACKUP_ROOT := "user://project_backups"
const MAX_COPY_FILES := 30000
const MAX_COPY_BYTES := 2 * 1024 * 1024 * 1024
const IGNORED_DIRS := [".git", ".godot", "node_modules", ".gradle", ".venv", "venv", "build", "dist", "target", "bin", "obj", "__pycache__"]

var _registered := false
var _sandbox_root_cache := ""

func _ready() -> void:
	if OS.get_name() != "Windows": return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BACKUP_ROOT))
	call_deferred("_register")

func _register() -> void:
	if _registered: return
	var main := get_parent()
	if main == null: return
	var registry = main.get("tools")
	if not registry is ToolRegistry: return
	# These names intentionally replace the generic bridge on Windows. The
	# generic bridge remains the fallback for non-Windows platforms.
	registry.register_tool("workspace_import_project", "Скопировать доверенный локальный проект в активную Windows-песочницу. Источник должен быть явно разрешён пользователем.", {"project_path":"string","target":"string","max_files":"int","max_bytes":"int"}, Callable(self, "_import_project"))
	registry.register_tool("trusted_project_read", "Прочитать конкретный текстовый файл из доверенного проекта.", {"project_path":"string","relative_path":"string","max_chars":"int"}, Callable(self, "_read_project_file"))
	registry.register_tool("project_compare_file", "Сравнить файл из Windows-песочницы с оригиналом доверенного проекта.", {"project_path":"string","relative_path":"string","sandbox_path":"string"}, Callable(self, "_compare_file"))
	registry.register_tool("project_apply_file", "Применить один проверенный файл из Windows-песочницы обратно в доверенный проект с резервной копией оригинала.", {"project_path":"string","relative_path":"string","sandbox_path":"string"}, Callable(self, "_apply_file"))
	_registered = true

func _project_bridge() -> ProjectIndexToolBridge:
	var main := get_parent()
	if main == null: return null
	return main.get_node_or_null("ProjectIndexTools") as ProjectIndexToolBridge

func _sandbox_bridge() -> SandboxToolBridge:
	var main := get_parent()
	if main == null: return null
	return main.get_node_or_null("SandboxTools") as SandboxToolBridge

func _trusted_root(path: String) -> String:
	var requested := path.strip_edges()
	var own_root := ProjectSettings.globalize_path("res://").replace("\\", "/")
	while own_root.ends_with("/") and own_root.length() > 3: own_root = own_root.trim_suffix("/")
	var requested_global := ProjectSettings.globalize_path(requested).replace("\\", "/") if requested.begins_with("res://") or requested.begins_with("user://") else requested.replace("\\", "/")
	while requested_global.ends_with("/") and requested_global.length() > 3: requested_global = requested_global.trim_suffix("/")
	if requested == "res://" or requested_global.to_lower() == own_root.to_lower(): return own_root
	var bridge := _project_bridge()
	if bridge == null or not bridge.access.is_trusted_root(path): return ""
	return bridge.access.normalize(path)

func _safe_relative(path: String) -> String:
	var p := path.replace("\\", "/").strip_edges().trim_prefix("/")
	if p.is_empty() or p == ".." or p.begins_with("../") or p.contains("/../") or p.contains(":"): return ""
	return p

func _service_sandbox_root() -> String:
	if not _sandbox_root_cache.is_empty() and DirAccess.dir_exists_absolute(_sandbox_root_cache): return _sandbox_root_cache
	var result := await _http_json(COMPUTER_URL + "/health")
	if not result.get("ok", false): return ""
	var root := str(result.get("sandbox_root", "")).replace("\\", "/")
	if root.is_empty() or not DirAccess.dir_exists_absolute(root): return ""
	_sandbox_root_cache = root
	return root

func _physical_workspace_root() -> String:
	var bridge := _sandbox_bridge()
	if bridge == null: return ""
	var ws := bridge.manager.get_active()
	if ws.is_empty(): return ""
	var id := str(ws.get("id", ""))
	if id.is_empty(): return ""
	var root := await _service_sandbox_root()
	if root.is_empty(): return ""
	var candidate := root.path_join(id).replace("\\", "/")
	# The service created this directory itself; never manufacture a different
	# workspace path from untrusted model input.
	if not DirAccess.dir_exists_absolute(candidate): return ""
	return candidate

func _import_project(args: Dictionary) -> Dictionary:
	var source := _trusted_root(str(args.get("project_path", "")))
	if source.is_empty(): return {"ok": false, "error": "Project root is not trusted"}
	var ws_root := await _physical_workspace_root()
	if ws_root.is_empty(): return {"ok": false, "error": "Windows sandbox service is unavailable or no workspace exists"}
	var target_rel := _safe_relative(str(args.get("target", "project")))
	if target_rel.is_empty(): return {"ok": false, "error": "Invalid sandbox target"}
	var target := ws_root.path_join("work").path_join(target_rel)
	var max_files := clampi(int(args.get("max_files", MAX_COPY_FILES)), 1, MAX_COPY_FILES)
	var max_bytes := clampi(int(args.get("max_bytes", MAX_COPY_BYTES)), 1024, MAX_COPY_BYTES)
	DirAccess.make_dir_recursive_absolute(target)
	var state := {"files": 0, "bytes": 0, "skipped": 0, "errors": [], "stopped": false}
	_copy_directory_limited(source, target, state, max_files, max_bytes)
	return {"ok": not bool(state.stopped), "project": source, "sandbox": target, "files": state.files, "bytes": state.bytes, "skipped": state.skipped, "errors": state.errors, "limit_reached": state.stopped}

func _copy_directory_limited(source: String, target: String, state: Dictionary, max_files: int, max_bytes: int) -> void:
	if bool(state.stopped): return
	var dir := DirAccess.open(source)
	if dir == null:
		state.errors.append("Cannot open: " + source)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "" and not bool(state.stopped):
		if name in [".", ".."]:
			name = dir.get_next()
			continue
		var src := source.path_join(name)
		var dst := target.path_join(name)
		if dir.current_is_dir():
			if name in IGNORED_DIRS or name.begins_with(".__"):
				state.skipped = int(state.skipped) + 1
			else:
				DirAccess.make_dir_recursive_absolute(dst)
				_copy_directory_limited(src, dst, state, max_files, max_bytes)
		else:
			var file := FileAccess.open(src, FileAccess.READ)
			if file == null:
				state.errors.append("Cannot read: " + src)
			else:
				var size := file.get_length()
				if int(state.files) + 1 > max_files or int(state.bytes) + size > max_bytes:
					file.close()
					state.stopped = true
					break
				DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
				var out := FileAccess.open(dst, FileAccess.WRITE)
				if out == null:
					file.close()
					state.errors.append("Cannot write: " + dst)
				else:
					while file.get_position() < size:
						out.store_buffer(file.get_buffer(mini(1024 * 1024, size - file.get_position())))
					out.close()
					file.close()
					state.files = int(state.files) + 1
					state.bytes = int(state.bytes) + size
		name = dir.get_next()
	dir.list_dir_end()

func _read_project_file(args: Dictionary) -> Dictionary:
	var root := _trusted_root(str(args.get("project_path", "")))
	if root.is_empty(): return {"ok": false, "error": "Project root is not trusted"}
	var rel := _safe_relative(str(args.get("relative_path", "")))
	if rel.is_empty(): return {"ok": false, "error": "Invalid relative path"}
	var path := root.path_join(rel)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "Cannot read project file"}
	var max_chars := clampi(int(args.get("max_chars", 300000)), 1000, 1000000)
	var text := file.get_as_text().substr(0, max_chars)
	file.close()
	return {"ok": true, "path": rel, "content": text}

func _sandbox_file(relative: String) -> String:
	var root := await _physical_workspace_root()
	var rel := _safe_relative(relative)
	if root.is_empty() or rel.is_empty(): return ""
	return root.path_join("work").path_join(rel)

func _compare_file(args: Dictionary) -> Dictionary:
	var root := _trusted_root(str(args.get("project_path", "")))
	if root.is_empty(): return {"ok": false, "error": "Project root is not trusted"}
	var rel := _safe_relative(str(args.get("relative_path", "")))
	var sandbox_rel := _safe_relative(str(args.get("sandbox_path", rel)))
	if rel.is_empty() or sandbox_rel.is_empty(): return {"ok": false, "error": "Invalid path"}
	var original := root.path_join(rel)
	var candidate := await _sandbox_file(sandbox_rel)
	if candidate.is_empty() or not FileAccess.file_exists(candidate): return {"ok": false, "error": "Sandbox candidate missing"}
	var original_hash := _sha256(original) if FileAccess.file_exists(original) else ""
	var candidate_hash := _sha256(candidate)
	var result := {"ok": true, "changed": original_hash != candidate_hash, "original_exists": FileAccess.file_exists(original), "original_sha256": original_hash, "candidate_sha256": candidate_hash, "original_size": _file_size(original), "candidate_size": _file_size(candidate)}
	if _looks_text(rel) and _file_size(candidate) <= 2 * 1024 * 1024: result["preview"] = _text_change_preview(original, candidate)
	return result

func _apply_file(args: Dictionary) -> Dictionary:
	var root := _trusted_root(str(args.get("project_path", "")))
	if root.is_empty(): return {"ok": false, "error": "Project root is not trusted"}
	var rel := _safe_relative(str(args.get("relative_path", "")))
	var sandbox_rel := _safe_relative(str(args.get("sandbox_path", rel)))
	if rel.is_empty() or sandbox_rel.is_empty(): return {"ok": false, "error": "Invalid path"}
	var source := await _sandbox_file(sandbox_rel)
	if source.is_empty() or not FileAccess.file_exists(source): return {"ok": false, "error": "Verified sandbox file is missing"}
	var target := root.path_join(rel)
	var before := _sha256(target) if FileAccess.file_exists(target) else ""
	var candidate := _sha256(source)
	if not before.is_empty() and before == candidate: return {"ok": true, "changed": false, "path": target, "sha256": candidate}
	var stamp := "%d" % int(Time.get_unix_time_from_system())
	var backup := "%s/%s/%s" % [BACKUP_ROOT, stamp, rel]
	var backup_abs := ProjectSettings.globalize_path(backup)
	if FileAccess.file_exists(target):
		DirAccess.make_dir_recursive_absolute(backup_abs.get_base_dir())
		if not _copy_file(target, backup_abs): return {"ok": false, "error": "Cannot create backup"}
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if not _copy_file(source, target): return {"ok": false, "error": "Cannot apply candidate file"}
	var after := _sha256(target)
	if after != candidate:
		if FileAccess.file_exists(backup_abs): _copy_file(backup_abs, target)
		return {"ok": false, "error": "Post-write hash verification failed; original restored"}
	return {"ok": true, "changed": true, "path": target, "backup": backup if FileAccess.file_exists(backup_abs) else "", "sha256": after}

func _copy_file(source: String, target: String) -> bool:
	var src := FileAccess.open(source, FileAccess.READ)
	if src == null: return false
	var dst := FileAccess.open(target, FileAccess.WRITE)
	if dst == null:
		src.close()
		return false
	var total := src.get_length()
	while src.get_position() < total:
		dst.store_buffer(src.get_buffer(mini(1024 * 1024, total - src.get_position())))
	dst.close()
	src.close()
	return true

func _sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return ""
	while file.get_position() < file.get_length():
		ctx.update(file.get_buffer(mini(1024 * 1024, file.get_length() - file.get_position())))
	file.close()
	return ctx.finish().hex_encode().to_lower()

func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return 0
	var size := f.get_length()
	f.close()
	return size

func _looks_text(path: String) -> bool:
	return path.get_extension().to_lower() in ["txt","md","json","csv","tsv","gd","py","js","ts","tsx","jsx","html","css","xml","yaml","yml","toml","ini","cfg","shader","glsl","cpp","c","h","hpp","cs","java","kt","rs","go","php","rb","lua","swift","dart","sql","sh","ps1"]

func _text_change_preview(original: String, candidate: String) -> String:
	var before := ""
	if FileAccess.file_exists(original):
		var f := FileAccess.open(original, FileAccess.READ)
		if f != null:
			before = f.get_as_text()
			f.close()
	var f2 := FileAccess.open(candidate, FileAccess.READ)
	if f2 == null: return ""
	var after := f2.get_as_text()
	f2.close()
	if before == after: return "Файл не изменился."
	var before_lines := before.split("\n")
	var after_lines := after.split("\n")
	var first := 0
	while first < before_lines.size() and first < after_lines.size() and before_lines[first] == after_lines[first]: first += 1
	var start := maxi(0, first - 4)
	var end_before := mini(before_lines.size(), first + 14)
	var end_after := mini(after_lines.size(), first + 14)
	return "--- original около строки %d ---\n%s\n--- candidate ---\n%s" % [first + 1, "\n".join(before_lines.slice(start, end_before)), "\n".join(after_lines.slice(start, end_after))]

func _http_json(url: String) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 5.0
	add_child(req)
	var err := req.request(url, PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": error_string(err)}
	var result: Array = await req.request_completed
	req.queue_free()
	var code := int(result[1])
	var raw := (result[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(raw)
	if code >= 200 and code < 300 and parsed is Dictionary: return parsed
	return {"ok": false, "http": code, "error": raw.substr(0, 2000)}
