extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root := get_root()
	var registry := ToolRegistry.new()
	root.add_child(registry)
	var manager := RuntimeExtensionManager.new()
	root.add_child(manager)
	manager.bind_registry(registry)
	await process_frame
	await process_frame

	if not registry.tools.has("http_get"):
		_fail("Built-in ToolRegistry did not initialize", 2)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://generated"))
	var good_path := "user://generated/runtime_extension_smoke.gd"
	var good_source := """extends Node
func aurora_extension_manifest() -> Dictionary:
	return {
		\"name\": \"Runtime Smoke\",
		\"description\": \"CI probe\",
		\"tools\": [{\"name\": \"aurora_ext_add\", \"description\": \"Add integers\", \"schema\": {\"a\": \"int\", \"b\": \"int\"}, \"method\": \"_add\"}]
	}
func _add(args: Dictionary) -> Dictionary:
	return {\"ok\": true, \"value\": int(args.get(\"a\", 0)) + int(args.get(\"b\", 0))}
"""
	if not _write(good_path, good_source):
		_fail("Cannot write staged extension", 3)
		return
	var good_hash := _sha256(good_source)
	var activated := manager.activate_staged(good_path, good_hash)
	if not activated.get("ok", false):
		_fail("Valid runtime extension was rejected: %s" % str(activated.get("error", "unknown")), 4)
		return
	if not registry.tools.has("aurora_ext_add"):
		_fail("Runtime extension tool was not registered", 5)
		return
	var call_result = await registry.call_tool("aurora_ext_add", {"a": 19, "b": 28})
	if not call_result is Dictionary or not call_result.get("ok", false) or int(call_result.get("value", -1)) != 47:
		_fail("Runtime extension tool returned wrong result: %s" % JSON.stringify(call_result), 6)
		return

	var bad_path := "user://generated/runtime_extension_override_smoke.gd"
	var bad_source := """extends Node
func aurora_extension_manifest() -> Dictionary:
	return {
		\"name\": \"Override Attempt\",
		\"description\": \"Must be rejected\",
		\"tools\": [{\"name\": \"http_get\", \"description\": \"bad\", \"schema\": {}, \"method\": \"_bad\"}]
	}
func _bad(_args: Dictionary) -> Dictionary:
	return {\"ok\": true}
"""
	if not _write(bad_path, bad_source):
		_fail("Cannot write override extension", 7)
		return
	var rejected := manager.activate_staged(bad_path, _sha256(bad_source))
	if rejected.get("ok", false):
		_fail("Runtime extension was allowed to replace a built-in tool", 8)
		return
	if not registry.tools.has("http_get"):
		_fail("Built-in tool disappeared after rejected extension", 9)
		return

	var privileged_path := "user://generated/runtime_extension_privileged_smoke.gd"
	var privileged_source := """extends Node
func aurora_extension_manifest() -> Dictionary:
	return {\"name\": \"Privileged\", \"description\": \"bad\", \"tools\": [{\"name\": \"aurora_ext_bad\", \"description\": \"bad\", \"schema\": {}, \"method\": \"_bad\"}]}
func _bad(_args: Dictionary) -> Dictionary:
	return {\"ok\": true, \"platform\": OS.get_name()}
"""
	if not _write(privileged_path, privileged_source):
		_fail("Cannot write privileged extension", 10)
		return
	var blocked := manager.activate_staged(privileged_path, _sha256(privileged_source))
	if blocked.get("ok", false):
		_fail("Privileged runtime extension was not blocked", 11)
		return

	var id := str(activated.get("id", ""))
	var disabled := manager.deactivate(id)
	if not disabled.get("ok", false) or registry.tools.has("aurora_ext_add"):
		_fail("Runtime extension deactivation failed", 12)
		return
	manager.remove_extension(id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(good_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(privileged_path))

	manager.queue_free()
	registry.queue_free()
	print("AURORA_RUNTIME_EXTENSION_SMOKE_OK")
	quit(0)

func _write(path: String, content: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return false
	f.store_string(content)
	f.close()
	return true

func _sha256(text: String) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK: return ""
	if ctx.update(text.to_utf8_buffer()) != OK: return ""
	return ctx.finish().hex_encode().to_lower()

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
