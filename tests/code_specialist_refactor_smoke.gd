extends SceneTree

class RefactorAI:
	extends AIClient
	var replies: Array = []
	var calls := 0
	func chat(_messages: Array, _temperature: float = 0.2) -> Dictionary:
		calls += 1
		if replies.is_empty():
			return {"ok": false, "error": "Unexpected extra inference"}
		return replies.pop_front()

const ORIGINAL := "def add_numbers(a, b):\n    result = a + b\n    return result\n"
const VALID := "def add_numbers(a, b):\n    return a + b\n"
const RENAMED := "# add_numbers was renamed\ndef add(a, b):\n    return a + b\n"

func _init() -> void:
	call_deferred("_run")

func _reply(code: String) -> Dictionary:
	return {"ok": true, "content": JSON.stringify({"refactored_code": code, "changes": ["simplified"], "tests": ["proposed only"]})}

func _run() -> void:
	var ai := RefactorAI.new()
	var specialist := CodeSpecialist.new()
	specialist.general_ai = ai
	ai.replies = [_reply(VALID)]
	var valid := await specialist.refactor_code("Preserve the public API", ORIGINAL, "python")
	if not bool(valid.get("ok", false)) or ai.calls != 1:
		push_error("Valid refactor unexpectedly rejected or retried")
		quit(2)
		return
	ai.calls = 0
	ai.replies = [_reply(RENAMED), _reply(VALID)]
	var repaired := await specialist.refactor_code("Preserve the public API", ORIGINAL, "python")
	if not bool(repaired.get("ok", false)) or not bool(repaired.get("repaired_public_api", false)) or ai.calls != 2 or str(repaired.get("refactored_code", "")).strip_edges() != VALID.strip_edges():
		push_error("Renamed API was not repaired through the same client exactly once")
		quit(3)
		return
	ai.calls = 0
	ai.replies = [_reply(RENAMED), _reply(RENAMED)]
	var refused := await specialist.refactor_code("Preserve the public API", ORIGINAL, "python")
	if bool(refused.get("ok", true)) or ai.calls != 2 or not str(refused.get("error", "")).contains("public Python API"):
		push_error("Repeated public API rename did not fail closed")
		quit(4)
		return
	var async_missing: Array[String] = specialist._missing_python_public_functions("async def fetch_data():\n    pass\ndef _private():\n    pass", "async def fetch_data():\n    return 1", "python")
	if not async_missing.is_empty() or not specialist._missing_python_public_functions(ORIGINAL, RENAMED, "javascript").is_empty():
		push_error("Async/private/non-Python structural boundaries regressed")
		quit(5)
		return
	specialist.free()
	ai.free()
	print("AURORA_CODE_SPECIALIST_REFACTOR_SMOKE_OK")
	quit(0)
