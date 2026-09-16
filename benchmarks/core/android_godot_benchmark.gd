extends Node

const REPORT_PATH := "user://core-benchmark-android-e2e.json"
const EXPECTED_SHA := "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5"
const EXPECTED_BYTES := 1282439264

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var suite_started := Time.get_ticks_usec()
	var report := {
		"schema_version": 1,
		"suite": "aurorafox_core_android_normal_path_v1",
		"status": "running",
		"platform": OS.get_name(),
		"scenarios": [],
		"performance": {},
		"core": {},
		"environment": {
			"remote_ai_allowed": false,
			"normal_path": "AIClient.chat -> AuroraCoreRuntime.chat_local_only -> AndroidLocalRuntime.chat -> AuroraFoxRuntime.chatLocal -> llama.cpp"
		}
	}
	_write_report(report)

	# Airplane/Wi-Fi/data state is configured by the emulator workflow, but the
	# measured process must prove the network is really unreachable rather than
	# trusting a settings flag. This probe runs before any inference call.
	var network_probe := await _probe_external_network()
	var network_blocked := not bool(network_probe.get("reachable", true))
	report.environment["external_network_probe_blocked"] = network_blocked
	_append(report, "offline_network_guard", network_blocked, {
		"probe_http": int(network_probe.get("http", 0)),
		"probe_error": str(network_probe.get("error", "")).substr(0, 300)
	})

	var client := AIClient.new()
	add_child(client)
	await get_tree().process_frame
	client.configure_ollama_compatibility("http://10.0.2.2:9", "benchmark-must-not-run")
	client.set_ollama_fallback(true)

	var runtime_before := client.runtime_info()
	var model_path := AuroraBundledCoreModel.runtime_candidate()
	var model_abs := ProjectSettings.globalize_path(model_path) if not model_path.is_empty() else ""
	var model_bytes := _file_size(model_path)
	var model_sha := FileAccess.get_sha256(model_path).to_lower() if not model_path.is_empty() and FileAccess.file_exists(model_path) else ""
	var caps: Dictionary = runtime_before.get("android", {}) if runtime_before.get("android", {}) is Dictionary else {}
	var identity_pass: bool = (
		OS.get_name() == "Android"
		and model_bytes == EXPECTED_BYTES
		and model_sha == EXPECTED_SHA
		and bool(runtime_before.get("self_primary", false))
		and not bool(runtime_before.get("external_ai_required", true))
		and bool(caps.get("llama_cpp", false))
	)
	report["core"] = {
		"model_path": model_path,
		"model_absolute_path_sha256": model_abs.sha256_text(),
		"actual_bytes": model_bytes,
		"prepared_sha256": model_sha,
		"expected_sha256": EXPECTED_SHA,
		"runtime_before": _compact_runtime(runtime_before),
		"capabilities": caps
	}
	_append(report, "bundled_core_identity", identity_pass, {"bytes": model_bytes, "sha256": model_sha, "llama_cpp": caps.get("llama_cpp", false)})
	if not identity_pass:
		await _finish(report, suite_started, client)
		return

	var cold := await _measure_chat(client, [{"role":"user", "content":"Reply exactly ANDROID-E2E-READY and nothing else."}], 0.0)
	var cold_text := _final_text(str(cold.result.get("content", "")))
	var cold_pass: bool = bool(cold.result.get("ok", false)) and str(cold.result.get("runtime", "")) == "aurora_core_android" and _normalized(cold_text) == "android-e2e-ready"
	_append(report, "cold_start_first_response", cold_pass, _chat_details(cold, cold_text))
	report.performance["cold_first_response_ms"] = cold.elapsed_ms

	var warm_values: Array[float] = []
	for item in [
		{"id":"basic_reasoning", "prompt":"Compute 9 * 7. Reply only with 63.", "expected":"63"},
		{"id":"russian_dialog", "prompt":"Ответь только словом ЛОКАЛЬНО.", "expected":"ЛОКАЛЬНО"}
	]:
		var row := await _measure_chat(client, [{"role":"user", "content":str(item.prompt)}], 0.0)
		var text := _final_text(str(row.result.get("content", "")))
		var passed: bool = bool(row.result.get("ok", false)) and str(row.result.get("runtime", "")) == "aurora_core_android" and _normalized(text) == _normalized(str(item.expected))
		warm_values.append(float(row.elapsed_ms))
		_append(report, str(item.id), passed, _chat_details(row, text))
	report.performance["warm_median_ms"] = _median(warm_values)

	var multi := await _measure_chat(client, [
		{"role":"user", "content":"Remember this marker for the next turn: MOBILE-42."},
		{"role":"assistant", "content":"Remembered."},
		{"role":"user", "content":"Reply only with the marker."}
	], 0.0)
	var multi_text := _final_text(str(multi.result.get("content", "")))
	var multi_pass: bool = bool(multi.result.get("ok", false)) and str(multi.result.get("runtime", "")) == "aurora_core_android" and _normalized(multi_text) == "mobile-42"
	_append(report, "multi_turn_context", multi_pass, _chat_details(multi, multi_text))

	var knowledge_import := client.import_knowledge_text(
		"Android benchmark local Core Knowledge marker is MOBILE-IVORY-29.",
		"android_core_benchmark",
		{"scope":"core_knowledge", "kind":"benchmark_fact"}
	)
	var knowledge := await _measure_chat(client, [{"role":"user", "content":"According to local Core Knowledge, reply only with the Android benchmark marker."}], 0.0)
	var knowledge_text := _final_text(str(knowledge.result.get("content", "")))
	var knowledge_pass: bool = bool(knowledge_import.get("ok", false)) and bool(knowledge.result.get("ok", false)) and str(knowledge.result.get("runtime", "")) == "aurora_core_android" and _normalized(knowledge_text) == "mobile-ivory-29"
	var knowledge_details := _chat_details(knowledge, knowledge_text)
	knowledge_details["import_ok"] = knowledge_import.get("ok", false)
	_append(report, "core_knowledge_retrieval", knowledge_pass, knowledge_details)

	var compatibility := await _measure_chat(client, [{"role":"user", "content":"Reply exactly ANDROID-COMPAT-LOCAL and nothing else."}], 0.0)
	var compatibility_text := _final_text(str(compatibility.result.get("content", "")))
	var runtime_after := client.runtime_info()
	var compatibility_pass: bool = (
		client.ollama_fallback_enabled()
		and bool(compatibility.result.get("ok", false))
		and str(compatibility.result.get("runtime", "")) == "aurora_core_android"
		and _normalized(compatibility_text) == "android-compat-local"
		and int(runtime_after.get("ollama_failures", -1)) == 0
		and not compatibility.result.has("fallback_from")
	)
	var compatibility_details := _chat_details(compatibility, compatibility_text)
	compatibility_details["compatibility_enabled"] = client.ollama_fallback_enabled()
	compatibility_details["ollama_failures"] = runtime_after.get("ollama_failures", -1)
	compatibility_details["fallback_from_present"] = compatibility.result.has("fallback_from")
	_append(report, "compatibility_switch_isolation", compatibility_pass, compatibility_details)
	report.core["runtime_after"] = _compact_runtime(runtime_after)

	await _finish(report, suite_started, client)

func _measure_chat(client: AIClient, messages: Array, temperature: float) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result: Dictionary = await client.chat(messages, temperature)
	return {"result": result, "elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0}

func _chat_details(call: Dictionary, text: String) -> Dictionary:
	var result: Dictionary = call.get("result", {})
	return {
		"elapsed_ms": float(call.get("elapsed_ms", 0.0)),
		"runtime": result.get("runtime", ""),
		"content_sha256": _normalized(text).sha256_text(),
		"content_excerpt": text.substr(0, 240),
		"error": str(result.get("error", "")).substr(0, 500)
	}

func _append(report: Dictionary, id: String, passed: bool, details: Dictionary) -> void:
	var row := {"id": id, "passed": passed}
	row.merge(details, true)
	report.scenarios.append(row)
	_write_report(report)

func _finish(report: Dictionary, started: int, client: AIClient) -> void:
	report.performance["suite_wall_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	var failed: Array = []
	for row in report.scenarios:
		if row is Dictionary and not bool(row.get("passed", false)):
			failed.append(str(row.get("id", "unknown")))
	report["failed_scenarios"] = failed
	report["passed"] = failed.is_empty() and report.scenarios.size() >= 8
	report["status"] = "completed"
	_write_report(report)
	print("AURORAFOX_ANDROID_E2E_REPORT " + JSON.stringify(report))
	client.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if bool(report.passed) else 7)

func _compact_runtime(info: Dictionary) -> Dictionary:
	return {
		"self_primary": info.get("self_primary", false),
		"external_ai_required": info.get("external_ai_required", true),
		"ollama_fallback_enabled": info.get("ollama_fallback_enabled", false),
		"ollama_failures": info.get("ollama_failures", -1),
		"last_runtime": info.get("last_runtime", ""),
		"model_installed": info.get("model_installed", false)
	}

func _normalized(text: String) -> String:
	return text.strip_edges().to_lower()

func _final_text(text: String) -> String:
	var value := text.strip_edges()
	var think_end := value.find("</think>")
	if think_end >= 0:
		value = value.substr(think_end + 8).strip_edges()
	value = value.trim_suffix("<|im_end|>").strip_edges()
	return value

func _probe_external_network() -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 3.0
	add_child(request)
	var err := request.request("http://1.1.1.1/", PackedStringArray(["User-Agent: AuroraFox-Android-Core-Benchmark/1"]), HTTPClient.METHOD_GET)
	if err != OK:
		request.queue_free()
		return {"reachable": false, "http": 0, "error": error_string(err)}
	var result: Array = await request.request_completed
	request.queue_free()
	var code := int(result[1])
	return {
		"reachable": code > 0,
		"http": code,
		"error": "" if code > 0 else "external network probe blocked or unavailable"
	}

func _file_size(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size

func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var copy := values.duplicate()
	copy.sort()
	var middle := copy.size() / 2
	if copy.size() % 2 == 1:
		return float(copy[middle])
	return (float(copy[middle - 1]) + float(copy[middle])) / 2.0

func _write_report(report: Dictionary) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()