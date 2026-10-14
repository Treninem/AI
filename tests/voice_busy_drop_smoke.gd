extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var user_dir := ProjectSettings.globalize_path("user://").to_lower()
	if not user_dir.contains("voice-busy-drop-profile"):
		_fail("isolated synthetic profile required")
		return
	var main = load("res://scripts/main.gd").new()
	main.input = TextEdit.new()
	main.status = Label.new()
	main.request_busy = true
	main.submit_voice_text("synthetic delayed voice text")
	if not main.input.text.is_empty() or not main.status.text.contains("не отправлен"):
		_fail("busy request accepted a delayed voice transcript")
		return
	main.request_busy = false
	main.file_processing_busy = true
	main.status.text = ""
	main.submit_voice_text("synthetic file-time voice text")
	if not main.input.text.is_empty() or not main.status.text.contains("не отправлен"):
		_fail("file analysis accepted a delayed voice transcript")
		return
	main.file_processing_busy = false
	await process_frame
	if not main.input.text.is_empty():
		_fail("busy voice transcript appeared after work completed")
		return
	main.input.free()
	main.status.free()
	for field in ["ai", "memory", "tools", "agent", "improver", "chats", "attachments", "public_web"]:
		var value = main.get(field)
		if value is Node:
			value.free()
	main.free()
	print("VOICE_BUSY_DROP_SMOKE_PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
