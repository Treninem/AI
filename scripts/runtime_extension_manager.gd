class_name RuntimeExtensionManager
extends Node

signal extension_activated(id: String, tool_names: Array)
signal extension_deactivated(id: String)
signal extension_error(message: String, details: Dictionary)

const STAGED_RUNTIME_ROOT := "user://generated/"
const EDITOR_STAGED_ROOT := "res://generated/"
const EXTENSION_ROOT := "user://extensions/"
const MANIFEST_PATH := "user://runtime_extensions.json"
const MAX_SOURCE_BYTES := 512 * 1024
const TOOL_PREFIX := "aurora_ext_"

const BLOCKED_SOURCE_MARKERS := [
	"OS.", "FileAccess", "DirAccess", "ProjectSettings", "Engine.",
	"HTTPRequest", "HTTPClient", "TCPServer", "UDPServer", "PacketPeerUDP",
	"WebSocket", "JavaClassWrapper", "JavaScriptBridge", "ResourceLoader",
	"ResourceSaver", "preload(", "@tool", "@onready",
	"func _init", "func _ready", "func _process", "func _physics_process",
	"func _notification", "func _enter_tree", "func _exit_tree"
]

var registry: ToolRegistry
var entries: Dictionary = {}
var active_instances: Dictionary = {}
var active_tools: Dictionary = {}
var _bootstrap_started := false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXTENSION_ROOT))
	_load_manifest()
	call_deferred("_bootstrap")

func bind_registry(value: ToolRegistry) -> void:
	registry = value
	if is_inside_tree() and not _bootstrap_started:
		call_deferred("_bootstrap")

func _bootstrap() -> void:
	if _bootstrap_started: return
	_bootstrap_started = true
	for _i in range(8):
		if registry == null:
			var main := get_parent()
			if main != null:
				var candidate = main.get("tools")
				if candidate is ToolRegistry: registry = candidate
		if registry != null and not registry.tools.is_empty(): break
		await get_tree().process_frame
	if registry == null:
		extension_error.emit("ToolRegistry недоступен для runtime-расширений", {})
		return
	_restore_enabled()

func list_extensions() -> Array:
	var result: Array = []
	for id in entries.keys():
		var item: Dictionary = entries[id].duplicate(true)
		item["active"] = active_instances.has(id)
		result.append(item)
	result.sort_custom(func(a, b): return str(a.get("name", a.get("id", ""))).naturalnocasecmp_to(str(b.get("name", b.get("id", "")))) < 0)
	return result

func activate_staged(stage_path: String, expected_sha256 := "") -> Dictionary:
	if registry == null:
		return _fail("ToolRegistry ещё не готов", {"stage_path": stage_path})
	var allowed := _allowed_stage_path(stage_path)
	if allowed.is_empty(): return _fail("Разрешены только проверенные модули из generated/", {"stage_path": stage_path})
	var source_result := _read_source(allowed)
	if not source_result.get("ok", false): return source_result
	var source := str(source_result.get("source", ""))
	var sha := _sha256_text(source)
	if not expected_sha256.strip_edges().is_empty() and sha != expected_sha256.to_lower():
		return _fail("SHA-256 подготовленного модуля изменился после проверки", {"expected": expected_sha256, "actual": sha})
	var static_check := _validate_source(source)
	if not static_check.get("ok", false): return static_check

	var compiled := _compile_extension(source)
	if not compiled.get("ok", false): return compiled
	var instance: Node = compiled.get("instance")
	var declaration = instance.call("aurora_extension_manifest")
	if not declaration is Dictionary:
		instance.free()
		return _fail("aurora_extension_manifest() должен вернуть Dictionary", {})
	var manifest_check := _validate_extension_manifest(declaration, instance)
	if not manifest_check.get("ok", false):
		instance.free()
		return manifest_check

	var id := _extension_id(sha, str(declaration.get("name", "extension")))
	if entries.has(id) and active_instances.has(id):
		instance.free()
		return {"ok": true, "already_active": true, "id": id, "tools": active_tools.get(id, [])}

	var copied_path := EXTENSION_ROOT + id + ".gd"
	var copy_result := _write_extension_source(copied_path, source)
	if not copy_result.get("ok", false):
		instance.free()
		return copy_result

	var registered := _register_declared_tools(id, declaration, instance)
	if not registered.get("ok", false):
		instance.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(copied_path))
		return registered

	add_child(instance)
	active_instances[id] = instance
	active_tools[id] = registered.get("tools", [])
	entries[id] = {
		"id": id,
		"name": str(declaration.get("name", id)).substr(0, 80),
		"description": str(declaration.get("description", "")).substr(0, 500),
		"path": copied_path,
		"sha256": sha,
		"enabled": true,
		"tools": registered.get("tools", []),
		"activated_at": Time.get_datetime_string_from_system(true)
	}
	_save_manifest()
	extension_activated.emit(id, registered.get("tools", []))
	return {"ok": true, "id": id, "path": copied_path, "sha256": sha, "tools": registered.get("tools", []), "name": declaration.get("name", id)}

func deactivate(id: String) -> Dictionary:
	if not entries.has(id): return {"ok": false, "error": "Unknown extension"}
	_remove_extension_tools(id)
	if active_instances.has(id):
		var instance = active_instances[id]
		if is_instance_valid(instance): instance.queue_free()
		active_instances.erase(id)
	active_tools.erase(id)
	var item: Dictionary = entries[id]
	item["enabled"] = false
	entries[id] = item
	_save_manifest()
	extension_deactivated.emit(id)
	return {"ok": true, "id": id}

func enable(id: String) -> Dictionary:
	if not entries.has(id): return {"ok": false, "error": "Unknown extension"}
	if active_instances.has(id): return {"ok": true, "already_active": true, "id": id}
	var item: Dictionary = entries[id]
	var result := _activate_saved(id, str(item.get("path", "")), str(item.get("sha256", "")))
	if result.get("ok", false):
		item["enabled"] = true
		entries[id] = item
		_save_manifest()
	return result

func remove_extension(id: String) -> Dictionary:
	if not entries.has(id): return {"ok": false, "error": "Unknown extension"}
	deactivate(id)
	var path := str(entries[id].get("path", ""))
	if path.begins_with(EXTENSION_ROOT) and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	entries.erase(id)
	_save_manifest()
	return {"ok": true, "id": id, "removed": true}

func _restore_enabled() -> void:
	for id in entries.keys():
		var item: Dictionary = entries[id]
		if not bool(item.get("enabled", false)): continue
		var result := _activate_saved(str(id), str(item.get("path", "")), str(item.get("sha256", "")))
		if not result.get("ok", false):
			item["enabled"] = false
			item["last_error"] = str(result.get("error", "restore failed"))
			entries[id] = item
	_save_manifest()

func _activate_saved(id: String, path: String, expected_sha: String) -> Dictionary:
	if registry == null: return _fail("ToolRegistry недоступен", {"id": id})
	if not path.begins_with(EXTENSION_ROOT): return _fail("Extension path escapes user://extensions", {"id": id})
	var source_result := _read_source(path)
	if not source_result.get("ok", false): return source_result
	var source := str(source_result.get("source", ""))
	var sha := _sha256_text(source)
	if sha != expected_sha.to_lower(): return _fail("Extension SHA-256 mismatch", {"id": id, "expected": expected_sha, "actual": sha})
	var static_check := _validate_source(source)
	if not static_check.get("ok", false): return static_check
	var compiled := _compile_extension(source)
	if not compiled.get("ok", false): return compiled
	var instance: Node = compiled.get("instance")
	var declaration = instance.call("aurora_extension_manifest")
	if not declaration is Dictionary:
		instance.free()
		return _fail("Saved extension manifest is invalid", {"id": id})
	var manifest_check := _validate_extension_manifest(declaration, instance)
	if not manifest_check.get("ok", false):
		instance.free()
		return manifest_check
	var registered := _register_declared_tools(id, declaration, instance)
	if not registered.get("ok", false):
		instance.free()
		return registered
	add_child(instance)
	active_instances[id] = instance
	active_tools[id] = registered.get("tools", [])
	extension_activated.emit(id, registered.get("tools", []))
	return {"ok": true, "id": id, "tools": registered.get("tools", []), "restored": true}

func _register_declared_tools(id: String, declaration: Dictionary, instance: Node) -> Dictionary:
	var tool_defs: Array = declaration.get("tools", [])
	var names: Array = []
	for definition in tool_defs:
		var name := str(definition.get("name", ""))
		if registry.tools.has(name):
			_remove_names(names)
			return _fail("Runtime-расширение попыталось заменить существующий инструмент", {"tool": name, "extension": id})
		var method := str(definition.get("method", ""))
		registry.register_tool(name, str(definition.get("description", "")).substr(0, 500), definition.get("schema", {}), Callable(instance, method))
		names.append(name)
	return {"ok": true, "tools": names}

func _remove_extension_tools(id: String) -> void:
	_remove_names(active_tools.get(id, []))

func _remove_names(names: Array) -> void:
	if registry == null: return
	for name in names: registry.tools.erase(str(name))

func _validate_extension_manifest(value: Dictionary, instance: Node) -> Dictionary:
	var name := str(value.get("name", "")).strip_edges()
	if name.is_empty(): return _fail("Extension manifest name is empty", {})
	var tool_defs = value.get("tools", [])
	if not tool_defs is Array or tool_defs.is_empty(): return _fail("Extension must declare at least one tool", {})
	if tool_defs.size() > 12: return _fail("Extension declares too many tools", {"count": tool_defs.size()})
	var seen: Dictionary = {}
	for definition in tool_defs:
		if not definition is Dictionary: return _fail("Invalid tool declaration", {})
		var tool_name := str(definition.get("name", "")).strip_edges()
		if not tool_name.begins_with(TOOL_PREFIX): return _fail("Runtime tool must use aurora_ext_ prefix", {"tool": tool_name})
		if tool_name.length() > 80 or not _valid_identifier(tool_name): return _fail("Invalid runtime tool name", {"tool": tool_name})
		if seen.has(tool_name): return _fail("Duplicate runtime tool name", {"tool": tool_name})
		seen[tool_name] = true
		var method := str(definition.get("method", "")).strip_edges()
		if method.is_empty() or not instance.has_method(method): return _fail("Runtime tool method is missing", {"tool": tool_name, "method": method})
		var schema = definition.get("schema", {})
		if not schema is Dictionary: return _fail("Runtime tool schema must be a Dictionary", {"tool": tool_name})
	return {"ok": true}

func _validate_source(source: String) -> Dictionary:
	if source.strip_edges().is_empty(): return _fail("Extension source is empty", {})
	if source.to_utf8_buffer().size() > MAX_SOURCE_BYTES: return _fail("Extension exceeds size limit", {})
	if not source.contains("extends Node"): return _fail("Runtime extension must extend Node", {})
	if not source.contains("func aurora_extension_manifest"):
		return _fail("Runtime extension must implement aurora_extension_manifest()", {})
	for marker in BLOCKED_SOURCE_MARKERS:
		if source.contains(marker): return _fail("Runtime extension uses blocked privileged API or lifecycle hook", {"marker": marker})
	for line in source.split("\n"):
		var clean := str(line).strip_edges()
		if clean.begins_with("load(") or clean.contains("= load(") or clean.begins_with("return load("):
			return _fail("Runtime extension uses blocked dynamic load()", {"line": clean.substr(0, 200)})
	return {"ok": true}

func _compile_extension(source: String) -> Dictionary:
	var script := GDScript.new()
	script.source_code = source
	var err := script.reload()
	if err != OK: return _fail("GDScript runtime compilation failed: %s" % error_string(err), {})
	if not script.can_instantiate(): return _fail("Compiled runtime extension cannot instantiate", {})
	var value = script.new()
	if not value is Node:
		if value != null and value.has_method("free"): value.free()
		return _fail("Runtime extension root must be Node", {})
	return {"ok": true, "instance": value}

func _allowed_stage_path(path: String) -> String:
	var normalized := path.replace("\\", "/").strip_edges()
	var roots := [STAGED_RUNTIME_ROOT]
	if OS.has_feature("editor"): roots.append(EDITOR_STAGED_ROOT)
	for root in roots:
		if normalized.begins_with(root) and normalized.ends_with(".gd"):
			var relative := normalized.trim_prefix(root)
			if relative.is_empty() or relative == ".." or relative.begins_with("../") or relative.contains("/../") or relative.contains(":"): return ""
			return normalized
	return ""

func _read_source(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return _fail("Cannot read extension source", {"path": path})
	if f.get_length() > MAX_SOURCE_BYTES:
		f.close()
		return _fail("Extension source exceeds size limit", {"path": path})
	var source := f.get_as_text()
	f.close()
	return {"ok": true, "source": source}

func _write_extension_source(path: String, source: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return _fail("Cannot store approved runtime extension", {"path": path})
	f.store_string(source)
	f.close()
	var check := FileAccess.open(path, FileAccess.READ)
	if check == null: return _fail("Cannot verify stored runtime extension", {"path": path})
	var actual := check.get_as_text()
	check.close()
	if actual != source:
		DirAccess.remove_absolute(absolute)
		return _fail("Stored runtime extension failed byte integrity check", {"path": path})
	return {"ok": true, "path": path}

func _extension_id(sha: String, display_name: String) -> String:
	var clean := ""
	for ch in display_name.to_lower():
		var s := str(ch)
		if s in "abcdefghijklmnopqrstuvwxyz0123456789_-": clean += s
		elif s == " ": clean += "_"
	if clean.is_empty(): clean = "extension"
	return clean.substr(0, 32) + "_" + sha.substr(0, 12)

func _valid_identifier(value: String) -> bool:
	if value.is_empty(): return false
	for ch in value:
		var s := str(ch)
		if s not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_": return false
	return true

func _sha256_text(text: String) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK: return ""
	if ctx.update(text.to_utf8_buffer()) != OK: return ""
	return ctx.finish().hex_encode().to_lower()

func _load_manifest() -> void:
	entries.clear()
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null: return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary: return
	for item in parsed.get("extensions", []):
		if item is Dictionary:
			var id := str(item.get("id", ""))
			if not id.is_empty(): entries[id] = item

func _save_manifest() -> void:
	var list: Array = []
	for id in entries.keys(): list.append(entries[id])
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"extensions": list}, "  "))
		f.close()

func _fail(message: String, details: Dictionary) -> Dictionary:
	var result := {"ok": false, "error": message, "details": details}
	extension_error.emit(message, details)
	return result
