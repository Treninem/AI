extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var bridge := AndroidFileToolBridge.new()
	root.add_child(bridge)
	await process_frame
	if OS.get_name() == "Android":
		if bridge.client == null or bridge.client.get_parent() != bridge:
			push_error("Android file client must belong to the bridge")
			quit(1)
			return
	else:
		if bridge.client != null:
			push_error("Non-Android bridge must not allocate an unused file client")
			quit(2)
			return
		var analysis: Dictionary = await bridge._analyze_file({"path": "res://synthetic.txt"})
		var tree: Dictionary = await bridge._file_tree({"path": "user://synthetic"})
		if analysis.get("error") != "unsupported_platform" or tree.get("error") != "unsupported_platform":
			push_error("Non-Android direct calls must fail closed")
			quit(3)
			return
	bridge.queue_free()
	await process_frame
	print("AURORA_ANDROID_FILE_BRIDGE_LIFECYCLE_OK")
	quit(0)
