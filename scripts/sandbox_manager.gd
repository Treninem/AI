class_name SandboxManager
extends Node

signal workspace_created(id: String, root: String)
signal workspace_event(id: String, kind: String, details: Dictionary)

const INDEX_PATH := "user://sandboxes/index.json"
const ROOT_PATH := "user://sandboxes"
const WINDOWS_SERVICE := "http://127.0.0.1:8766"

var workspaces: Dictionary = {}
var active_workspace_id := ""
var android_runtime := AndroidLocalRuntime.new()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT_PATH))
	add_child(android_runtime)
	_load_index()

func capabilities() -> Dictionary:
	var os_name := OS.get_name()
	var base := {
		"platform": os_name,
		"workspace_files": true,
		"snapshots": true,
		"rollback": true,
		"network": true,
		"native_processes": false,
		"container_runtime": false,
		"embedded_runtime": false,
		"computer_control": os_name == "Windows"
	}
	if os_name == "Windows":
		base.native_processes = true
		base.container_runtime = _command_exists("docker") or _command_exists("podman")
	elif os_name == "Android":
		var android_caps := android_runtime.capabilities()
		for key in android_caps.keys():
			base[key] = android_caps[key]
	return base

func create_workspace(task: String, runtime_hint := "auto") -> Dictionary:
	var id := "%d_%04d" % [Time.get_unix_time_from_system(), randi_range(0, 9999)]
	var root := "%s/%s" % [ROOT_PATH, id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	for name in ["input", "work", "output", "logs", "snapshots"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root + "/" + name))
	var item := {
		"id": id,
		"root": root,
		"task": task,
		"runtime_hint": runtime_hint,
		"platform": OS.get_name(),
		"created_at": Time.get_datetime_string_from_system(true),
		"state": "ready",
		"last_event": "created",
		"events": []
	}
	workspaces[id] = item
	active_workspace_id = id
	_write_json(root + "/manifest.json", item)
	_save_index()
	workspace_created.emit(id, root)
	return {"ok": true, "workspace": item, "capabilities": capabilities()}

func set_active(id: String) -> Dictionary:
	if not workspaces.has(id):
		return {"ok": false, "error": "Unknown workspace"}
	active_workspace_id = id
	return {"ok": true, "workspace": workspaces[id]}

func get_active() -> Dictionary:
	if active_workspace_id.is_empty() or not workspaces.has(active_workspace_id):
		return {}
	return workspaces[active_workspace_id]

func list_workspaces(limit := 30) -> Array:
	var values: Array = workspaces.values()
	values.reverse()
	return values.slice(0, mini(values.size(), limit))

func write_file(relative_path: String, content: String, area := "work") -> Dictionary:
	var ws := get_active()
	if ws.is_empty():
		return {"ok": false, "error": "No active workspace"}
	var safe := _safe_relative(relative_path)
	if safe.is_empty():
		return {"ok": false, "error": "Invalid relative path"}
	var path := "%s/%s/%s" % [ws.root, area, safe]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Cannot write file"}
	f.store_string(content)
	_record("write", {"path": "%s/%s" % [area, safe], "bytes": content.to_utf8_buffer().size()})
	return {"ok": true, "path": path}

func read_file(relative_path: String, area := "work", max_chars := 300000) -> Dictionary:
	var ws := get_active()
	if ws.is_empty():
		return {"ok": false, "error": "No active workspace"}
	var safe := _safe_relative(relative_path)
	if safe.is_empty():
		return {"ok": false, "error": "Invalid relative path"}
	var path := "%s/%s/%s" % [ws.root, area, safe]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Cannot read file"}
	return {"ok": true, "path": path, "content": f.get_as_text().substr(0, max_chars)}

func tree(area := "work", max_items := 1000) -> Dictionary:
	var ws := get_active()
	if ws.is_empty():
		return {"ok": false, "error": "No active workspace"}
	var root := "%s/%s" % [ws.root, area]
	var items: Array = []
	_walk(root, "", items, max_items)
	return {"ok": true, "root": root, "items": items}

func snapshot(label := "checkpoint") -> Dictionary:
	var ws := get_active()
	if ws.is_empty():
		return {"ok": false, "error": "No active workspace"}
	var stamp := "%d" % Time.get_unix_time_from_system()
	var snapshot_dir := "%s/snapshots/%s_%s" % [ws.root, stamp, _slug(label)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(snapshot_dir))
	var result := _copy_tree("%s/work" % ws.root, snapshot_dir)
	if result.get("ok", false):
		_record("snapshot", {"label": label, "path": snapshot_dir})
	return result.merged({"snapshot": snapshot_dir}, true)

func rollback(snapshot_path: String) -> Dictionary:
	var ws := get_active()
	if ws.is_empty():
		return {"ok": false, "error": "No active workspace"}
	if not snapshot_path.begins_with(ws.root + "/snapshots/"):
		return {"ok": false, "error": "Snapshot outside active workspace"}
	var work_abs := ProjectSettings.globalize_path(ws.root + "/work")
	_remove_children(work_abs)
	var result := _copy_tree(snapshot_path, ws.root + "/work")
	if result.get("ok", false):
		_record("rollback", {"snapshot": snapshot_path})
	return result

func execute(command: Array, cwd := ".", timeout := 120, mode := "auto") -> Dictionary:
	var ws := get_active()
	if ws.is_empty():
		return {"ok": false, "error": "No active workspace"}
	if command.is_empty():
		return {"ok": false, "error": "Empty command"}
	_record("exec_requested", {"command": _redact_command(command), "cwd": cwd, "mode": mode})
	var result: Dictionary
	if OS.get_name() == "Windows":
		result = await _execute_windows(command, cwd, timeout, mode)
	elif OS.get_name() == "Android":
		result = await android_runtime.execute(ws.root + "/work", command, cwd, timeout, mode)
	else:
		result = {"ok": false, "error": "Platform runtime not implemented: " + OS.get_name()}
	_record("exec_result", {"ok": result.get("ok", false), "code": result.get("code", -1), "summary": str(result.get("output", result.get("error", ""))).substr(0, 4000)})
	return result

func test(language := "auto", cwd := ".") -> Dictionary:
	var commands := _test_commands(language)
	var attempts: Array = []
	for cmd in commands:
		var result := await execute(cmd, cwd, 180, "auto")
		attempts.append({"command": cmd, "result": result})
		if result.get("ok", false):
			return {"ok": true, "language": language, "attempts": attempts, "passed_by": cmd}
	return {"ok": false, "language": language, "attempts": attempts, "error": "No verification command passed"}

func status() -> Dictionary:
	return {"ok": true, "active": get_active(), "count": workspaces.size(), "capabilities": capabilities()}

func _execute_windows(command: Array, cwd: String, timeout: int, mode: String) -> Dictionary:
	var ws := get_active()
	var rel_cwd := "%s/work" % ws.id
	if cwd != "." and not cwd.is_empty():
		rel_cwd += "/" + _safe_relative(cwd)
	var payload := {"command": command, "cwd": rel_cwd, "timeout": clampi(timeout, 1, 600)}
	if mode == "container" or (mode == "auto" and bool(capabilities().get("container_runtime", false))):
		# Computer service may choose Docker/Podman when its container endpoint is available.
		var container_result := await _http_json(WINDOWS_SERVICE + "/sandbox/container_exec", HTTPClient.METHOD_POST, payload, float(timeout + 30))
		if container_result.get("ok", false) or int(container_result.get("http", 0)) != 404:
			return container_result
	return await _http_json(WINDOWS_SERVICE + "/sandbox/exec", HTTPClient.METHOD_POST, payload, float(timeout + 30))

func _test_commands(language: String) -> Array:
	var l := language.to_lower()
	if l in ["python", "py"]: return [["python", "-m", "pytest", "-q"], ["python", "-m", "compileall", "."]]
	if l in ["godot", "gdscript"]: return [["godot", "--headless", "--path", ".", "--quit"]]
	if l in ["javascript", "js", "typescript", "ts"]: return [["npm", "test", "--", "--runInBand"], ["npx", "tsc", "--noEmit"]]
	if l in ["rust", "rs"]: return [["cargo", "test", "--quiet"], ["cargo", "check", "--quiet"]]
	if l in ["go", "golang"]: return [["go", "test", "./..."]]
	if l in ["java", "kotlin"]: return [["gradlew.bat", "test"], ["gradle", "test"]]
	if l in ["csharp", "c#", "dotnet"]: return [["dotnet", "test"], ["dotnet", "build", "--no-restore"]]
	return [["python", "-m", "pytest", "-q"], ["godot", "--headless", "--path", ".", "--quit"], ["git", "diff", "--check"]]

func _record(kind: String, details: Dictionary) -> void:
	if active_workspace_id.is_empty() or not workspaces.has(active_workspace_id): return
	var item: Dictionary = workspaces[active_workspace_id]
	var events: Array = item.get("events", [])
	events.append({"time": Time.get_datetime_string_from_system(true), "kind": kind, "details": details})
	if events.size() > 300: events = events.slice(events.size() - 300)
	item.events = events
	item.last_event = kind
	workspaces[active_workspace_id] = item
	_write_json(item.root + "/manifest.json", item)
	_save_index()
	workspace_event.emit(active_workspace_id, kind, details)

func _safe_relative(path: String) -> String:
	var p := path.replace("\\", "/").strip_edges().trim_prefix("/")
	if p.is_empty() or p.contains("../") or p == ".." or p.contains(":"):
		return ""
	return p

func _slug(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		if c.is_valid_identifier() or c.is_valid_int(): out += c
		elif c in ["-", "_"]: out += c
		else: out += "_"
	return out.substr(0, 48)

func _walk(root: String, rel: String, out: Array, max_items: int) -> void:
	if out.size() >= max_items: return
	var path := root if rel.is_empty() else root + "/" + rel
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "" and out.size() < max_items:
		if name not in [".", ".."]:
			var child_rel := name if rel.is_empty() else rel + "/" + name
			var is_dir := dir.current_is_dir()
			out.append({"path": child_rel, "dir": is_dir})
			if is_dir: _walk(root, child_rel, out, max_items)
		name = dir.get_next()
	dir.list_dir_end()

func _copy_tree(source: String, dest: String) -> Dictionary:
	var src_abs := ProjectSettings.globalize_path(source)
	var dst_abs := ProjectSettings.globalize_path(dest)
	DirAccess.make_dir_recursive_absolute(dst_abs)
	var dir := DirAccess.open(src_abs)
	if dir == null: return {"ok": false, "error": "Cannot open source tree"}
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name not in [".", ".."]:
			var s := src_abs.path_join(name)
			var d := dst_abs.path_join(name)
			if dir.current_is_dir():
				var nested := _copy_tree(s, d)
				if not nested.get("ok", false): return nested
			else:
				var err := DirAccess.copy_absolute(s, d)
				if err != OK: return {"ok": false, "error": "Copy failed: %s" % err}
		name = dir.get_next()
	dir.list_dir_end()
	return {"ok": true}

func _remove_children(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null: return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name not in [".", ".."]:
			var full := abs_path.path_join(name)
			if dir.current_is_dir():
				_remove_children(full)
				DirAccess.remove_absolute(full)
			else:
				DirAccess.remove_absolute(full)
		name = dir.get_next()
	dir.list_dir_end()

func _command_exists(name: String) -> bool:
	if OS.get_name() != "Windows": return false
	var output: Array = []
	return OS.execute("where", PackedStringArray([name]), output, true, false) == 0

func _redact_command(command: Array) -> Array:
	var out: Array = []
	var redact_next := false
	for part in command:
		var s := str(part)
		if redact_next:
			out.append("[REDACTED]")
			redact_next = false
		elif s.to_lower() in ["--password", "--token", "--secret", "-p"]:
			out.append(s)
			redact_next = true
		else:
			out.append(s)
	return out

func _write_json(path: String, value: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(value, "  "))

func _save_index() -> void:
	_write_json(INDEX_PATH, {"active": active_workspace_id, "workspaces": workspaces})

func _load_index() -> void:
	var f := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if f == null: return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		active_workspace_id = str(parsed.get("active", ""))
		workspaces = parsed.get("workspaces", {})

func _http_json(url: String, method: HTTPClient.Method, payload: Dictionary = {}, timeout := 180.0) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	var err := req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "HTTPRequest error %s" % err}
	var result: Array = await req.request_completed
	req.queue_free()
	var code := int(result[1])
	var raw: PackedByteArray = result[3]
	var text := raw.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if code < 200 or code >= 300:
		return {"ok": false, "http": code, "error": text.substr(0, 4000)}
	return parsed if parsed is Dictionary else {"ok": false, "error": "Invalid JSON response"}
