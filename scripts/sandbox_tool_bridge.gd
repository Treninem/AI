class_name SandboxToolBridge
extends Node

var manager := SandboxManager.new()

func _ready() -> void:
	if manager.get_parent() == null:
		add_child(manager)

func register_into(registry: ToolRegistry) -> void:
	registry.register_tool("workspace_create", "Создать отдельную локальную рабочую среду для задачи. Делай это перед сложной работой с кодом/файлами.", {"task":"string","runtime":"string"}, Callable(self, "_create"))
	registry.register_tool("workspace_status", "Показать активную песочницу и возможности текущей платформы.", {}, Callable(self, "_status"))
	registry.register_tool("workspace_tree", "Показать дерево файлов активной песочницы.", {"area":"string"}, Callable(self, "_tree"))
	registry.register_tool("workspace_write", "Записать файл в рабочую область активной песочницы.", {"path":"string","content":"string"}, Callable(self, "_write"))
	registry.register_tool("workspace_read", "Прочитать файл из рабочей области активной песочницы.", {"path":"string","area":"string"}, Callable(self, "_read"))
	registry.register_tool("workspace_snapshot", "Создать контрольную точку перед рискованным изменением.", {"label":"string"}, Callable(self, "_snapshot"))
	registry.register_tool("workspace_rollback", "Откатить рабочую область к ранее созданной контрольной точке.", {"snapshot":"string"}, Callable(self, "_rollback"))
	registry.register_tool("workspace_exec", "Запустить команду в подходящей локальной песочнице. На Windows предпочитает контейнер при наличии; на Android использует встроенный runtime.", {"command":"array","cwd":"string","timeout":"int","mode":"string"}, Callable(self, "_exec"))
	registry.register_tool("workspace_test", "Проверить результат в песочнице подходящим тестом/компиляцией для языка.", {"language":"string","cwd":"string"}, Callable(self, "_test"))

func _create(args: Dictionary) -> Dictionary:
	return manager.create_workspace(str(args.get("task", "task")), str(args.get("runtime", "auto")))

func _status(_args: Dictionary) -> Dictionary:
	return manager.status()

func _tree(args: Dictionary) -> Dictionary:
	return manager.tree(str(args.get("area", "work")))

func _write(args: Dictionary) -> Dictionary:
	return manager.write_file(str(args.get("path", "")), str(args.get("content", "")), "work")

func _read(args: Dictionary) -> Dictionary:
	return manager.read_file(str(args.get("path", "")), str(args.get("area", "work")))

func _snapshot(args: Dictionary) -> Dictionary:
	return manager.snapshot(str(args.get("label", "checkpoint")))

func _rollback(args: Dictionary) -> Dictionary:
	return manager.rollback(str(args.get("snapshot", "")))

func _exec(args: Dictionary) -> Dictionary:
	return await manager.execute(args.get("command", []), str(args.get("cwd", ".")), clampi(int(args.get("timeout", 120)), 1, 600), str(args.get("mode", "auto")))

func _test(args: Dictionary) -> Dictionary:
	return await manager.test(str(args.get("language", "auto")), str(args.get("cwd", ".")))
