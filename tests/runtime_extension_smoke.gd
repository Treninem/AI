extends SceneTree

func _init() -> void:
	var script := GDScript.new()
	script.source_code = "extends Node\nfunc aurora_extension_probe() -> int:\n\treturn 47\n"
	var reload_error := script.reload()
	if reload_error != OK:
		push_error("Dynamic GDScript reload failed: %s" % error_string(reload_error))
		quit(2)
		return
	if not script.can_instantiate():
		push_error("Dynamic GDScript cannot instantiate")
		quit(3)
		return
	var instance = script.new()
	if not instance is Node:
		push_error("Dynamic GDScript did not create a Node")
		quit(4)
		return
	if int(instance.call("aurora_extension_probe")) != 47:
		push_error("Dynamic GDScript method returned unexpected result")
		instance.free()
		quit(5)
		return
	instance.free()
	print("AURORA_RUNTIME_EXTENSION_SMOKE_OK")
	quit(0)
