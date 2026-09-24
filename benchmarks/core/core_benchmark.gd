extends SceneTree

const REPORT_SCHEMA_VERSION := 1
const DEFAULT_SCENARIO_TIMEOUT_MS := 120000
const LOCAL_RUNTIMES := ["aurora_core_desktop", "aurora_core_native", "aurora_core_android"]

class AsyncChatCall:
	extends Node
	signal completed(result: Dictionary, elapsed_ms: float)

	func start(ai: AIClient, messages: Array, temperature: float) -> void:
		call_deferred("_execute", ai, messages, temperature)

	func _execute(ai: AIClient, messages: Array, temperature: float) -> void:
		var started := Time.get_ticks_usec()
		var result: Dictionary = await ai.chat(messages, temperature)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		completed.emit(result, elapsed)

class AsyncAgentCall:
	extends Node
	signal completed(answer: String, elapsed_ms: float)

	func start(agent: AgentCore, task: String, context: Array = []) -> void:
		call_deferred("_execute", agent, task, context)

	func _execute(agent: AgentCore, task: String, context: Array) -> void:
		var started := Time.get_ticks_usec()
		var answer := await agent.run_task(task, context)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		completed.emit(answer, elapsed)

class AsyncPlanCall:
	extends Node
	signal completed(plan: Dictionary, elapsed_ms: float)

	func start(cognition: CognitionLayer, task: String) -> void:
		call_deferred("_execute", cognition, task)

	func _execute(cognition: CognitionLayer, task: String) -> void:
		var started := Time.get_ticks_usec()
		var plan := await cognition.make_plan(task, [], [])
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		completed.emit(plan, elapsed)

var _report: Dictionary = {}
var _report_path := ""
var _suite_started_ms := 0
var _scenario_timeout_ms := DEFAULT_SCENARIO_TIMEOUT_MS
var _timeout_count := 0
var _warm_latencies: Array[float] = []
var _warm_throughputs: Array[float] = []
var _probe_calls := 0
var _probe_last_value := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_suite_started_ms = Time.get_ticks_msec()
	_report_path = OS.get_environment("AURORAFOX_BENCHMARK_REPORT").strip_edges()
	if _report_path.is_empty():
		_report_path = ProjectSettings.globalize_path("user://core-benchmark-report.json")
	var configured_timeout := int(OS.get_environment("AURORAFOX_BENCHMARK_SCENARIO_TIMEOUT_MS"))
	if configured_timeout > 0:
		_scenario_timeout_ms = configured_timeout

	_report = {
		"schema_version": REPORT_SCHEMA_VERSION,
		"suite": "aurorafox_core_quality_v1",
		"status": "running",
		"started_at": Time.get_datetime_string_from_system(true),
		"git_sha": OS.get_environment("AURORAFOX_BENCHMARK_GIT_SHA"),
		"platform": OS.get_name(),
		"machine": {
			"os": OS.get_name(),
			"arch": OS.get_environment("PROCESSOR_ARCHITECTURE"),
			"logical_processors": OS.get_processor_count(),
			"processor_identifier": OS.get_environment("AURORAFOX_BENCHMARK_CPU")
		},
		"environment": {
			"network_guard_required": OS.get_environment("AURORAFOX_BENCHMARK_REQUIRE_NETWORK_GUARD") == "1",
			"network_guard_os_active": OS.get_environment("AURORAFOX_BENCHMARK_NETWORK_GUARD_ACTIVE") == "1",
			"ollama_absent_os_verified": OS.get_environment("AURORAFOX_BENCHMARK_OLLAMA_ABSENT") == "1",
			"clean_user_requested": OS.get_environment("AURORAFOX_BENCHMARK_CLEAN_USER") == "1",
			"remote_ai_allowed": false,
			"fixture_core_used": false
		},
		"core": {},
		"scenarios": [],
		"performance": {
			"cold_first_response_ms": 0.0,
			"warm_median_ms": 0.0,
			"throughput_equivalent_tps": 0.0,
			"peak_rss_mb": 0.0,
			"suite_wall_ms": 0.0,
			"timeout_count": 0
		}
	}
	_write_report()

	var clean_requested := bool(_report.environment.clean_user_requested)
	var clean_ok := _clean_benchmark_state() if clean_requested else false
	_record_scenario("clean_start_state", clean_requested and clean_ok, {
		"clean_user_requested": clean_requested,
		"isolated_ephemeral_runner_required": true
	})

	var network_probe := await _probe_external_network()
	var network_required := bool(_report.environment.network_guard_required)
	var network_os_guard := bool(_report.environment.network_guard_os_active)
	var network_blocked := not bool(network_probe.get("reachable", true))
	_record_scenario("offline_network_guard", network_required and network_os_guard and network_blocked, {
		"os_guard_active": network_os_guard,
		"probe_blocked": network_blocked,
		"probe_http": int(network_probe.get("http", 0)),
		"probe_error": str(network_probe.get("error", "")).substr(0, 300)
	})

	var client := AIClient.new()
	root.add_child(client)
	await process_frame
	client.configure_ollama_compatibility("http://127.0.0.1:9", "benchmark-must-not-run")
	client.set_ollama_fallback(true)

	var runtime_before := client.runtime_info()
	var model_path := AuroraBundledCoreModel.runtime_candidate()
	var model_size := _file_size(model_path)
	var prepared_sha := OS.get_environment("AURORAFOX_BENCHMARK_MODEL_SHA").to_lower()
	_report["core"] = {
		"model_path": model_path,
		"expected_bytes": AuroraBundledCoreModel.EXPECTED_BYTES,
		"actual_bytes": model_size,
		"expected_sha256": AuroraBundledCoreModel.EXPECTED_SHA256,
		"prepared_sha256": prepared_sha,
		"runtime_before": _compact_runtime_info(runtime_before)
	}
	var bundled_ok := (
		not model_path.is_empty()
		and model_size == AuroraBundledCoreModel.EXPECTED_BYTES
		and prepared_sha == AuroraBundledCoreModel.EXPECTED_SHA256
		and bool(runtime_before.get("self_primary", false))
		and not bool(runtime_before.get("external_ai_required", true))
		and not bool(runtime_before.get("normal_chat_external_fallback", true))
		and bool(runtime_before.get("operational_without_ollama", false))
	)
	_record_scenario("bundled_core_identity", bundled_ok, {
		"model_path": model_path,
		"bytes": model_size,
		"sha256": prepared_sha,
		"self_primary": runtime_before.get("self_primary", false),
		"external_ai_required": runtime_before.get("external_ai_required", true)
	})
	if not bundled_ok:
		await _finish(client, 3)
		return

	var ollama_absent := bool(_report.environment.ollama_absent_os_verified)
	_record_scenario("ollama_absent", ollama_absent, {
		"os_process_check": ollama_absent,
		"compatibility_switch_enabled": client.ollama_fallback_enabled()
	})

	var cold := await _chat_with_watchdog(client, [
		{"role": "user", "content": "Reply with exactly CORE-LOCAL-READY and nothing else."}
	], 0.0)
	if await _handle_timeout("cold_start_first_response", cold, client): return
	var cold_text := _final_text(str(cold.result.get("content", "")))
	var cold_pass := bool(cold.result.get("ok", false)) and _normalized(cold_text) == "core-local-ready" and _is_local_runtime(cold.result)
	var cold_row := _chat_row("cold_start_first_response", cold, cold_pass, {"expected": "CORE-LOCAL-READY"})
	_append_scenario(cold_row)
	_report.performance.cold_first_response_ms = float(cold.elapsed_ms)

	var warm_ok := true
	var warm_outputs: Array = []
	for i in range(1, 4):
		var expected := "WARM-%d" % i
		var warm := await _chat_with_watchdog(client, [
			{"role": "user", "content": "Reply exactly %s and nothing else." % expected}
		], 0.0)
		if bool(warm.get("timeout", false)):
			warm_ok = false
			_timeout_count += 1
			warm_outputs.append({"timeout": true, "expected": expected})
			break
		var text := _final_text(str(warm.result.get("content", "")))
		var passed := bool(warm.result.get("ok", false)) and _normalized(text) == expected.to_lower() and _is_local_runtime(warm.result)
		warm_ok = warm_ok and passed
		var perf := _throughput_metrics(warm.result, float(warm.elapsed_ms), text)
		_warm_latencies.append(float(warm.elapsed_ms))
		_warm_throughputs.append(float(perf.get("throughput_equivalent_tps", 0.0)))
		warm_outputs.append({
			"expected": expected,
			"passed": passed,
			"elapsed_ms": warm.elapsed_ms,
			"runtime": warm.result.get("runtime", ""),
			"throughput_equivalent_tps": perf.get("throughput_equivalent_tps", 0.0),
			"output_sha256": _normalized(text).sha256_text()
		})
	_record_scenario("warm_followup", warm_ok and warm_outputs.size() == 3, {"samples": warm_outputs}, "aurora_core_desktop" if OS.get_name() == "Windows" else "")
	if not warm_ok:
		await _finish(client, 4)
		return

	var ru := await _run_direct_case(client, "russian_dialog", "Ответь одной короткой фразой по-русски: назови столицу России и обязательно используй слово «Москва».", func(text: String) -> bool:
		return text.to_lower().contains("москва") and _contains_cyrillic(text)
	)
	if ru: return

	var en := await _run_direct_case(client, "english_dialog", "In one short English sentence, name the planet where humans live. Include the word Earth.", func(text: String) -> bool:
		return text.to_lower().contains("earth") and text.length() >= 5
	)
	if en: return

	var instruction := await _run_direct_case(client, "instruction_following", "Output exactly BLUE-17 and nothing else.", func(text: String) -> bool:
		return _normalized(text) == "blue-17"
	)
	if instruction: return

	var multi := await _chat_with_watchdog(client, [
		{"role": "user", "content": "Remember this passphrase for the next turn: MINT-42."},
		{"role": "assistant", "content": "Remembered."},
		{"role": "user", "content": "What passphrase did I give you? Reply only with the passphrase."}
	], 0.0)
	if await _handle_timeout("multi_turn_context", multi, client): return
	var multi_text := _final_text(str(multi.result.get("content", "")))
	_append_scenario(_chat_row("multi_turn_context", multi, bool(multi.result.get("ok", false)) and _normalized(multi_text) == "mint-42" and _is_local_runtime(multi.result), {}))

	var memory := MemoryStore.new()
	root.add_child(memory)
	await process_frame
	memory.remember("benchmark_fact", "The AuroraFox benchmark memory marker is CEDAR-58.", "core_benchmark", 0.95, 1.0)
	var empty_tools := ToolRegistry.new()
	root.add_child(empty_tools)
	await process_frame
	empty_tools.tools.clear()
	var memory_agent := AgentCore.new()
	memory_agent.enable_planning = false
	memory_agent.enable_self_check = false
	memory_agent.enable_skill_learning = false
	memory_agent.enable_dream_cycle = false
	memory_agent.enable_specialist_team = false
	memory_agent.max_steps = 2
	root.add_child(memory_agent)
	memory_agent.setup(client, memory, empty_tools)
	var memory_call := await _agent_with_watchdog(memory_agent, "Using your relevant local long-term memory, reply only with the benchmark memory marker.")
	if await _handle_agent_timeout("local_memory_retrieval", memory_call, client): return
	var memory_text := _final_text(str(memory_call.answer))
	var retrieved := await memory.retrieve("benchmark memory marker", 5, true, true)
	var retrieval_has_marker := JSON.stringify(retrieved).contains("CEDAR-58")
	var memory_exact_format := _normalized(memory_text) == "cedar-58"
	var memory_answer_has_marker := memory_exact_format
	if not memory_answer_has_marker:
		var parsed_memory = JSON.parse_string(memory_text)
		if parsed_memory is Dictionary or parsed_memory is Array:
			memory_answer_has_marker = JSON.stringify(parsed_memory).to_upper().contains("CEDAR-58")
	_record_scenario("local_memory_retrieval", memory_answer_has_marker and retrieval_has_marker, {
		"elapsed_ms": memory_call.elapsed_ms,
		"retrieval_contains_marker": retrieval_has_marker,
		"answer_contains_marker": memory_answer_has_marker,
		"answer_exact_format": memory_exact_format,
		"answer_excerpt": memory_text.substr(0, 160),
		"answer_sha256": _normalized(memory_text).sha256_text()
	}, "aurora_core_desktop" if OS.get_name() == "Windows" else "")

	var knowledge_import := client.import_knowledge_text(
		"Benchmark local Core Knowledge fact: the codeword for glacier protocol is IVORY-29.",
		"core_benchmark_local",
		{"scope": "core_knowledge", "kind": "benchmark_fact"}
	)
	var knowledge_call := await _chat_with_watchdog(client, [
		{"role": "user", "content": "According to local Core Knowledge, what is the codeword for glacier protocol? Reply only with the codeword."}
	], 0.0)
	if await _handle_timeout("core_knowledge_retrieval", knowledge_call, client): return
	var knowledge_text := _final_text(str(knowledge_call.result.get("content", "")))
	_append_scenario(_chat_row("core_knowledge_retrieval", knowledge_call,
		bool(knowledge_import.get("ok", false)) and _normalized(knowledge_text) == "ivory-29" and _is_local_runtime(knowledge_call.result),
		{"import_ok": knowledge_import.get("ok", false)}))

	var cognition := CognitionLayer.new()
	root.add_child(cognition)
	cognition.setup(client)
	var plan_call := await _plan_with_watchdog(cognition, "Prepare a cup of tea safely using a kettle. Give a short practical plan.")
	if await _handle_plan_timeout("simple_planning", plan_call, client): return
	var plan: Dictionary = plan_call.plan
	var plan_steps: Array = plan.get("steps", [])
	var plan_checks: Array = plan.get("success_checks", [])
	_record_scenario("simple_planning", plan_steps.size() >= 2 and not str(plan.get("objective", "")).is_empty(), {
		"elapsed_ms": plan_call.elapsed_ms,
		"step_count": plan_steps.size(),
		"success_check_count": plan_checks.size(),
		"needs_tools": plan.get("needs_tools", false)
	}, "aurora_core_desktop" if OS.get_name() == "Windows" else "")

	var safe_tools := ToolRegistry.new()
	root.add_child(safe_tools)
	await process_frame
	safe_tools.tools.clear()
	safe_tools.register_tool("benchmark_probe", "Read-only benchmark probe. Returns a local marker and performs no external or destructive action.", {"value": "string"}, Callable(self, "_benchmark_probe"))
	var tool_memory := MemoryStore.new()
	root.add_child(tool_memory)
	await process_frame
	var tool_agent := AgentCore.new()
	tool_agent.enable_planning = false
	tool_agent.enable_self_check = false
	tool_agent.enable_skill_learning = false
	tool_agent.enable_dream_cycle = false
	tool_agent.enable_specialist_team = false
	tool_agent.max_steps = 1
	root.add_child(tool_agent)
	tool_agent.setup(client, tool_memory, safe_tools)
	_probe_calls = 0
	_probe_last_value = ""
	var tool_call := await _agent_with_watchdog(tool_agent, "Use the read-only benchmark_probe tool exactly once with value GREEN-73. Reply only with the tool-action JSON and nothing else.")
	if await _handle_agent_timeout("safe_tool_selection", tool_call, client): return
	var tool_answer := _final_text(str(tool_call.answer))
	_record_scenario("safe_tool_selection", _probe_calls == 1 and _probe_last_value == "GREEN-73", {
		"elapsed_ms": tool_call.elapsed_ms,
		"tool_calls": _probe_calls,
		"selected_tool": "benchmark_probe" if _probe_calls == 1 else "",
		"selected_value": _probe_last_value,
		"single_step_selection_gate": true,
		"dangerous_tools_exposed": false,
		"answer_excerpt": tool_answer.substr(0, 160)
	}, "aurora_core_desktop" if OS.get_name() == "Windows" else "")

	var text_generation := await _run_direct_case(client, "text_generation", "Write exactly two concise English sentences about a local AI assistant. Include the words local, memory, and planning.", func(text: String) -> bool:
		var lower := text.to_lower()
		return text.length() >= 40 and lower.contains("local") and lower.contains("memory") and lower.contains("planning")
	)
	if text_generation: return

	var code_generation := await _run_direct_case(client, "code_generation_explanation", "Write a tiny Python function named add_numbers(a, b) that returns their sum, then add one short sentence explaining it. Do not use imports.", func(text: String) -> bool:
		var lower := text.to_lower()
		return lower.contains("def add_numbers") and lower.contains("return") and lower.contains("a + b") and text.length() >= 45
	)
	if code_generation: return

	var reasoning := await _run_direct_case(client, "basic_reasoning", "Compute 17 * 6. Reply only with the integer result.", func(text: String) -> bool:
		var normalized := _normalized(text)
		return normalized == "102" or normalized.ends_with("= 102") or normalized.ends_with("=102")
	)
	if reasoning: return

	var corrupted := await _run_direct_case(client, "corrupted_input", "Noise: � � ### \\x00 [broken] !!!. Ignore the noise and reply exactly SAFE-INPUT.", func(text: String) -> bool:
		return _normalized(text) == "safe-input"
	)
	if corrupted: return

	var long_context := "BEGIN CONTEXT\n"
	for i in range(120):
		long_context += "Record %03d: ordinary local benchmark filler about files, memory and planning.\n" % i
	long_context += "Critical marker: LANTERN-64.\n"
	for i in range(120, 180):
		long_context += "Record %03d: more ordinary filler for context retention.\n" % i
	long_context += "END CONTEXT\nQuestion: What is the critical marker? Reply only with the marker."
	var long_call := await _chat_with_watchdog(client, [{"role": "user", "content": long_context}], 0.0)
	if await _handle_timeout("long_context", long_call, client): return
	var long_text := _final_text(str(long_call.result.get("content", "")))
	_append_scenario(_chat_row("long_context", long_call, _normalized(long_text) == "lantern-64" and _is_local_runtime(long_call.result), {"prompt_chars": long_context.length()}))

	var compatibility := await _chat_with_watchdog(client, [
		{"role": "user", "content": "Reply exactly COMPAT-LOCAL and nothing else."}
	], 0.0)
	if await _handle_timeout("compatibility_switch_isolation", compatibility, client): return
	var compatibility_text := _final_text(str(compatibility.result.get("content", "")))
	var runtime_after_compat := client.runtime_info()
	var compatibility_pass: bool = (
		client.ollama_fallback_enabled()
		and bool(compatibility.result.get("ok", false))
		and _normalized(compatibility_text) == "compat-local"
		and _is_local_runtime(compatibility.result)
		and int(runtime_after_compat.get("ollama_failures", -1)) == 0
		and not compatibility.result.has("fallback_from")
	)
	_append_scenario(_chat_row("compatibility_switch_isolation", compatibility, compatibility_pass, {
		"compatibility_enabled": client.ollama_fallback_enabled(),
		"ollama_failures": runtime_after_compat.get("ollama_failures", -1),
		"fallback_from_present": compatibility.result.has("fallback_from")
	}))

	var repeat_outputs: Array = []
	var semantic_passes := 0
	var fingerprint_counts: Dictionary = {}
	for _repeat in range(3):
		var repeated := await _chat_with_watchdog(client, [
			{"role": "user", "content": "Reply exactly RPT-31 and nothing else."}
		], 0.0)
		if bool(repeated.get("timeout", false)):
			_timeout_count += 1
			repeat_outputs.append({"timeout": true})
			continue
		var repeat_text := _final_text(str(repeated.result.get("content", "")))
		var semantic_ok := _normalized(repeat_text) == "rpt-31" and _is_local_runtime(repeated.result)
		if semantic_ok: semantic_passes += 1
		var fingerprint := _normalized(repeat_text).sha256_text()
		fingerprint_counts[fingerprint] = int(fingerprint_counts.get(fingerprint, 0)) + 1
		repeat_outputs.append({
			"passed": semantic_ok,
			"elapsed_ms": repeated.elapsed_ms,
			"output_sha256": fingerprint,
			"runtime": repeated.result.get("runtime", "")
		})
	var most_common := 0
	for count in fingerprint_counts.values(): most_common = maxi(most_common, int(count))
	var exact_ratio := float(most_common) / 3.0
	_record_scenario("repeatability", semantic_passes == 3 and exact_ratio >= (2.0 / 3.0), {
		"semantic_passes": semantic_passes,
		"samples": 3,
		"exact_fingerprint_ratio": exact_ratio,
		"results": repeat_outputs
	}, "aurora_core_desktop" if OS.get_name() == "Windows" else "")

	var final_info := client.runtime_info()
	_report.core["runtime_after"] = _compact_runtime_info(final_info)
	await _finish(client, 0)

func _run_direct_case(client: AIClient, id: String, prompt: String, validator: Callable) -> bool:
	var call := await _chat_with_watchdog(client, [{"role": "user", "content": prompt}], 0.0)
	if await _handle_timeout(id, call, client):
		return true
	var text := _final_text(str(call.result.get("content", "")))
	var passed := bool(call.result.get("ok", false)) and _is_local_runtime(call.result) and bool(validator.call(text))
	_append_scenario(_chat_row(id, call, passed, {}))
	return false

func _chat_with_watchdog(client: AIClient, messages: Array, temperature: float) -> Dictionary:
	var worker := AsyncChatCall.new()
	root.add_child(worker)
	var state := {"done": false, "result": {}, "elapsed_ms": 0.0}
	worker.completed.connect(func(result: Dictionary, elapsed_ms: float):
		state["done"] = true
		state["result"] = result
		state["elapsed_ms"] = elapsed_ms
	)
	worker.start(client, messages, temperature)
	var deadline := Time.get_ticks_msec() + _scenario_timeout_ms
	while not bool(state.done):
		if Time.get_ticks_msec() >= deadline:
			worker.queue_free()
			return {"timeout": true, "elapsed_ms": float(_scenario_timeout_ms), "result": {}}
		await process_frame
	worker.queue_free()
	return {"timeout": false, "elapsed_ms": float(state.elapsed_ms), "result": state.result}

func _agent_with_watchdog(agent: AgentCore, task: String) -> Dictionary:
	var worker := AsyncAgentCall.new()
	root.add_child(worker)
	var state := {"done": false, "answer": "", "elapsed_ms": 0.0}
	worker.completed.connect(func(answer: String, elapsed_ms: float):
		state["done"] = true
		state["answer"] = answer
		state["elapsed_ms"] = elapsed_ms
	)
	worker.start(agent, task)
	var deadline := Time.get_ticks_msec() + _scenario_timeout_ms
	while not bool(state.done):
		if Time.get_ticks_msec() >= deadline:
			worker.queue_free()
			return {"timeout": true, "elapsed_ms": float(_scenario_timeout_ms), "answer": ""}
		await process_frame
	worker.queue_free()
	return {"timeout": false, "elapsed_ms": float(state.elapsed_ms), "answer": str(state.answer)}

func _plan_with_watchdog(cognition: CognitionLayer, task: String) -> Dictionary:
	var worker := AsyncPlanCall.new()
	root.add_child(worker)
	var state := {"done": false, "plan": {}, "elapsed_ms": 0.0}
	worker.completed.connect(func(plan: Dictionary, elapsed_ms: float):
		state["done"] = true
		state["plan"] = plan
		state["elapsed_ms"] = elapsed_ms
	)
	worker.start(cognition, task)
	var deadline := Time.get_ticks_msec() + _scenario_timeout_ms
	while not bool(state.done):
		if Time.get_ticks_msec() >= deadline:
			worker.queue_free()
			return {"timeout": true, "elapsed_ms": float(_scenario_timeout_ms), "plan": {}}
		await process_frame
	worker.queue_free()
	return {"timeout": false, "elapsed_ms": float(state.elapsed_ms), "plan": state.plan}

func _handle_timeout(id: String, call: Dictionary, client: AIClient) -> bool:
	if not bool(call.get("timeout", false)):
		return false
	_timeout_count += 1
	_record_scenario(id, false, {"timeout_ms": _scenario_timeout_ms}, "", true)
	_report.status = "scenario_timeout"
	await _finish(client, 124)
	return true

func _handle_agent_timeout(id: String, call: Dictionary, client: AIClient) -> bool:
	return await _handle_timeout(id, call, client)

func _handle_plan_timeout(id: String, call: Dictionary, client: AIClient) -> bool:
	return await _handle_timeout(id, call, client)

func _chat_row(id: String, call: Dictionary, passed: bool, details: Dictionary) -> Dictionary:
	var result: Dictionary = call.get("result", {})
	var text := _final_text(str(result.get("content", "")))
	var perf := _throughput_metrics(result, float(call.get("elapsed_ms", 0.0)), text)
	var row := {
		"id": id,
		"required": true,
		"passed": passed,
		"timeout": false,
		"elapsed_ms": float(call.get("elapsed_ms", 0.0)),
		"runtime": str(result.get("runtime", "")),
		"output_excerpt": text.substr(0, 600),
		"output_sha256": _normalized(text).sha256_text(),
		"completion_tokens": perf.get("completion_tokens", 0),
		"throughput_equivalent_tps": perf.get("throughput_equivalent_tps", 0.0),
		"throughput_source": perf.get("throughput_source", ""),
		"details": details
	}
	return row

func _throughput_metrics(result: Dictionary, elapsed_ms: float, final_text: String) -> Dictionary:
	var completion_tokens := 0
	var raw = result.get("raw", {})
	if raw is Dictionary:
		var usage = raw.get("usage", {})
		if usage is Dictionary:
			completion_tokens = int(usage.get("completion_tokens", 0))
	var seconds := maxf(0.001, elapsed_ms / 1000.0)
	if completion_tokens > 0:
		return {
			"completion_tokens": completion_tokens,
			"throughput_equivalent_tps": float(completion_tokens) / seconds,
			"throughput_source": "reported_completion_tokens_per_wall_second"
		}
	var equivalent_tokens := maxf(1.0, float(final_text.to_utf8_buffer().size()) / 4.0)
	return {
		"completion_tokens": 0,
		"throughput_equivalent_tps": equivalent_tokens / seconds,
		"throughput_source": "utf8_bytes_div_4_per_wall_second"
	}

func _record_scenario(id: String, passed: bool, details: Dictionary = {}, runtime: String = "", timeout := false) -> void:
	_append_scenario({
		"id": id,
		"required": true,
		"passed": passed,
		"timeout": timeout,
		"runtime": runtime,
		"details": details
	})

func _append_scenario(row: Dictionary) -> void:
	_report.scenarios.append(row)
	_write_report()
	var marker := "PASS" if bool(row.get("passed", false)) else "FAIL"
	print("CORE_BENCHMARK_SCENARIO %s %s" % [marker, str(row.get("id", "unknown"))])

func _finish(client: AIClient, requested_exit_code: int) -> void:
	if is_instance_valid(client) and client.core_runtime != null and client.core_runtime.desktop_runtime != null:
		client.core_runtime.desktop_runtime.stop()
	var perf: Dictionary = _report.get("performance", {})
	perf["timeout_count"] = _timeout_count
	perf["warm_median_ms"] = _median(_warm_latencies)
	perf["throughput_equivalent_tps"] = _median(_positive_values(_warm_throughputs))
	perf["suite_wall_ms"] = float(Time.get_ticks_msec() - _suite_started_ms)
	_report["performance"] = perf
	var failures: Array = []
	for row in _report.scenarios:
		if row is Dictionary and bool(row.get("required", true)) and not bool(row.get("passed", false)):
			failures.append(str(row.get("id", "unknown")))
	_report["quality"] = {
		"passed": failures.is_empty(),
		"required_scenarios": _report.scenarios.size(),
		"failed_scenarios": failures
	}
	_report["status"] = "completed" if requested_exit_code != 124 else "scenario_timeout"
	_report["finished_at"] = Time.get_datetime_string_from_system(true)
	_write_report()
	var code := requested_exit_code
	if code == 0 and not failures.is_empty():
		code = 2
	print("AURORAFOX_CORE_BENCHMARK_DONE quality=%s scenarios=%d failures=%d" % [str(failures.is_empty()), _report.scenarios.size(), failures.size()])
	await process_frame
	quit(code)

func _probe_external_network() -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 3.0
	root.add_child(req)
	var err := req.request("http://1.1.1.1/", PackedStringArray(["User-Agent: AuroraFox-Core-Benchmark/1"]), HTTPClient.METHOD_GET)
	if err != OK:
		req.queue_free()
		return {"reachable": false, "error": error_string(err), "http": 0}
	var result: Array = await req.request_completed
	req.queue_free()
	var code := int(result[1])
	return {
		"reachable": code > 0,
		"http": code,
		"result_code": int(result[0]),
		"error": "" if code > 0 else "external network probe blocked or unavailable"
	}

func _clean_benchmark_state() -> bool:
	var paths := [
		"user://memory.json",
		"user://knowledge.json",
		"user://memory_vectors.json",
		"user://aurora_core_settings.json",
		"user://knowledge/knowledge.jsonl",
		"user://knowledge/structured.jsonl"
	]
	var ok := true
	for path in paths:
		if FileAccess.file_exists(path):
			var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if err != OK:
				ok = false
	for path in paths:
		if FileAccess.file_exists(path):
			ok = false
	return ok

func _benchmark_probe(args: Dictionary) -> Dictionary:
	_probe_calls += 1
	_probe_last_value = str(args.get("value", ""))
	return {"ok": true, "local_only": true, "read_only": true, "value": _probe_last_value}

func _compact_runtime_info(info: Dictionary) -> Dictionary:
	return {
		"runtime": info.get("runtime", ""),
		"self_primary": info.get("self_primary", false),
		"external_ai_required": info.get("external_ai_required", true),
		"normal_chat_external_fallback": info.get("normal_chat_external_fallback", true),
		"operational_without_ollama": info.get("operational_without_ollama", false),
		"ollama_fallback_enabled": info.get("ollama_fallback_enabled", false),
		"ollama_failures": info.get("ollama_failures", 0),
		"last_runtime": info.get("last_runtime", ""),
		"bundled_core": info.get("bundled_core", false),
		"model_installed": info.get("model_installed", false)
	}

func _is_local_runtime(result: Dictionary) -> bool:
	var runtime := str(result.get("runtime", ""))
	return runtime in LOCAL_RUNTIMES and not result.has("fallback_from")

func _final_text(text: String) -> String:
	var cleaned := text.strip_edges()
	var regex := RegEx.new()
	if regex.compile("(?s)<think>.*?</think>") == OK:
		cleaned = regex.sub(cleaned, "", true).strip_edges()
	if cleaned.begins_with("```") and cleaned.ends_with("```"):
		cleaned = cleaned.trim_prefix("```").trim_suffix("```").strip_edges()
	return cleaned

func _normalized(text: String) -> String:
	var value := _final_text(text).strip_edges().to_lower()
	while value.ends_with(".") or value.ends_with("!") or value.ends_with("?"):
		value = value.left(value.length() - 1).strip_edges()
	return value

func _contains_cyrillic(text: String) -> bool:
	for i in range(text.length()):
		var code := text.unicode_at(i)
		if code >= 0x0400 and code <= 0x052f:
			return true
	return false

func _file_size(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size

func _positive_values(values: Array[float]) -> Array[float]:
	var out: Array[float] = []
	for value in values:
		if value > 0.0: out.append(value)
	return out

func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[middle])
	return (float(sorted[middle - 1]) + float(sorted[middle])) / 2.0

func _write_report() -> void:
	if _report_path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write Core benchmark report: " + _report_path)
		return
	file.store_string(JSON.stringify(_report, "  "))
	file.close()
