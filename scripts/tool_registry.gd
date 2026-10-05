class_name ToolRegistry
extends Node

signal tool_called(name: String, args: Dictionary)

const COMPUTER_TIMEOUT_MAX := 320.0
const COMPUTER_ACTION_TIMEOUT := 32.0
const COMPUTER_SCREEN_TIMEOUT := 20.0
const COMPUTER_WINDOWS_TIMEOUT := 16.0

var security_owner_review: Callable
var _security_review_busy := false
var _security_child_pid := -1
var tools: Dictionary = {}
var computer_base_url := "http://127.0.0.1:8766"
var files_base_url := "http://127.0.0.1:8767"

func _ready() -> void:
	register_tool("http_get", "Скачать текст или JSON по URL", {"url":"string"}, Callable(self, "_http_get"))
	register_tool("read_file", "Прочитать текстовый файл проекта или user://", {"path":"string"}, Callable(self, "_read_file"))
	register_tool("write_file", "Записать текстовый файл в разрешённую область", {"path":"string","content":"string"}, Callable(self, "_write_file"))
	register_tool("list_dir", "Показать файлы и папки", {"path":"string"}, Callable(self, "_list_dir"))
	register_tool("analyze_file", "Глубоко разобрать локальный файл: PDF, DOCX, XLS/XLSX, PPTX, ODT/ODS, изображение, аудио, видео, архив или исходный код", {"path":"string","question":"string","visual":"bool"}, Callable(self, "_analyze_file"))
	register_tool("file_tree", "Построить дерево локальной папки проекта или user:// с размерами файлов", {"path":"string","max_items":"int"}, Callable(self, "_file_tree"))
	register_tool("search_file_cache", "Найти ранее разобранные файлы и фрагменты по локальному индексу File Intelligence", {"query":"string","limit":"int"}, Callable(self, "_search_file_cache"))
	register_tool("security_configuration_check", "Запустить только явно авторизованную владельцем проверку HTTP/TLS-конфигурации по приватному scope JSON. Не обходит вход, CAPTCHA, редиректы или ограничения доступа.", {"scope_path":"string","baseline_path":"string","authorized":"bool"}, Callable(self, "_security_configuration_check"))
	register_tool("git_status", "Проверить git status", {}, Callable(self, "_git_status"))
	register_tool("git_diff", "Посмотреть git diff", {}, Callable(self, "_git_diff"))
	register_tool("system_info", "Получить сведения о системе и Godot", {}, Callable(self, "_system_info"))
	register_tool("computer_plan", "Совместимый контракт: планирование Computer Agent выполняет только локальный AuroraFox Core", {"goal":"string"}, Callable(self, "_computer_plan"))
	register_tool("computer_goal", "Совместимый контракт: цель должна быть разложена локальным AuroraFox Core на явные computer_action", {"goal":"string","max_steps":"int","auto_execute":"bool"}, Callable(self, "_computer_goal"))
	register_tool("computer_action", "Выполнить одну уже выбранную локальным AuroraFox Core примитивную операцию мыши/клавиатуры с bounded execution и проверкой разрешений", {"type":"string","x":"int","y":"int","button":"string","clicks":"int","text":"string","keys":"array","amount":"int","seconds":"float","action_id":"string","verify":"bool"}, Callable(self, "_computer_action"))
	register_tool("computer_screenshot", "Получить локальный screenshot Windows после проверки master stop и разрешений", {}, Callable(self, "_computer_screenshot"))
	register_tool("computer_windows", "Получить локальное описание окон и UI Automation элементов Windows", {}, Callable(self, "_screen_snapshot"))
	register_tool("sandbox_exec", "Запустить разрешённую команду: auto/container требуют строгий локальный контейнер; local доступен только как явный degraded operator mode", {"command":"array","cwd":"string","timeout":"int","mode":"string"}, Callable(self, "_sandbox_exec"))
	register_tool("sandbox_write", "Создать текстовый файл внутри изолированной песочницы", {"path":"string","content":"string"}, Callable(self, "_sandbox_write"))
	register_tool("sandbox_read", "Прочитать файл из изолированной песочницы", {"path":"string"}, Callable(self, "_sandbox_read"))
	register_tool("screen_snapshot", "Получить описание текущих окон и элементов интерфейса Windows", {}, Callable(self, "_screen_snapshot"))

func register_tool(name: String, description: String, schema: Dictionary, callable: Callable) -> void:
	tools[name] = {"description": description, "schema": schema, "callable": callable}

func describe_tools() -> Array:
	var out: Array = []
	for name in tools.keys():
		var t: Dictionary = tools[name]
		out.append({"name": name, "description": t.description, "schema": t.schema})
	return out

func call_tool(name: String, args: Dictionary = {}, execution_guard: Callable = Callable()) -> Variant:
	if not tools.has(name):
		return {"ok": false, "error": "Unknown tool: " + name}
	tool_called.emit(name, args)
	if name == "security_configuration_check":
		return await _security_configuration_check(args, execution_guard)
	return await tools[name].callable.call(args)

func _path_allowed(path: String, writing := false) -> bool:
	if path.begins_with("user://"):
		var absolute := ProjectSettings.globalize_path(path).simplify_path()
		var reserved := ProjectSettings.globalize_path("user://security/runs").simplify_path()
		if writing and (absolute == reserved or absolute.begins_with(reserved + "/")):
			return false
		return not _security_user_path(path, false).is_empty()
	if path.begins_with("res://"):
		return not writing or path.begins_with("res://workspace/") or path.begins_with("res://generated/")
	return false

func _http_json(url: String, method: HTTPClient.Method, payload: Dictionary = {}, timeout := 240.0) -> Dictionary:
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
	if parsed is Dictionary:
		return parsed
	return {"ok": false, "error": "Invalid JSON response"}

func _computer_json(path: String, method: HTTPClient.Method, payload: Dictionary = {}, timeout := 12.0) -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "unsupported_platform", "message": "Desktop Computer Agent is not supported on %s" % OS.get_name(), "retryable": false}
	if not ComputerClient.master_enabled_from(self):
		return {"ok": false, "error": "master_stop", "message": "Master stop активен", "retryable": false}
	var req := HTTPRequest.new()
	req.timeout = clampf(timeout, 1.0, COMPUTER_TIMEOUT_MAX)
	add_child(req)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-AuroraFox-Computer-Token: " + ComputerClient.shared_service_token(),
		"X-AuroraFox-Autonomy-Allowed: 1",
	])
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	var err := req.request(computer_base_url + path, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "service_unavailable", "message": "Computer service request failed (%s)" % err, "retryable": true}
	var completed: Array = await req.request_completed
	req.queue_free()
	if completed.size() < 4:
		return {"ok": false, "error": "malformed_response", "message": "Computer service returned an incomplete response", "retryable": true}
	var result_code := int(completed[0])
	var code := int(completed[1])
	var raw: PackedByteArray = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "transport_failure", "message": "Computer service transport failed (%s" % result_code, "retryable": true}
	var text := raw.get_string_from_utf8().strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "empty_response", "http": code, "retryable": code >= 500}
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "error": "malformed_response", "http": code, "retryable": code >= 500}
	var response: Dictionary = parsed
	if code < 200 or code >= 300:
		return {"ok": false, "http": code, "error": str(response.get("error", "http_error")), "message": str(response.get("detail", response.get("message", "Computer service error"))).substr(0, 2048), "retryable": code in [408, 429, 502, 503, 504]}
	return response

func _computer_permission() -> Dictionary:
	if ComputerClient.computer_control_enabled():
		return {"ok": true}
	return {"ok": false, "error": "permission_denied", "message": "Computer control is disabled by the user", "retryable": false}

func _http_get(args: Dictionary) -> Dictionary:
	# Compatibility name, hardened implementation. All arbitrary public reads go
	# through the same SSRF/redirect/size/content/access-control policy as chat.
	var reader := PublicWebManager.new()
	add_child(reader)
	var result := await reader.read_public_url(str(args.get("url", "")))
	reader.queue_free()
	return result

func _read_file(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if not _path_allowed(path, false):
		return {"ok": false, "error": "Path denied"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Cannot open file"}
	var content := f.get_as_text()
	f.close()
	return {"ok": true, "content": content}

func _write_file(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if not _path_allowed(path, true):
		return {"ok": false, "error": "Write path denied"}
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Cannot open file"}
	f.store_string(str(args.get("content", "")))
	f.close()
	return {"ok": true}

func _list_dir(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", "res://"))
	if not _path_allowed(path, false):
		return {"ok": false, "error": "Path denied"}
	var dir := DirAccess.open(path)
	if dir == null:
		return {"ok": false, "error": "Cannot open directory"}
	var items: Array = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		items.append({"name": name, "dir": dir.current_is_dir()})
		name = dir.get_next()
	dir.list_dir_end()
	return {"ok": true, "items": items}

func _analyze_file(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if not _path_allowed(path, false):
		return {"ok": false, "error": "File Intelligence path denied. Use res:// or user://."}
	return await _http_json(files_base_url + "/analyze", HTTPClient.METHOD_POST, {
		"path": ProjectSettings.globalize_path(path),
		"question": str(args.get("question", "")),
		"visual": bool(args.get("visual", true)),
		"max_chars": 200000
	}, 620.0)

func _file_tree(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", "res://"))
	if not _path_allowed(path, false):
		return {"ok": false, "error": "File tree path denied. Use res:// or user://."}
	return await _http_json(files_base_url + "/tree", HTTPClient.METHOD_POST, {
		"path": ProjectSettings.globalize_path(path),
		"max_items": clampi(int(args.get("max_items", 2000)), 1, 5000)
	}, 90.0)

func _search_file_cache(args: Dictionary) -> Dictionary:
	return await _http_json(files_base_url + "/cache/search", HTTPClient.METHOD_POST, {
		"query": str(args.get("query", "")),
		"limit": clampi(int(args.get("limit", 20)), 1, 100)
	}, 30.0)

func _security_configuration_check(args: Dictionary, execution_guard: Callable = Callable()) -> Dictionary:
	if _security_child_pid > 0:
		return {"ok": false, "error": "security_run_busy"}
	# Authorization is deliberately independent from the scope file: imported
	# content cannot authorize traffic by merely containing an allow flag.
	if not bool(args.get("authorized", false)):
		return {"ok": false, "error": "explicit_owner_authorization_required", "message": "Нужно явное подтверждение владельца для этого точного scope."}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "unsupported_platform", "message": "Интегрированная security-проверка сейчас доступна в Windows-клиенте."}
	var scope_user := str(args.get("scope_path", "")).strip_edges()
	var scope_abs := _security_user_path(scope_user, true)
	if scope_abs.is_empty():
		return {"ok": false, "error": "scope_path_denied", "message": "Scope должен быть существующим приватным файлом user://."}
	var baseline_user := str(args.get("baseline_path", "")).strip_edges()
	var baseline_abs := ""
	if not baseline_user.is_empty():
		baseline_abs = _security_user_path(baseline_user, true)
		if baseline_abs.is_empty():
			return {"ok": false, "error": "baseline_path_denied", "message": "Baseline должен быть существующим приватным файлом user://."}
	# Tool arguments only request review. They never represent trusted consent.
	if not str(args.get("output_path", "")).is_empty():
		return {"ok": false, "error": "output_path_denied", "message": "Evidence получает новый приватный путь автоматически; существующие файлы не перезаписываются."}
	var runtime := _security_runtime_paths()
	if not bool(runtime.get("ok", false)):
		return runtime
	var reviewed := await _security_review_scope(scope_abs, baseline_abs)
	if not bool(reviewed.get("ok", false)):
		return reviewed
	var run_user := "user://security/runs/" + Crypto.new().generate_random_bytes(16).hex_encode()
	var run_abs := _security_user_path(run_user, false)
	if DirAccess.dir_exists_absolute(run_abs) or DirAccess.make_dir_recursive_absolute(run_abs) != OK:
		return {"ok": false, "error": "security_storage_unavailable"}
	# Freeze exactly the bytes shown to the owner, rather than reopen mutable inputs.
	scope_abs = run_abs.path_join("scope.json")
	if not _security_write_snapshot(scope_abs, str(reviewed.scope_text)):
		return {"ok": false, "error": "security_snapshot_failed"}
	if not baseline_abs.is_empty():
		baseline_abs = run_abs.path_join("baseline.json")
		if not _security_write_snapshot(baseline_abs, str(reviewed.baseline_text)):
			return {"ok": false, "error": "security_snapshot_failed"}
	var output_user := run_user.path_join("evidence.json")
	var output_abs := run_abs.path_join("evidence.json")
	var argv := PackedStringArray([
		str(runtime.get("runner", "")),
		"--scope", scope_abs,
		"--authorize",
		"--output", output_abs
	])
	if not baseline_abs.is_empty():
		argv.append("--baseline")
		argv.append(baseline_abs)
	if not _security_execution_allowed(execution_guard):
		return {"ok": false, "error": "security_execution_stopped"}
	var pid := OS.create_process(str(runtime.get("python", "")), argv, false)
	if pid <= 0:
		return {"ok": false, "error": "security_runner_start_failed", "message": "Не удалось запустить локальный security runner."}
	if not await _security_wait_child(pid, execution_guard):
		return {"ok": false, "error": "security_execution_stopped"}
	if not FileAccess.file_exists(output_abs):
		return {"ok": false, "error": "security_runner_rejected_scope", "message": "Проверка не началась или scope был отклонён до создания evidence."}
	var report_file := FileAccess.open(output_abs, FileAccess.READ)
	if report_file == null:
		return {"ok": false, "error": "security_evidence_unreadable", "message": "Evidence создан, но не читается."}
	var parsed = JSON.parse_string(report_file.get_as_text())
	report_file.close()
	if not parsed is Dictionary:
		return {"ok": false, "error": "security_evidence_invalid", "message": "Security runner вернул некорректный evidence JSON."}
	var report: Dictionary = parsed
	var validation := _security_validate_evidence(report, str(reviewed.scope_text))
	if not bool(validation.get("ok", false)):
		return validation
	var all_checked := bool(validation.get("all_checked", false))
	return {
		"ok": all_checked,
		"evidence_path": output_user,
		"report": report,
		"message": "Проверка завершена." if all_checked else "Проверка завершена с границей доступа, сетевой ошибкой или другим непроверенным исходом."
	}

func _exit_tree() -> void:
	if _security_child_pid > 0 and OS.is_process_running(_security_child_pid):
		OS.kill(_security_child_pid)

func _security_wait_child(pid: int, guard: Callable) -> bool:
	_security_child_pid = pid
	while OS.is_process_running(pid):
		if not _security_execution_allowed(guard):
			OS.kill(pid)
			_security_child_pid = -1
			return false
		await get_tree().create_timer(0.10).timeout
	_security_child_pid = -1
	return _security_execution_allowed(guard)

func _security_execution_allowed(guard: Callable) -> bool:
	if not ComputerClient.master_enabled_from(self):
		return false
	if not guard.is_valid():
		return true
	var decision = guard.call("before_tool", {"tool": "security_configuration_check", "running": true})
	if decision is bool:
		return decision
	return bool(decision.get("allowed", true)) if decision is Dictionary else true

func _security_validate_evidence(report: Dictionary, scope_text: String) -> Dictionary:
	var scope = JSON.parse_string(scope_text)
	var results = report.get("results", null)
	var urls = scope.get("urls", []) if scope is Dictionary else []
	if report.get("schema", "") != "aurorafox.security-evidence.v1" or report.get("scope_file_sha256", "") != scope_text.sha256_text() or not results is Array or results.is_empty() or results.size() != urls.size():
		return {"ok": false, "error": "security_evidence_invalid"}
	var all_checked := true
	for index in range(results.size()):
		var item = results[index]
		if not item is Dictionary or item.get("target_sha256", "") != JSON.stringify(str(urls[index])).sha256_text() or not item.has("outcome"):
			return {"ok": false, "error": "security_evidence_invalid"}
		if str(item.outcome) != "checked":
			all_checked = false
	return {"ok": true, "all_checked": all_checked}

func _security_review_scope(scope_abs: String, baseline_abs: String) -> Dictionary:
	if _security_review_busy or not security_owner_review.is_valid():
		return {"ok": false, "error": "owner_review_unavailable"}
	var scope_text := FileAccess.get_file_as_string(scope_abs)
	var scope = JSON.parse_string(scope_text)
	if not scope is Dictionary:
		return {"ok": false, "error": "invalid_scope_json"}
	var baseline_text := "" if baseline_abs.is_empty() else FileAccess.get_file_as_string(baseline_abs)
	_security_review_busy = true
	var approved: bool = bool(await security_owner_review.call(scope_text, baseline_text.sha256_text() if not baseline_abs.is_empty() else ""))
	_security_review_busy = false
	if not approved:
		return {"ok": false, "error": "owner_authorization_declined"}
	if FileAccess.get_file_as_string(scope_abs) != scope_text or (not baseline_abs.is_empty() and FileAccess.get_file_as_string(baseline_abs) != baseline_text):
		return {"ok": false, "error": "reviewed_inputs_changed"}
	return {"ok": true, "scope_text": scope_text, "baseline_text": baseline_text}

func _security_write_snapshot(path: String, content: String) -> bool:
	if FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return FileAccess.get_file_as_string(path) == content

func _security_user_path(value: String, require_existing: bool) -> String:
	if not value.begins_with("user://"):
		return ""
	var root := ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var absolute := ProjectSettings.globalize_path(value).simplify_path()
	if absolute != root and not absolute.begins_with(root + "/"):
		return ""
	# Reject symlink/reparse traversal into another private file or outside root.
	var cursor := root
	for part in absolute.trim_prefix(root).trim_prefix("/").split("/", false):
		var parent := DirAccess.open(cursor)
		if parent != null and parent.is_link(part):
			return ""
		cursor = cursor.path_join(part)
	if require_existing and not FileAccess.file_exists(absolute):
		return ""
	return absolute

func _security_runtime_paths() -> Dictionary:
	var app_root := OS.get_executable_path().get_base_dir()
	var candidates := [
		{
			"python": app_root.path_join("file_intelligence/python/python.exe"),
			"runner": app_root.path_join("file_intelligence/security_runner.py")
		},
		{
			"python": ProjectSettings.globalize_path("res://file_intelligence/python/python.exe"),
			"runner": ProjectSettings.globalize_path("res://security_workspace/runner.py")
		}
	]
	for candidate in candidates:
		if FileAccess.file_exists(str(candidate.get("python", ""))) and FileAccess.file_exists(str(candidate.get("runner", ""))):
			candidate["ok"] = true
			return candidate
	return {"ok": false, "error": "security_runtime_unavailable", "message": "Локальный Python/security runner не найден; восстановите File Intelligence runtime."}

func _run_process(args: Dictionary) -> Dictionary:
	var program := str(args.get("program", ""))
	var allowed := ["git", "python", "python3", "godot", "godot4", "curl"]
	if program not in allowed:
		return {"ok": false, "error": "Program not allowed"}
	var argv: PackedStringArray = PackedStringArray(args.get("args", []))
	var output: Array = []
	var code := OS.execute(program, argv, output, true, false)
	return {"ok": code == 0, "code": code, "output": "\n".join(output).substr(0, 100000)}

func _git_status(_args: Dictionary) -> Dictionary:
	return await _run_process({"program":"git","args":["status","--short"]})

func _git_diff(_args: Dictionary) -> Dictionary:
	return await _run_process({"program":"git","args":["diff","--"]})

func _system_info(_args: Dictionary) -> Dictionary:
	return {"ok": true, "godot": Engine.get_version_info(), "os": OS.get_name(), "cpu_count": OS.get_processor_count(), "locale": OS.get_locale()}

func _computer_plan(_args: Dictionary) -> Dictionary:
	return {"ok": false, "error": "local_core_planning_required", "message": "Computer planning belongs to local AuroraFox Core. Use computer_windows/computer_screenshot, decide locally, then call computer_action.", "retryable": false}

func _computer_goal(_args: Dictionary) -> Dictionary:
	return {"ok": false, "error": "local_core_planning_required", "message": "Computer goals must be planned by local AuroraFox Core and executed as explicit computer_action primitives.", "retryable": false}

func _computer_action(args: Dictionary) -> Dictionary:
	var permission := _computer_permission()
	if not permission.get("ok", false):
		return permission
	var payload := args.duplicate(true)
	if str(payload.get("action_id", "")).strip_edges().is_empty():
		payload["action_id"] = "%d:%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	return await _computer_json("/action", HTTPClient.METHOD_POST, payload, COMPUTER_ACTION_TIMEOUT)

func _computer_screenshot(_args: Dictionary) -> Dictionary:
	var permission := _computer_permission()
	if not permission.get("ok", false):
		return permission
	return await _computer_json("/screen", HTTPClient.METHOD_GET, {}, COMPUTER_SCREEN_TIMEOUT)

func _sandbox_exec(args: Dictionary) -> Dictionary:
	var timeout := clampi(int(args.get("timeout", 60)), 1, 300)
	var mode := str(args.get("mode", "auto")).strip_edges().to_lower()
	if mode not in ["auto", "container", "local"]:
		return {"ok": false, "error": "invalid_sandbox_mode", "message": "sandbox_exec mode must be auto, container, or local", "retryable": false}
	var payload := {"command": args.get("command", []), "cwd": str(args.get("cwd", ".")), "timeout": timeout, "allow_network": false}
	if mode in ["auto", "container"]:
		var container_result := await _computer_json("/sandbox/container_exec", HTTPClient.METHOD_POST, payload, float(timeout + 5))
		if int(container_result.get("http", 0)) == 404:
			return {"ok": false, "error": "container_runtime_unavailable", "message": "Automatic/strict sandbox execution requires Docker/Podman and a preinstalled local image; degraded local fallback is disabled", "retryable": false, "network_isolation_enforced": false}
		return container_result
	# Explicit local mode is intentionally degraded and still fails closed at the
	# sidecar unless AURORAFOX_ALLOW_DEGRADED_LOCAL_SANDBOX=1 was set by an operator.
	var local_result := await _computer_json("/sandbox/exec", HTTPClient.METHOD_POST, payload, float(timeout + 5))
	if local_result.get("ok", false) and not bool(local_result.get("network_isolation_enforced", false)):
		local_result["degraded_isolation"] = true
		local_result["isolation_note"] = "Explicit local mode lacks strict filesystem/network isolation. Prefer mode=container."
	return local_result

func _sandbox_write(args: Dictionary) -> Dictionary:
	return await _computer_json("/sandbox/write", HTTPClient.METHOD_POST, {"path": str(args.get("path", "")), "content": str(args.get("content", ""))}, 12.0)

func _sandbox_read(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	var encoded := path.uri_encode()
	return await _computer_json("/sandbox/read?path=" + encoded, HTTPClient.METHOD_GET, {}, 12.0)

func _screen_snapshot(_args: Dictionary) -> Dictionary:
	var permission := _computer_permission()
	if not permission.get("ok", false):
		return permission
	return await _computer_json("/windows", HTTPClient.METHOD_GET, {}, COMPUTER_WINDOWS_TIMEOUT)
