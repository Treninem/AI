extends SceneTree

class FakeSelfPrimaryCore:
	extends AuroraCoreRuntime
	var local_calls := 0
	var compatibility_calls := 0

	func chat_local_only(messages: Array, temperature := 0.2) -> Dictionary:
		local_calls += 1
		return {
			"ok": true,
			"runtime": "aurora_core_test",
			"content": "local-only",
			"messages": messages,
			"temperature": temperature
		}

	func chat(messages: Array, temperature := 0.2) -> Dictionary:
		compatibility_calls += 1
		return {
			"ok": true,
			"runtime": "ollama_legacy_test",
			"content": "compatibility",
			"messages": messages,
			"temperature": temperature
		}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var client := AIClient.new()
	var fake := FakeSelfPrimaryCore.new()
	client.core_runtime = fake
	root.add_child(client)
	await process_frame

	# Deliberately enable the compatibility switch. Normal intelligence must
	# still stay on the AuroraFox-owned local-only API.
	fake.set_ollama_fallback_enabled(true)
	var normal := await client.chat([
		{"role": "user", "content": "self reliance runtime smoke"}
	], 0.17)
	if not bool(normal.get("ok", false)):
		_fail("normal local chat failed")
		return
	if str(normal.get("runtime", "")) != "aurora_core_test":
		_fail("normal chat escaped the AuroraFox local-only runtime")
		return
	if fake.local_calls != 1:
		_fail("normal chat did not call local-only runtime exactly once")
		return
	if fake.compatibility_calls != 0:
		_fail("normal chat called the external compatibility path")
		return

	# External compatibility remains possible only through an explicit call.
	var optional := await client.chat_with_compatibility([
		{"role": "user", "content": "explicit compatibility smoke"}
	], 0.21)
	if not bool(optional.get("ok", false)):
		_fail("explicit compatibility call failed")
		return
	if fake.compatibility_calls != 1:
		_fail("explicit compatibility path was not isolated")
		return
	if fake.local_calls != 1:
		_fail("explicit compatibility test unexpectedly changed the normal local call count")
		return

	var info := client.runtime_info()
	if not bool(info.get("self_primary", false)):
		_fail("runtime info does not report self_primary")
		return
	if bool(info.get("external_ai_required", true)):
		_fail("runtime info incorrectly requires external AI")
		return
	if bool(info.get("normal_chat_external_fallback", true)):
		_fail("runtime info allows normal chat external fallback")
		return

	print("SELF_RELIANCE_SMOKE_OK")
	client.queue_free()
	await process_frame
	quit(0)

func _fail(message: String) -> void:
	push_error("SELF_RELIANCE_SMOKE_FAILED: " + message)
	quit(1)
