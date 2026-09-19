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

	# Exercise the packaged Android plugin and its real bundled assets from the
	# installed, offline release APK. Static Kotlin/asset checks do not prove that
	# Godot can invoke these runtimes after installation.
	var android_runtime := AndroidLocalRuntime.new()
	add_child(android_runtime)
	await get_tree().process_frame
	var voice_caps := android_runtime.capabilities()
	var tts_started := Time.get_ticks_usec()
	var tts := android_runtime.synthesize_speech("Аврора проверяет локальный голос: один, два, три.", 1.0, "neutral", 0.5)
	var tts_path := str(tts.get("path", ""))
	var tts_bytes := _file_size(tts_path)
	var tts_pass: bool = (
		bool(voice_caps.get("local_tts", false))
		and bool(tts.get("ok", false))
		and str(tts.get("engine", "")) == "sherpa-onnx-supertonic-3"
		and str(tts.get("language", "")) == "ru"
		and float(tts.get("duration", 0.0)) > 0.0
		and tts_bytes > 1024
	)
	_append(report, "installed_voice_tts", tts_pass, {
		"elapsed_ms": float(Time.get_ticks_usec() - tts_started) / 1000.0,
		"engine": tts.get("engine", ""),
		"language": tts.get("language", ""),
		"duration": tts.get("duration", 0.0),
		"wav_bytes": tts_bytes,
		"wav_sha256": FileAccess.get_sha256(tts_path) if tts_bytes > 0 else "",
		"error": str(tts.get("error", "")).substr(0, 500)
	})

	var stt_started := Time.get_ticks_usec()
	var stt := android_runtime.transcribe("", tts_path, "ru") if tts_bytes > 0 else {"ok": false, "error": "TTS fixture WAV is unavailable"}
	var stt_text := str(stt.get("text", "")).strip_edges()
	var stt_pass: bool = (
		bool(voice_caps.get("sherpa_stt", false))
		and bool(stt.get("ok", false))
		and str(stt.get("engine", "")) == "sherpa-onnx-whisper-tiny"
		and not stt_text.is_empty()
	)
	_append(report, "installed_voice_stt", stt_pass, {
		"elapsed_ms": float(Time.get_ticks_usec() - stt_started) / 1000.0,
		"engine": stt.get("engine", ""),
		"language": stt.get("language", ""),
		"text_sha256": _normalized(stt_text).sha256_text(),
		"text_excerpt": stt_text.substr(0, 160),
		"error": str(stt.get("error", "")).substr(0, 500)
	})

	var fixture := await _create_bilingual_ocr_fixture()
	var file_client := FileIntelligenceClient.new()
	add_child(file_client)
	await get_tree().process_frame
	var ocr_started := Time.get_ticks_usec()
	var ocr: Dictionary = await file_client.analyze_file(str(fixture.get("path", "")), "", true) if bool(fixture.get("ok", false)) else {"ok": false, "error": fixture.get("error", "OCR fixture creation failed")}
	var ocr_text := str(ocr.get("content", ""))
	var ocr_normalized := _normalized(ocr_text)
	var ocr_meta: Dictionary = ocr.get("metadata", {}) if ocr.get("metadata", {}) is Dictionary else {}
	var ocr_health: Dictionary = voice_caps.get("local_ocr_health", {}) if voice_caps.get("local_ocr_health", {}) is Dictionary else {}
	var ocr_languages: Array = ocr_health.get("languages", []) if ocr_health.get("languages", []) is Array else []
	var ocr_pass: bool = (
		bool(voice_caps.get("local_ocr", false))
		and str(ocr_health.get("engine", "")) == "tesseract4android"
		and "rus" in ocr_languages
		and "eng" in ocr_languages
		and bool(ocr.get("ok", false))
		and str(ocr.get("kind", "")) == "image"
		and bool(ocr_meta.get("local_ocr", false))
		and bool(ocr_meta.get("offline", false))
		and not bool(ocr_meta.get("external_ai_required", true))
		and ocr_normalized.contains("aurora")
		and ocr_normalized.contains("7429")
		and ocr_normalized.contains("аврора")
		and ocr_normalized.contains("5183")
	)
	_append(report, "installed_ocr_bilingual", ocr_pass, {
		"elapsed_ms": float(Time.get_ticks_usec() - ocr_started) / 1000.0,
		"kind": ocr.get("kind", ""),
		"fixture_sha256": fixture.get("sha256", ""),
		"content_sha256": ocr_normalized.sha256_text(),
		"content_excerpt": ocr_text.substr(0, 240),
		"engine": ocr_health.get("engine", ocr_meta.get("engine", "")),
		"languages": ocr_languages,
		"offline": ocr_meta.get("offline", false),
		"external_ai_required": ocr_meta.get("external_ai_required", true),
		"error": str(ocr.get("error", "")).substr(0, 500)
	})
	file_client.queue_free()
	android_runtime.queue_free()

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
	report["passed"] = failed.is_empty() and report.scenarios.size() >= 11
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

func _create_bilingual_ocr_fixture() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 420)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var background := ColorRect.new()
	background.position = Vector2.ZERO
	background.size = Vector2(viewport.size)
	background.color = Color.WHITE
	viewport.add_child(background)

	var label := Label.new()
	label.position = Vector2(40, 24)
	label.size = Vector2(1200, 372)
	label.text = "AURORA 7429\nАВРОРА 5183"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_font_size_override("font_size", 112)
	viewport.add_child(label)

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null or image.is_empty():
		return {"ok": false, "error": "Godot did not render the bilingual OCR fixture"}
	var path := "user://android-installed-ocr-e2e.png"
	var save_error := image.save_png(path)
	if save_error != OK:
		return {"ok": false, "error": "Cannot save OCR fixture: " + error_string(save_error)}
	return {
		"ok": true,
		"path": path,
		"sha256": FileAccess.get_sha256(path),
		"bytes": _file_size(path)
	}

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
