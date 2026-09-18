extends SceneTree

const DEFAULT_REPORT := "user://code-specialist-smoke.json"
const SAMPLE_CODE := "def add_numbers(a, b):\n    return a + b\n"
const BUGGY_CODE := "def add_numbers(a, b):\n    return a - b\n"
const VERBOSE_CODE := "def add_numbers(a, b):\n    result = a + b\n    return result\n"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var report_path := OS.get_environment("AURORAFOX_CODE_SPECIALIST_REPORT").strip_edges()
	if report_path.is_empty():
		report_path = ProjectSettings.globalize_path(DEFAULT_REPORT)

	var guard_expected := OS.get_environment("AURORAFOX_CODE_SPECIALIST_NETWORK_GUARD") == "1"
	var network_probe := await _probe_external_network()
	var network_blocked := not bool(network_probe.get("reachable", true))

	var client := AIClient.new()
	root.add_child(client)
	await process_frame
	client.configure_ollama_compatibility("http://127.0.0.1:9", "benchmark-must-not-run")
	client.set_ollama_fallback(true)

	# Work/AgentCore owns a SpecialistTeam, and SpecialistTeam owns the
	# CodeSpecialist.new() child. Exercise that exact startup ownership path.
	var team := SpecialistTeam.new()
	root.add_child(team)
	team.setup(client)
	var specialist := team.coder
	var team_setup_ok := (
		team.ai == client
		and specialist != null
		and specialist.get_parent() == team
		and specialist.general_ai == client
	)

	var timings: Dictionary = {}
	var runtimes: Dictionary = {}
	var operation_reports: Dictionary = {}

	var started := Time.get_ticks_usec()
	var analyze := await specialist.analyze_request(
		"Create a tiny Python function add_numbers(a, b) that returns their sum. Give a practical implementation and validation plan.",
		[{"path": "sample.py", "content": "# Python module\n"}]
	)
	timings["analyze_request"] = float(Time.get_ticks_usec() - started) / 1000.0
	runtimes["analyze_request"] = client.runtime_info()
	var analyze_plan_value = analyze.get("implementation_plan", [])
	var analyze_plan: Array = analyze_plan_value if analyze_plan_value is Array else []
	var analyze_summary := str(analyze.get("summary", "")).strip_edges()
	var analyze_ok := bool(analyze.get("ok", false)) and not analyze_summary.is_empty() and not analyze_plan.is_empty() and _runtime_is_local(runtimes["analyze_request"])
	operation_reports["analyze_request"] = {
		"passed": analyze_ok,
		"elapsed_ms": timings["analyze_request"],
		"summary_present": not analyze_summary.is_empty(),
		"implementation_plan_steps": analyze_plan.size(),
		"error": str(analyze.get("error", "")).substr(0, 500)
	}

	started = Time.get_ticks_usec()
	var generated := await specialist.generate_code(
		"Implement add_numbers(a, b) in sample.py. It must return a + b and use no imports.",
		[{"path":"sample.py", "language":"python", "content":"# implement here\n"}]
	)
	timings["generate_code"] = float(Time.get_ticks_usec() - started) / 1000.0
	runtimes["generate_code"] = client.runtime_info()
	var generated_files_value = generated.get("files", [])
	var generated_files: Array = generated_files_value if generated_files_value is Array else []
	var generated_text := JSON.stringify(generated_files)
	var generated_lower := generated_text.to_lower()
	var generate_ok := (
		bool(generated.get("ok", false))
		and not generated_files.is_empty()
		and generated_lower.contains("add_numbers")
		and generated_lower.contains("return")
		and generated_text.contains("a + b")
		and _runtime_is_local(runtimes["generate_code"])
	)
	operation_reports["generate_code"] = {
		"passed": generate_ok,
		"elapsed_ms": timings["generate_code"],
		"files": generated_files.size(),
		"contains_expected_function": generated_lower.contains("add_numbers") and generated_text.contains("a + b"),
		"error": str(generated.get("error", "")).substr(0, 500)
	}

	started = Time.get_ticks_usec()
	var debug := await specialist.debug_code(
		"add_numbers(2, 3) incorrectly returns -1 instead of 5. Find the defect and provide corrected code.",
		BUGGY_CODE,
		"python"
	)
	timings["debug_code"] = float(Time.get_ticks_usec() - started) / 1000.0
	runtimes["debug_code"] = client.runtime_info()
	var corrected_code := str(debug.get("corrected_code", ""))
	var root_cause := str(debug.get("root_cause", "")).strip_edges()
	var debug_ok := (
		bool(debug.get("ok", false))
		and not root_cause.is_empty()
		and corrected_code.contains("add_numbers")
		and corrected_code.contains("a + b")
		and _runtime_is_local(runtimes["debug_code"])
	)
	operation_reports["debug_code"] = {
		"passed": debug_ok,
		"elapsed_ms": timings["debug_code"],
		"root_cause_present": not root_cause.is_empty(),
		"corrected_sum": corrected_code.contains("a + b"),
		"error": str(debug.get("error", "")).substr(0, 500)
	}

	started = Time.get_ticks_usec()
	var review := await specialist.review_code(
		"Review a tiny Python addition helper for correctness and propose concrete validation.",
		SAMPLE_CODE,
		"python"
	)
	timings["review_code"] = float(Time.get_ticks_usec() - started) / 1000.0
	runtimes["review_code"] = client.runtime_info()
	var review_tests_value = review.get("tests", [])
	var review_tests: Array = review_tests_value if review_tests_value is Array else []
	var review_verdict := str(review.get("verdict", "")).strip_edges()
	var review_ok := bool(review.get("ok", false)) and not review_verdict.is_empty() and not review_tests.is_empty() and _runtime_is_local(runtimes["review_code"])
	operation_reports["review_code"] = {
		"passed": review_ok,
		"elapsed_ms": timings["review_code"],
		"verdict_present": not review_verdict.is_empty(),
		"validation_tests": review_tests.size(),
		"issues_count": (review.get("issues", []) as Array).size() if review.get("issues", []) is Array else -1,
		"error": str(review.get("error", "")).substr(0, 500)
	}

	started = Time.get_ticks_usec()
	var explain := await specialist.explain_code(SAMPLE_CODE, "python")
	timings["explain_code"] = float(Time.get_ticks_usec() - started) / 1000.0
	runtimes["explain_code"] = client.runtime_info()
	var data_flow_value = explain.get("data_flow", [])
	var data_flow: Array = data_flow_value if data_flow_value is Array else []
	var explain_purpose := str(explain.get("purpose", "")).strip_edges()
	var explain_ok := bool(explain.get("ok", false)) and not explain_purpose.is_empty() and not data_flow.is_empty() and _runtime_is_local(runtimes["explain_code"])
	operation_reports["explain_code"] = {
		"passed": explain_ok,
		"elapsed_ms": timings["explain_code"],
		"purpose_present": not explain_purpose.is_empty(),
		"data_flow_steps": data_flow.size(),
		"complexity": str(explain.get("complexity", "")),
		"error": str(explain.get("error", "")).substr(0, 500)
	}

	started = Time.get_ticks_usec()
	var refactor := await specialist.refactor_code(
		"Simplify this helper while preserving its public signature and addition behavior.",
		VERBOSE_CODE,
		"python"
	)
	timings["refactor_code"] = float(Time.get_ticks_usec() - started) / 1000.0
	runtimes["refactor_code"] = client.runtime_info()
	var refactored_code := str(refactor.get("refactored_code", ""))
	var refactor_changes_value = refactor.get("changes", [])
	var refactor_changes: Array = refactor_changes_value if refactor_changes_value is Array else []
	var refactor_ok := (
		bool(refactor.get("ok", false))
		and refactored_code.contains("add_numbers")
		and refactored_code.contains("a + b")
		and not refactor_changes.is_empty()
		and _runtime_is_local(runtimes["refactor_code"])
	)
	operation_reports["refactor_code"] = {
		"passed": refactor_ok,
		"elapsed_ms": timings["refactor_code"],
		"changes": refactor_changes.size(),
		"preserves_sum": refactored_code.contains("a + b"),
		"returned_ok": bool(refactor.get("ok", false)),
		"contains_expected_function": refactored_code.contains("add_numbers"),
		"refactored_code_excerpt": refactored_code.substr(0, 4000),
		"error": str(refactor.get("error", "")).substr(0, 500)
	}

	started = Time.get_ticks_usec()
	var tests := await specialist.generate_tests(
		"Generate a minimal regression test that proves add_numbers(2, 3) returns 5 and include one edge case.",
		SAMPLE_CODE,
		"python"
	)
	timings["generate_tests"] = float(Time.get_ticks_usec() - started) / 1000.0
	runtimes["generate_tests"] = client.runtime_info()
	var test_code := str(tests.get("test_code", ""))
	var cases_value = tests.get("cases", [])
	var cases: Array = cases_value if cases_value is Array else []
	var tests_ok := (
		bool(tests.get("ok", false))
		and not test_code.is_empty()
		and test_code.to_lower().contains("add_numbers")
		and test_code.contains("5")
		and cases.size() >= 2
		and _runtime_is_local(runtimes["generate_tests"])
	)
	operation_reports["generate_tests"] = {
		"passed": tests_ok,
		"elapsed_ms": timings["generate_tests"],
		"cases": cases.size(),
		"contains_expected_assertion_inputs": test_code.to_lower().contains("add_numbers") and test_code.contains("5"),
		"returned_ok": bool(tests.get("ok", false)),
		"test_code_excerpt": test_code.substr(0, 4000),
		"rejected_response_excerpt": str(tests.get("raw", "")).substr(0, 4000),
		"error": str(tests.get("error", "")).substr(0, 500)
	}

	started = Time.get_ticks_usec()
	var multi := await specialist.reason_across_files(
		"Explain how app.py depends on util.py and identify which file should change if add_numbers needs input validation. Give a validation plan.",
		[
			{"path":"util.py", "language":"python", "content":SAMPLE_CODE},
			{"path":"app.py", "language":"python", "content":"from util import add_numbers\n\ndef total():\n    return add_numbers(2, 3)\n"}
		]
	)
	timings["reason_across_files"] = float(Time.get_ticks_usec() - started) / 1000.0
	runtimes["reason_across_files"] = client.runtime_info()
	var multi_summary := str(multi.get("summary", "")).strip_edges()
	var dependencies_value = multi.get("dependencies", [])
	var dependencies: Array = dependencies_value if dependencies_value is Array else []
	var validation_value = multi.get("validation", [])
	var validation: Array = validation_value if validation_value is Array else []
	var multi_text := JSON.stringify(multi).to_lower()
	var multi_ok := (
		bool(multi.get("ok", false))
		and not multi_summary.is_empty()
		and not dependencies.is_empty()
		and not validation.is_empty()
		and multi_text.contains("util.py")
		and multi_text.contains("app.py")
		and _runtime_is_local(runtimes["reason_across_files"])
	)
	operation_reports["reason_across_files"] = {
		"passed": multi_ok,
		"elapsed_ms": timings["reason_across_files"],
		"dependencies": dependencies.size(),
		"validation_steps": validation.size(),
		"mentions_both_files": multi_text.contains("util.py") and multi_text.contains("app.py"),
		"error": str(multi.get("error", "")).substr(0, 500)
	}

	var operation_names := [
		"analyze_request", "generate_code", "debug_code", "review_code", "explain_code",
		"refactor_code", "generate_tests", "reason_across_files"
	]
	var elapsed_ms := 0.0
	var operations_ok := true
	var runtime_evidence: Dictionary = {}
	for operation in operation_names:
		elapsed_ms += float(timings.get(operation, 0.0))
		operations_ok = operations_ok and bool((operation_reports.get(operation, {}) as Dictionary).get("passed", false))
		runtime_evidence[operation] = _runtime_evidence(runtimes.get(operation, {}))

	var runtime_after: Dictionary = runtimes.get("reason_across_files", {})
	var passed := (
		guard_expected
		and network_blocked
		and team_setup_ok
		and operations_ok
		and client.ollama_fallback_enabled()
		and str(runtime_after.get("last_runtime", "")) == "aurora_core_desktop"
		and int(runtime_after.get("ollama_failures", -1)) == 0
		and bool(runtime_after.get("self_primary", false))
		and not bool(runtime_after.get("external_ai_required", true))
	)

	var report := {
		"schema_version": 3,
		"suite": "aurorafox_specialist_team_code_specialist_offline_v3",
		"status": "completed",
		"passed": passed,
		"elapsed_ms": elapsed_ms,
		"network": {
			"guard_expected": guard_expected,
			"external_probe_blocked": network_blocked,
			"probe_http": int(network_probe.get("http", 0)),
			"probe_error": str(network_probe.get("error", "")).substr(0, 300)
		},
		"core": {
			"self_primary": runtime_after.get("self_primary", false),
			"external_ai_required": runtime_after.get("external_ai_required", true),
			"compatibility_enabled": client.ollama_fallback_enabled(),
			"ollama_failures": runtime_after.get("ollama_failures", -1),
			"last_runtime": runtime_after.get("last_runtime", ""),
			"per_operation_runtime": runtime_evidence
		},
		"specialist_team": {
			"team_instantiated": true,
			"team_setup_ok": team_setup_ok,
			"coder_parent_is_team": specialist != null and specialist.get_parent() == team,
			"coder_uses_same_ai_client": specialist != null and specialist.general_ai == client,
			"bounded_operations": operation_names
		},
		"operations": operation_reports
	}
	_write_report(report_path, report)
	print("AURORAFOX_SPECIALIST_TEAM_CODE_SPECIALIST_SMOKE " + JSON.stringify(report))

	if client.core_runtime != null and client.core_runtime.desktop_runtime != null:
		client.core_runtime.desktop_runtime.stop()
	team.queue_free()
	client.queue_free()
	await process_frame
	quit(0 if passed else 9)

func _runtime_is_local(info: Dictionary) -> bool:
	return (
		str(info.get("last_runtime", "")) == "aurora_core_desktop"
		and int(info.get("ollama_failures", -1)) == 0
		and bool(info.get("self_primary", false))
		and not bool(info.get("external_ai_required", true))
	)

func _runtime_evidence(info: Dictionary) -> Dictionary:
	return {
		"last_runtime": info.get("last_runtime", ""),
		"ollama_failures": info.get("ollama_failures", -1),
		"self_primary": info.get("self_primary", false),
		"external_ai_required": info.get("external_ai_required", true)
	}

func _probe_external_network() -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 3.0
	root.add_child(req)
	var err := req.request("http://1.1.1.1/", PackedStringArray(["User-Agent: AuroraFox-CodeSpecialist-Smoke/3"]), HTTPClient.METHOD_GET)
	if err != OK:
		req.queue_free()
		return {"reachable": false, "http": 0, "error": error_string(err)}
	var response: Array = await req.request_completed
	req.queue_free()
	var code := int(response[1])
	return {
		"reachable": code > 0,
		"http": code,
		"error": "" if code > 0 else "external network probe blocked or unavailable"
	}

func _write_report(path: String, report: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write CodeSpecialist smoke report: " + path)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
