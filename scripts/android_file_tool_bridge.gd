class_name AndroidFileToolBridge
extends Node

var client := FileIntelligenceClient.new()

func _ready() -> void:
	if OS.get_name() != "Android": return
	add_child(client)
	call_deferred("_register_android_tools")

func _register_android_tools() -> void:
	var main := get_parent()
	if main == null: return
	var registry = main.get("tools")
	if not registry is ToolRegistry: return
	registry.register_tool(
		"analyze_file",
		"Глубоко разобрать локальный файл на Android через native File Intelligence",
		{"path":"string","question":"string","visual":"bool"},
		Callable(self, "_analyze_file")
	)
	registry.register_tool(
		"file_tree",
		"Построить дерево приватной папки AuroraFox на Android",
		{"path":"string","max_items":"int"},
		Callable(self, "_file_tree")
	)
	registry.register_tool(
		"search_file_cache",
		"Поиск по файловому кэшу Android пока не индексируется отдельно; использовать память/историю чата",
		{"query":"string","limit":"int"},
		Callable(self, "_search_cache")
	)

func _analyze_file(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if not (path.begins_with("user://") or path.begins_with("res://")):
		return {"ok": false, "error": "Android agent file path must use user:// or res://"}
	return await client.analyze_file(path, str(args.get("question", "")), bool(args.get("visual", true)), 200000)

func _file_tree(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", "user://"))
	if not path.begins_with("user://"):
		return {"ok": false, "error": "Android directory tree is restricted to user://"}
	return await client.tree(path, clampi(int(args.get("max_items", 2000)), 1, 5000))

func _search_cache(_args: Dictionary) -> Dictionary:
	return {"ok": false, "results": [], "error": "Separate Android file-cache search is not enabled; extracted file text is available in the active chat context."}
