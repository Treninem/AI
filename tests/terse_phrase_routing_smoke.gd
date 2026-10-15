extends SceneTree

class PayloadProbe extends DesktopLocalRuntime:
	var captured_payload: Dictionary = {}
	func ensure_server(_model_absolute_path: String) -> Dictionary:
		return {"ok": true}
	func _request_progress_json(payload: Dictionary, _stall_seconds: float, _total_seconds: float, _byte_budget: int, _port: int = 8766) -> Dictionary:
		captured_payload = payload.duplicate(true)
		return {"ok": true, "data": {"choices": [{"message": {"content": "probe"}}]}}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var probe := PayloadProbe.new()
	var short_messages := [{"role": "user", "content": "Почему лёд плавает в воде? Ответь одним коротким предложением."}]
	if not probe._is_explicit_terse_request(short_messages):
		_fail("exact installed short-answer phrasing was not detected")
		return
	if probe._is_explicit_terse_request([{"role": "user", "content": "Почему лёд плавает в воде?"}]):
		_fail("ordinary prose was incorrectly classified as terse")
		return
	var english_messages := [{"role": "user", "content": "Write exactly two concise English sentences about a local AI assistant."}]
	if not probe._is_explicit_terse_request(english_messages):
		_fail("explicit concise English output was not detected")
		return
	if OS.get_name() != "Windows":
		probe.free()
		print("TERSE_PHRASE_CLASSIFICATION_PASS_PAYLOAD_UNVERIFIED_NONWINDOWS")
		quit(0)
		return
	var fixture := ProjectSettings.globalize_path("user://terse_phrase_probe.gguf")
	var file := FileAccess.open(fixture, FileAccess.WRITE)
	if file == null:
		_fail("could not create synthetic model fixture")
		return
	file.store_string("fixture")
	file.close()
	var result := await probe.chat(fixture, short_messages)
	if not bool(result.get("ok", false)) or not bool(result.get("terse_request", false)):
		_fail("production chat did not use terse route")
		return
	if probe.captured_payload.get("reasoning_effort", "") != "none":
		_fail("short-answer payload retained hidden reasoning")
		return
	if int(probe.captured_payload.get("max_tokens", -1)) != OwnerResourcePolicy.value("terse_max_tokens"):
		_fail("short-answer payload did not use the owner terse token budget")
		return
	var english := await probe.chat(fixture, english_messages)
	if not bool(english.get("ok", false)) or not bool(english.get("terse_request", false)) or probe.captured_payload.get("reasoning_effort", "") != "none":
		_fail("explicit concise English payload retained hidden reasoning")
		return
	var ordinary := await probe.chat(fixture, [{"role": "user", "content": "Почему лёд плавает в воде?"}])
	if not bool(ordinary.get("ok", false)) or bool(ordinary.get("terse_request", true)) or probe.captured_payload.has("reasoning_effort"):
		_fail("ordinary prose route changed")
		return
	var structured := await probe.chat(fixture, [{"role": "user", "content": "Верни только строгий JSON"}])
	if not bool(structured.get("ok", false)) or bool(structured.get("terse_request", true)) or probe.captured_payload.get("response_format", {}) != {"type": "json_object"}:
		_fail("strict JSON route changed")
		return
	DirAccess.remove_absolute(fixture)
	probe.free()
	print("TERSE_PHRASE_ROUTING_SMOKE_PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
