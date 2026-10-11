extends SceneTree

class ChatSink extends Node:
	var messages: Array[String] = []
	func submit_voice_text(value: String) -> void:
		messages.append(value)

func _initialize() -> void:
	var sink := ChatSink.new()
	root.add_child(sink)
	var overlay: Node = load("res://scripts/voice_overlay.gd").new()
	sink.add_child(overlay)
	overlay.call("_submit_transcript", "unprompted background speech")
	if not sink.messages.is_empty():
		_fail("background transcript reached chat")
		return
	overlay.set("explicit_listen_until_ms", Time.get_ticks_msec() + 30000)
	overlay.call("_submit_transcript", "explicit request")
	if sink.messages != ["explicit request"] or int(overlay.get("explicit_listen_until_ms")) != 0:
		_fail("explicit request was not submitted exactly once")
		return
	overlay.call("_submit_transcript", "second background segment")
	if sink.messages.size() != 1:
		_fail("a second segment reached chat without consent")
		return
	overlay.call("_submit_transcript", "push to talk", true)
	if sink.messages != ["explicit request", "push to talk"]:
		_fail("push-to-talk request was lost")
		return
	print("VOICE_OVERLAY_CONSENT_PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
