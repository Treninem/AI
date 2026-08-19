class_name ProjectIndexToolBridge
extends Node

var index := ProjectIndexClient.new()
var access := ProjectAccessStore.new()

func _ready() -> void:
	add_child(index)
	add_child(access)
	if OS.get_name() == "Windows": call_deferred("_register_tools")

func _register_tools() -> void:
	var main := get_parent()
	if main == null: return
	var registry = main.get("tools")
	if not registry is ToolRegistry: return
	registry.register_tool(
		"index_project",
		"Проиндексировать большой проект локально: исходники, языки, классы, функции и текст. Разрешены res://, user:// и папки, явно добавленные пользователем в доверенные проекты.",
		{"path":"string","max_files":"int","force":"bool"},
		Callable(self, "_index_project")
	)
	registry.register_tool(
		"search_project",
		"Быстро найти нужные места в ранее проиндексированном проекте без чтения всех файлов заново.",
		{"path":"string","query":"string","limit":"int","language":"string"},
		Callable(self, "_search_project")
	)
	registry.register_tool(
		"search_symbols",
		"Найти определения классов, функций, методов, сигналов и других символов по имени в индексе проекта.",
		{"path":"string","query":"string","limit":"int"},
		Callable(self, "_search_symbols")
	)
	registry.register_tool(
		"project_index_status",
		"Показать состояние локального индекса проекта и количество файлов по языкам.",
		{"path":"string"},
		Callable(self, "_status")
	)
	registry.register_tool(
		"trusted_projects",
		"Показать папки проектов, доступ к которым пользователь явно разрешил AuroraFox.",
		{},
		Callable(self, "_trusted_projects")
	)

func _allowed(path: String) -> bool:
	if path.begins_with("res://") or path.begins_with("user://"): return true
	return access.is_trusted_root(path)

func _denied() -> Dictionary:
	return {"ok": false, "error": "Project path is not trusted. Ask the user to add this folder through AuroraFox project settings first."}

func _index_project(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", "res://"))
	if not _allowed(path): return _denied()
	return await index.index_project(path, clampi(int(args.get("max_files", 30000)), 1, 100000), bool(args.get("force", false)))

func _search_project(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", "res://"))
	if not _allowed(path): return _denied()
	var query := str(args.get("query", "")).strip_edges()
	if query.is_empty(): return {"ok": false, "error": "Search query is empty"}
	return await index.search(path, query, clampi(int(args.get("limit", 20)), 1, 100), str(args.get("language", "")))

func _search_symbols(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", "res://"))
	if not _allowed(path): return _denied()
	var query := str(args.get("query", "")).strip_edges()
	if query.is_empty(): return {"ok": false, "error": "Symbol query is empty"}
	return await index.search_symbols(path, query, clampi(int(args.get("limit", 50)), 1, 200))

func _status(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", "res://"))
	if not _allowed(path): return _denied()
	return await index.status(path)

func _trusted_projects(_args: Dictionary) -> Dictionary:
	return {"ok": true, "roots": access.all_roots()}
