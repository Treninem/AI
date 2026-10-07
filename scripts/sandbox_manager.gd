class_name SandboxManager
extends Node

signal workspace_created(id: String, root: String)
signal workspace_event(id: String, kind: String, details: Dictionary)

const INDEX_PATH := "user://sandboxes/index.json"
const ROOT_PATH := "user://sandboxes"
const WINDOWS_SERVICE := "http://127.0.0.1:8766"
const MAX_WINDOWS_EXEC_TIMEOUT := 300
const MAX_WINDOWS_HTTP_TIMEOUT := 320.0

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
		"native_processes": false,
		"container_runtime": false,
		"embedded_runtime": false,
		"computer_control": os_name == "Windows",
		"local_network_isolation": false,
		"strict_network_isolation": false,
		"degraded_local_process_opt_in": false,
	}
	if os_name == "Windows":
		var local_opt_in := OS.get_environment("AURORAFOX_ALLOW_DEGRADED_LOCAL_SANDBOX").strip_edges() == "1"
		base.native_processes = local_opt_in
		base.degraded_local_process_opt_in = local_opt_in
		base.container_runtime = _command_exists("podman") or _command_exists("docker")
		base.strict_network_isolation = bool(base.container_runtime)
	elif os_name == "Android":
		var android_caps := android_runtime.capabilities()
		for key in android_caps.keys():
			base[key] = android_caps[key]
	return base

func create_workspace(task: String, runtime_hint := "auto") -> Dictionary:
	var id := "%d_%04d" % [int(Time.get_unix_time_from_system()), randi_range(0, 9999)]
	var meta_root := "%s/%s" % [ROOT_PATH, id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(meta_root))
	var item := {
		"id": id,
		"root": meta_root,
		"meta_root": meta_root,
		"task": task,
		"runtime_hint": runtime_hint,
		"platform": OS.get_name(),
		"created_at": Time.get_datetime_string_from_system(true),
		"state": "creating",
		"last_event": "creating",
		"events": [],
		"remote": OS.get_name() == "Windows"
	}
	if OS.get_name() == "Windows":
		var created := await _http_json(WINDOWS_SERVICE + "/sandbox/workspace/create", HTTPClient.METHOD_POST, {"id": id, "task": task})
		if not created.get("ok", false): return created
		item["service_workspace"] = id
		item["service_root"] = str(created.get("workspace", {}).get("root", id))
	else:
		for name in ["input", "work", "output", "logs", "snapshots"]:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(meta_root + "/" + name))
	item["state"] = "ready"
	item["last_event"] = "created"
	workspaces[id] = item
	active_workspace_id = id
	_write_json(meta_root + "/manifest.json", item)
	_save_index()
	workspace_created.emit(id, str(item.get("service_root", meta_root)))
	return {"ok": true, "workspace": item, "capabilities": capabilities()}

func set_active(id: String) -> Dictionary:
	if not workspaces.has(id): return {"ok": false, "error": "Unknown workspace"}
	active_workspace_id = id
	_save_index()
	return {"ok": true, "workspace": workspaces[id]}

func get_active() -> Dictionary:
	if active_workspace_id.is_empty() or not workspaces.has(active_workspace_id): return {}
	return workspaces[active_workspace_id]

func list_workspaces(limit := -1) -> Array:
	var values: Array = workspaces.values()
	values.reverse()
	var budget := OwnerResourcePolicy.value("sandbox_workspace_items") if limit < 0 else limit
	return values if budget == 0 else values.slice(0, mini(values.size(), budget))

func write_file(relative_path: String, content: String, area := "work") -> Dictionary:
	var ws := get_active()
	if ws.is_empty(): return {"ok": false, "error": "No active workspace"}
	var safe := _safe_relative(relative_path)
	if safe.is_empty() or area not in ["input", "work", "output", "logs"]: return {"ok": false, "error": "Invalid workspace path"}
	var result: Dictionary
	if OS.get_name() == "Windows":
		result = await _http_json(WINDOWS_SERVICE + "/sandbox/write", HTTPClient.METHOD_POST, {"path": "%s/%s/%s" % [ws.id, area, safe], "content": content, "max_bytes": OwnerResourcePolicy.value("sandbox_write_bytes")})
	else:
		var path := "%s/%s/%s" % [ws.root, area, safe]
		if _path_has_link(path): return {"ok": false, "error": "Workspace links are not writable"}
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null: return {"ok": false, "error": "Cannot write file"}
		f.store_string(content)
		result = {"ok": true, "path": path}
	if result.get("ok", false): _record("write", {"path": "%s/%s" % [area, safe], "bytes": content.to_utf8_buffer().size()})
	return result

func read_file(relative_path: String, area := "work", max_chars := -1) -> Dictionary:
	max_chars = OwnerResourcePolicy.value("sandbox_read_chars") if max_chars == -1 else max_chars
	if max_chars < 0: return {"ok": false, "error": "Read character budget must be nonnegative"}
	var max_bytes := OwnerResourcePolicy.value("sandbox_read_bytes")
	var ws := get_active()
	if ws.is_empty(): return {"ok": false, "error": "No active workspace"}
	var safe := _safe_relative(relative_path)
	if safe.is_empty() or area not in ["input", "work", "output", "logs"]: return {"ok": false, "error": "Invalid workspace path"}
	if OS.get_name() == "Windows":
		var result := await _http_json(WINDOWS_SERVICE + "/sandbox/read?path=" + ("%s/%s/%s" % [ws.id, area, safe]).uri_encode() + "&max_bytes=%d" % max_bytes, HTTPClient.METHOD_GET)
		if result.has("text"):
			var text := str(result.get("text", ""))
			result["content"] = text if max_chars == 0 else text.substr(0, max_chars)
			result["truncated"] = max_chars > 0 and text.length() > max_chars
			result.erase("text")
		return result
	var path := "%s/%s/%s" % [ws.root, area, safe]
	if _path_has_link(path): return {"ok": false, "error": "Workspace links are not readable"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {"ok": false, "error": "Cannot read file"}
	if max_bytes > 0 and f.get_length() > max_bytes:
		return {"ok": false, "error": "File exceeds owner byte budget", "limit_reached": true}
	var data := f.get_buffer(max_bytes + 1 if max_bytes > 0 else f.get_length())
	if max_bytes > 0 and data.size() > max_bytes:
		return {"ok": false, "error": "File grew beyond owner byte budget", "limit_reached": true}
	var text := data.get_string_from_utf8()
	return {"ok": true, "path": path, "content": text if max_chars == 0 else text.substr(0, max_chars), "truncated": max_chars > 0 and text.length() > max_chars}

func tree(area := "work", max_items := -1) -> Dictionary:
	max_items = OwnerResourcePolicy.value("sandbox_tree_items") if max_items == -1 else max_items
	if max_items < 0: return {"ok": false, "error": "Tree budget must be nonnegative"}
	var ws := get_active()
	if ws.is_empty(): return {"ok": false, "error": "No active workspace"}
	if area not in ["input", "work", "output", "logs", "snapshots"]: return {"ok": false, "error": "Invalid workspace area"}
	if OS.get_name() == "Windows":
		var result := await _http_json(WINDOWS_SERVICE + "/sandbox/workspace/tree?workspace=%s&area=%s&max_items=%d" % [str(ws.id).uri_encode(), area.uri_encode(), max_items], HTTPClient.METHOD_GET)
		return result
	var root := "%s/%s" % [ws.root, area]
	var items: Array = []
	var coverage := {"truncated": false, "failed": 0, "unsafe": 0}
	_walk(root, "", items, max_items, coverage)
	return {"ok": true, "root": root, "items": items, "truncated": coverage.truncated, "failed_paths": coverage.failed, "unsafe_paths_skipped": coverage.unsafe, "partial": coverage.truncated or coverage.failed > 0 or coverage.unsafe > 0}

func snapshot(label := "checkpoint") -> Dictionary:
	var ws := get_active()
	if ws.is_empty(): return {"ok": false, "error": "No active workspace"}
	var result: Dictionary
	if OS.get_name() == "Windows":
		result = await _http_json(WINDOWS_SERVICE + "/sandbox/workspace/snapshot", HTTPClient.METHOD_POST, {"workspace": ws.id, "label": label, "max_entries": OwnerResourcePolicy.value("sandbox_snapshot_entries"), "max_bytes": OwnerResourcePolicy.value("sandbox_snapshot_bytes")})
	else:
		var snapshot_id := "%d_checkpoint" % int(Time.get_unix_time_from_system())
		var snapshot_dir := "%s/snapshots/%s" % [ws.root, snapshot_id]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(snapshot_dir))
		result = _copy_tree("%s/work" % ws.root, snapshot_dir)
		if result.get("ok", false):
			result["snapshot"] = snapshot_id
			result["path"] = snapshot_dir
	if result.get("ok", false): _record("snapshot", {"label": label, "snapshot": result.get("snapshot", "")})
	return result

func rollback(snapshot_ref: String) -> Dictionary:
	var ws := get_active()
	if ws.is_empty(): return {"ok": false, "error": "No active workspace"}
	if snapshot_ref.is_empty(): return {"ok": false, "error": "Missing snapshot"}
	var result: Dictionary
	if OS.get_name() == "Windows":
		result = await _http_json(WINDOWS_SERVICE + "/sandbox/workspace/rollback", HTTPClient.METHOD_POST, {"workspace": ws.id, "snapshot": snapshot_ref, "max_entries": OwnerResourcePolicy.value("sandbox_snapshot_entries"), "max_bytes": OwnerResourcePolicy.value("sandbox_snapshot_bytes")})
	else:
		var safe_snapshot := _safe_relative(snapshot_ref)
		if safe_snapshot.is_empty(): return {"ok": false, "error": "Invalid snapshot"}
		var snapshot_path := "%s/snapshots/%s" % [ws.root, safe_snapshot]
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(snapshot_path)): return {"ok": false, "error": "Snapshot not found"}
		var work_abs := ProjectSettings.globalize_path(ws.root + "/work")
		if _path_has_link(snapshot_path) or _path_has_link(work_abs): return {"ok": false, "error": "Workspace links cannot be rolled back"}
		var staged := _global_path(ws.root).path_join("rollback_stage_%d" % Time.get_ticks_usec())
		var backup := staged + "_backup"
		result = _copy_tree(snapshot_path, staged)
		if not result.get("ok", false):
			_remove_children(staged)
			DirAccess.remove_absolute(staged)
			return result # Current work remains untouched on any staging failure.
		var move_error := DirAccess.rename_absolute(work_abs, backup)
		if move_error != OK:
			_remove_children(staged)
			DirAccess.remove_absolute(staged)
			return {"ok": false, "error": "Cannot preserve current workspace", "code": move_error}
		move_error = DirAccess.rename_absolute(staged, work_abs)
		if move_error != OK:
			var restore_error := DirAccess.rename_absolute(backup, work_abs)
			return {"ok": false, "error": "Cannot apply staged rollback", "code": move_error, "restore_code": restore_error, "recovery_backup": backup}
		_remove_children(backup)
		DirAccess.remove_absolute(backup)
		result = {"ok": true, "snapshot": snapshot_ref}
	if result.get("ok", false): _record("rollback", {"snapshot": snapshot_ref})
	return result

func execute(command: Array, cwd := ".", timeout := 120, mode := "auto") -> Dictionary:
	var ws := get_active()
	if ws.is_empty(): return {"ok": false, "error": "No active workspace"}
	if command.is_empty(): return {"ok": false, "error": "Empty command"}
	_record("exec_requested", {"command": _redact_command(command), "cwd": cwd, "mode": mode})
	var result: Dictionary
	if OS.get_name() == "Windows":
		result = await _execute_windows(command, cwd, timeout, mode)
	elif OS.get_name() == "Android":
		result = android_runtime.execute(ws.root + "/work", command, cwd, timeout, mode)
	else:
		result = {"ok": false, "error": "Platform runtime not implemented: " + OS.get_name()}
	_record("exec_result", {"ok": result.get("ok", false), "code": result.get("code", -1), "summary": str(result.get("output", result.get("error", ""))).substr(0, 4000)})
	return result

func test(language := "auto", cwd := ".") -> Dictionary:
	var attempts: Array = []
	for cmd in _test_commands(language):
		var result := await execute(cmd, cwd, 180, "auto")
		attempts.append({"command": cmd, "result": result})
		if result.get("ok", false): return {"ok": true, "language": language, "attempts": attempts, "passed_by": cmd}
	return {"ok": false, "language": language, "attempts": attempts, "error": "No verification command passed"}

func status() -> Dictionary:
	return {"ok": true, "active": get_active(), "count": workspaces.size(), "capabilities": capabilities()}

func _execute_windows(command: Array, cwd: String, timeout: int, mode: String) -> Dictionary:
	var ws := get_active()
	var requested_mode := mode.strip_edges().to_lower()
	if requested_mode not in ["auto", "container", "local"]:
		return {"ok": false, "error": "invalid_sandbox_mode", "message": "Sandbox mode must be auto, container, or local", "retryable": false}
	var rel_cwd := "%s/work" % ws.id
	if cwd != "." and not cwd.is_empty():
		var safe_cwd := _safe_relative(cwd)
		if safe_cwd.is_empty(): return {"ok": false, "error": "Invalid cwd"}
		rel_cwd += "/" + safe_cwd
	var bounded_timeout := ComputerRequestGuard.execution_timeout(timeout)
	if bounded_timeout < 0: return {"ok": false, "error": "invalid_timeout", "retryable": false}
	var payload := {"command": command, "cwd": rel_cwd, "timeout": bounded_timeout, "allow_network": false}
	if requested_mode in ["auto", "container"]:
		if requested_mode == "auto" and not bool(capabilities().get("container_runtime", false)):
			return {"ok": false, "error": "container_runtime_unavailable", "message": "Automatic execution requires the strict Docker/Podman sandbox; degraded local fallback is disabled", "retryable": false, "network_isolation_enforced": false}
		var container_result := await _http_json(WINDOWS_SERVICE + "/sandbox/container_exec", HTTPClient.METHOD_POST, payload, ComputerRequestGuard.execution_http_timeout(bounded_timeout))
		if int(container_result.get("http", 0)) == 404:
			return {"ok": false, "error": "container_runtime_unavailable", "message": "Strict container sandbox requested but Docker/Podman or the required local image is unavailable", "retryable": false, "network_isolation_enforced": false}
		return container_result
	# "local" is an explicit degraded operator mode. The sidecar independently
	# rejects this endpoint unless AURORAFOX_ALLOW_DEGRADED_LOCAL_SANDBOX=1.
	var local_result := await _http_json(WINDOWS_SERVICE + "/sandbox/exec", HTTPClient.METHOD_POST, payload, ComputerRequestGuard.execution_http_timeout(bounded_timeout))
	if local_result.get("ok", false) and not bool(local_result.get("network_isolation_enforced", false)):
		local_result["degraded_isolation"] = true
		local_result["isolation_note"] = "Explicit local mode lacks strict filesystem/network isolation. Prefer mode=container."
	return local_result

func _test_commands(language: String) -> Array:
	var l := language.to_lower()
	if OS.get_name() == "Android": return [["wasm", "test.wasm"]]
	if l in ["python", "py"]: return [["python", "-m", "pytest", "-q"], ["python", "-m", "compileall", "."]]
	if l in ["godot", "gdscript"]: return [["godot", "--headless", "--path", ".", "--quit"]]
	if l in ["javascript", "js"]: return [["npm", "test", "--", "--runInBand"]]
	if l in ["typescript", "ts"]: return [["npx", "tsc", "--noEmit"], ["npm", "test"]]
	if l in ["rust", "rs"]: return [["cargo", "test", "--quiet"], ["cargo", "check", "--quiet"]]
	if l in ["go", "golang"]: return [["go", "test", "./..."]]
	if l in ["java", "kotlin"]: return [["gradlew.bat", "test"], ["gradle", "test"]]
	if l in ["csharp", "c#", "dotnet"]: return [["dotnet", "test"], ["dotnet", "build", "--no-restore"]]
	if l in ["c", "cpp", "c++"]: return [["cmake", "--build", "build"], ["git", "diff", "--check"]]
	return [["git", "diff", "--check"], ["python", "-m", "pytest", "-q"], ["godot", "--headless", "--path", ".", "--quit"]]

func _record(kind: String, details: Dictionary) -> void:
	if active_workspace_id.is_empty() or not workspaces.has(active_workspace_id): return
	var item: Dictionary = workspaces[active_workspace_id]
	var events: Array = item.get("events", [])
	events.append({"time": Time.get_datetime_string_from_system(true), "kind": kind, "details": details})
	var event_budget := OwnerResourcePolicy.value("sandbox_event_items")
	if event_budget > 0 and events.size() > event_budget: events = events.slice(events.size() - event_budget)
	item["events"] = events
	item["last_event"] = kind
	workspaces[active_workspace_id] = item
	_write_json(str(item.get("meta_root", item.get("root", ROOT_PATH))) + "/manifest.json", item)
	_save_index()
	workspace_event.emit(active_workspace_id, kind, details)

func _safe_relative(path: String) -> String:
	var p := path.replace("\\", "/").strip_edges().trim_prefix("/")
	if p.is_empty() or p.contains("../") or p == ".." or p.contains(":"): return ""
	return p

func _path_has_link(path: String) -> bool:
	var absolute := _global_path(path).simplify_path()
	var root := _global_path(ROOT_PATH).simplify_path()
	if absolute != root and not absolute.begins_with(root + "/"): return true
	var current := root
	var root_parent := DirAccess.open(root.get_base_dir())
	if root_parent != null and root_parent.is_link(root.get_file()): return true
	for part in absolute.trim_prefix(root).trim_prefix("/").split("/", false):
		var parent := DirAccess.open(current)
		if parent == null: return false # Missing destinations may be created by write/copy.
		if parent.is_link(part): return true
		current = current.path_join(part)
	return false

func _walk(root: String, rel: String, out: Array, max_items: int, coverage: Dictionary = {}) -> void:
	var path := root if rel.is_empty() else root + "/" + rel
	if _path_has_link(path):
		coverage["unsafe"] = int(coverage.get("unsafe", 0)) + 1
		return
	var dir := DirAccess.open(path)
	if dir == null:
		coverage["failed"] = int(coverage.get("failed", 0)) + 1
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name not in [".", ".."]:
			if dir.is_link(name):
				coverage["unsafe"] = int(coverage.get("unsafe", 0)) + 1
			elif max_items > 0 and out.size() >= max_items:
				coverage["truncated"] = true
				break
			else:
				var child_rel := name if rel.is_empty() else rel + "/" + name
				var is_dir := dir.current_is_dir()
				out.append({"path": child_rel, "dir": is_dir})
				if is_dir: _walk(root, child_rel, out, max_items, coverage)
		name = dir.get_next()
	dir.list_dir_end()

func _copy_tree(source: String, dest: String) -> Dictionary:
	var src_abs := _global_path(source)
	var dst_abs := _global_path(dest)
	if _path_has_link(src_abs) or _path_has_link(dst_abs): return {"ok": false, "error": "Workspace links are not copied"}
	DirAccess.make_dir_recursive_absolute(dst_abs)
	var dir := DirAccess.open(src_abs)
	if dir == null: return {"ok": false, "error": "Cannot open source tree"}
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name not in [".", ".."]:
			if dir.is_link(name): return {"ok": false, "error": "Workspace links are not copied"}
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
	if _path_has_link(abs_path): return
	var dir := DirAccess.open(abs_path)
	if dir == null: return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name not in [".", ".."]:
			var full := abs_path.path_join(name)
			if dir.current_is_dir() and not dir.is_link(name):
				_remove_children(full)
				DirAccess.remove_absolute(full)
			else:
				DirAccess.remove_absolute(full)
		name = dir.get_next()
	dir.list_dir_end()

func _global_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"): return ProjectSettings.globalize_path(path)
	return path

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
	if _path_has_link(path):
		push_error("Workspace links are not writable")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(value, "  "))

func _save_index() -> void:
	_write_json(INDEX_PATH, {"active": active_workspace_id, "workspaces": workspaces})

func _load_index() -> void:
	if _path_has_link(INDEX_PATH): return
	var f := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if f == null: return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		active_workspace_id = str(parsed.get("active", ""))
		workspaces = parsed.get("workspaces", {})

func _http_json(url: String, method: HTTPClient.Method, payload: Dictionary = {}, timeout := -1.0) -> Dictionary:
	if not url.begins_with(WINDOWS_SERVICE):
		return {"ok": false, "error": "service_url_denied", "retryable": false}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "unsupported_platform", "retryable": false}
	if not ComputerClient.master_enabled_from(self):
		return {"ok": false, "error": "master_stop", "message": "Master stop активен", "retryable": false}
	var req := HTTPRequest.new()
	if not ComputerRequestGuard.configure_request(req, timeout, "sandbox_default_http_seconds"):
		req.free()
		return {"ok": false, "error": "invalid_timeout", "retryable": false}
	add_child(req)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-AuroraFox-Computer-Token: " + ComputerClient.shared_service_token(),
		"X-AuroraFox-Autonomy-Allowed: 1",
	])
	payload = ComputerRequestGuard.execution_payload(url, payload)
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	var err := req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "service_unavailable", "message": "Computer sandbox request failed (%s)" % err, "retryable": true}
	var allowed := func() -> bool: return ComputerClient.master_enabled_from(self)
	var guarded: Dictionary = await ComputerRequestGuard.wait(req, self, allowed, WINDOWS_SERVICE, ComputerClient.shared_service_token(), payload)
	if guarded.cancelled:
		req.queue_free()
		return {"ok": false, "error": "response_budget" if int(guarded.get("transport_result", -1)) == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED else ("transport_failure" if guarded.has("transport_result") else "cancelled"), "retryable": false, "limit_reached": int(guarded.get("transport_result", -1)) == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, "termination_confirmed": guarded.termination_confirmed, "uncertain_external_state": guarded.uncertain_external_state}
	var completed: Array = guarded.completed
	req.queue_free()
	if completed.size() < 4:
		return {"ok": false, "error": "malformed_response", "retryable": true}
	var result_code := int(completed[0])
	var code := int(completed[1])
	var raw: PackedByteArray = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "transport_failure", "message": "Computer sandbox transport failed (%s)" % result_code, "retryable": true}
	var text := raw.get_string_from_utf8().strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "empty_response", "http": code, "retryable": code >= 500}
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "error": "malformed_response", "http": code, "retryable": code >= 500}
	var response: Dictionary = parsed
	if code < 200 or code >= 300:
		return {"ok": false, "http": code, "error": str(response.get("error", "http_error")), "message": OwnerResourcePolicy.clip(str(response.get("detail", response.get("message", "Computer sandbox error"))), "computer_http_error_chars"), "retryable": code in [408, 429, 502, 503, 504]}
	return response