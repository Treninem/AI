class_name ToolRegistry
extends Node

signal tool_called(name: String, args: Dictionary)

var tools: Dictionary = {}

func _ready() -> void:
	register_tool("http_get", "Скачать текст или JSON по URL", {"url":"string"}, Callable(self, "_http_get"))
	register_tool("read_file", "Прочитать текстовый файл проекта или user://", {"path":"string"}, Callable(self, "_read_file"))
	register_tool("write_file", "Записать текстовый файл в разрешённую область", {"path":"string","content":"string"}, Callable(self, "_write_file"))
	register_tool("list_dir", "Показать файлы и папки", {"path":"string"}, Callable(self, "_list_dir"))
	register_tool("run_process", "Запустить разрешённую внешнюю программу", {"program":"string","args":"array"}, Callable(self, "_run_process"))
	register_tool("git_status", "Проверить git status", {}, Callable(self, "_git_status"))
	register_tool("git_diff", "Посмотреть git diff", {}, Callable(self, "_git_diff"))
	register_tool("system_info", "Получить сведения о системе и Godot", {}, Callable(self, "_system_info"))

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

func _http_get(args: Dictionary) -> Dictionary:
	var url := str(args.get("url", ""))
	if not (url.begins_with("http://") or url.begins_with("https://")):
		return {"ok": false, "error": "Only HTTP/HTTPS allowed"}
	var req := HTTPRequest.new()
	req.timeout = 30.0
	add_child(req)
	var err := req.request(url, PackedStringArray(["User-Agent: AutonomousAI-Godot/0.1"]))
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
	return {"ok": true, "content": f.get_as_text()}

func _write_file(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if not _path_allowed(path, true):
		return {"ok": false, "error": "Write path denied"}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Cannot open file"}
	f.store_string(str(args.get("content", "")))
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
