class_name ToolRegistry
extends Node

signal tool_called(name: String, args: Dictionary)

const COMPUTER_TIMEOUT_MAX := 320.0
const COMPUTER_ACTION_TIMEOUT := 32.0
const COMPUTER_SCREEN_TIMEOUT := 20.0
const COMPUTER_WINDOWS_TIMEOUT := 16.0

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
	register_tool("git_status", "Проверить git status", {}, Callable(self, "_git_status"))
	register_tool("git_diff", "Посмотреть git diff", {}, Callable(self, "_git_diff"))
	register_tool("system_info", "Получить сведения о системе и Godot", {}, Callable(self, "_system_info"))
	register_tool("computer_plan", "Совместимый контракт: планирование Computer Agent выполняет только локальный AuroraFox Core", {"goal":"string"}, Callable(self, "_computer_plan"))
	register_tool("computer_goal", "Совместимый контракт: цель должна быть разложена локальным AuroraFox Core на явные computer_action", {"goal":"string","max_steps":"int","auto_execute":"bool"}, Callable(self, "_computer_goal"))
	register_tool("computer_action", "Выполнить одну уже выбранную локальным AuroraFox Core примитивную операцию мыши/клавиатуры с bounded execution и проверкой разрешений", {"type":"string","x":"int","y":"int","button":"string","clicks":"int","text":"string","keys":"array","amount":"int","seconds":"float","action_id":"string","verify":"bool"}, Callable(self, "_computer_action"))
	register_tool("computer_screenshot", "Получить локальный screenshot Windows после проверки master stop и разрешений", {}, Callable(self, "_computer_screenshot"))
	register_tool("computer_windows", "Получить локальное описание окон и UI Automation элементов Windows", {}, Callable(self, "_screen_snapshot"))
	register_tool("sandbox_exec", "Запустить разрешённую команду в рабочей папке AuroraFox; auto предпочитает контейнер, container не откатывается на local", {"command":"array","cwd":"string","timeout":"int","mode":"string"}, Callable(self, "_sandbox_exec"))
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

func call_tool(name: String, args: Dictionary = {}) -> Variant:
	if not tools.has(name):
		return {"ok": false, "error": "Unknown tool: " + name}
	tool_called.emit(name, args)
	return await tools[name].callable.call(args)

func _path_allowed(path: String, writing := false) -> bool:
	if path.begins_with("user://"):
		return true
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
		return {"ok": false, "error": "transport_failure", "message": "Computer service transport failed (%s)" % result_code, "retryable": true}
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
	var url := str(args.get("url", ""))
	if not (url.begins_with("http://") or url.begins_with("https://")):
		return {"ok": false, "error": "Only HTTP/HTTPS allowed"}
	var req := HTTPRequest.new()
	req.timeout = 30.0
	add_child(req)
	var err := req.request(url, PackedStringArray(["User-Agent: AuroraFox/0.4"]))
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "request error %s" % err}
	var result: Array = await req.request_completed
	req.queue_free()
	var code := int(result[1])
	var body: PackedByteArray = result[3]
	return {"ok": code >= 200 and code < 400, "status": code, "body": body.get_string_from_utf8().substr(0, 200000)}

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
		if container_result.get("ok", false):
			return container_result
		if mode == "container":
			if int(container_result.get("http", 0)) == 404:
				return {"ok": false, "error": "container_runtime_unavailable", "message": "Strict container sandbox requested but Docker/Podman is unavailable", "retryable": false, "network_isolation_enforced": false}
			return container_result
		if int(container_result.get("http", 0)) != 404:
			return container_result
	var local_result := await _computer_json("/sandbox/exec", HTTPClient.METHOD_POST, payload, float(timeout + 5))
	if local_result.get("ok", false) and not bool(local_result.get("network_isolation_enforced", false)):
		local_result["degraded_isolation"] = true
		local_result["isolation_note"] = "Local process sandbox enforces path/auth/timeouts but cannot guarantee network isolation; use mode=container for strict isolation."
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