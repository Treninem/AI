extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var models_dir := "user://models"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(models_dir))
	var preferred := models_dir.path_join("failover-preferred-test.gguf")
	var alternate := models_dir.path_join("failover-alternate-test.gguf")
	_cleanup(preferred)
	_cleanup(alternate)
	_write_fixture(preferred, "BAD!", 1024 * 1024 + 32)
	_write_fixture(alternate, "GGUF", 1024 * 1024 + 64)

	var runtime := AuroraCoreRuntime.new()
	root.add_child(runtime)
	runtime.configure_model(preferred)
	await process_frame

	var candidates := runtime._available_model_paths()
	if candidates.is_empty() or str(candidates[0]) != preferred:
		_fail("preferred local model is not first in failover order: %s" % str(candidates), 2)
		return
	if alternate not in candidates:
		_fail("valid alternate GGUF was not discovered", 3)
		return
	if runtime._looks_like_gguf(preferred):
		_fail("corrupt preferred GGUF passed header validation", 4)
		return
	if not runtime._looks_like_gguf(alternate):
		_fail("valid alternate GGUF failed header validation", 5)
		return

	var invalid := await runtime._chat_local_model(preferred, [{"role":"user", "content":"test"}], 0.0)
	if bool(invalid.get("ok", false)) or not str(invalid.get("error", "")).contains("GGUF"):
		_fail("corrupt preferred model did not fail before runtime invocation: %s" % str(invalid), 6)
		return
	runtime._record_model_failure(preferred, str(invalid.get("error", "")))
	if not runtime._model_circuit_open(preferred):
		_fail("failed preferred model was not quarantined", 7)
		return
	var health := runtime._model_failure_summary(preferred)
	if not bool(health.get("quarantined", false)) or int(health.get("failures", 0)) != 1:
		_fail("model health registry did not expose quarantine", 8)
		return
	if runtime._model_circuit_open(alternate):
		_fail("healthy alternate was quarantined with preferred model", 9)
		return

	# Replacing the failed file must invalidate its old failure identity even if
	# its retry timer has not expired, so users never need to restart AuroraFox.
	_write_fixture(preferred, "GGUF", 1024 * 1024 + 128)
	if runtime._model_circuit_open(preferred):
		_fail("replaced preferred model stayed quarantined", 10)
		return
	if not runtime._looks_like_gguf(preferred):
		_fail("replaced preferred GGUF is not recognized", 11)
		return

	# Repeated failures back off without making Ollama a requirement.
	runtime._record_model_failure(preferred, "synthetic load failure 1")
	var first_retry := float(runtime._model_failure_summary(preferred).get("retry_after_unix", 0.0))
	runtime._record_model_failure(preferred, "synthetic load failure 2")
	var second := runtime._model_failure_summary(preferred)
	if int(second.get("failures", 0)) != 2 or float(second.get("retry_after_unix", 0.0)) <= first_retry:
		_fail("model failure backoff did not increase", 12)
		return
	var info := runtime.runtime_info()
	if bool(info.get("ollama_required", true)):
		_fail("model recovery made Ollama required", 13)
		return
	if not info.has("model_health") or int(info.get("quarantined_local_model_count", 0)) < 1:
		_fail("runtime info does not expose local model health", 14)
		return

	runtime._reset_model_failure(preferred)
	runtime.queue_free()
	await process_frame
	_cleanup(preferred)
	_cleanup(alternate)
	print("LOCAL_MODEL_FAILOVER_SMOKE_OK quarantine=true recovery_on_replace=true ollama_required=false")
	quit(0)

func _write_fixture(path: String, magic: String, size: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot create GGUF fixture: " + path, 20)
		return
	file.store_buffer(magic.to_ascii_buffer())
	file.seek(maxi(4, size - 1))
	file.store_8(0)
	file.close()

func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
