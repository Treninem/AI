extends SceneTree

const DEFAULT_REPORT := "user://code-specialist-smoke.json"
const SAMPLE_CODE := "def add_numbers(a, b):\n    return a + b\n"

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
	# CodeSpecialist.new() child. Exercise that exact startup ownership path
	# instead of constructing an independent specialist that could miss the
	# original Work Mode setup regression.
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

	# Exercise all three public CodeSpecialist inference operations. Each call is
	# deliberately small/bounded, uses the same production AIClient, and is
	# followed by a runtime snapshot so an accidental compatibility escape cannot
	# be hidden by a later successful local call.
	var analyze_started := Time.get_ticks_usec()
	var analyze := await specialist.analyze_request(
		"Create a tiny Python function add_numbers(a, b) that returns their sum. Give a practical implementation and validation plan.",
		[{"path": "sample.py"}]
	)
	var analyze_ms := float(Time.get_ticks_usec() - analyze_started) / 1000.0
	var runtime_after_analyze := client.runtime_info()
	var analyze_plan_value = analyze.get("implementation_plan", [])
	var analyze_plan: Array = analyze_plan_value if analyze_plan_value is Array else []
	var analyze_summary := str(analyze.get("summary", "")).strip_edges()
	var analyze_ok := (
		bool(analyze.get("ok", false))
		and not analyze_summary.is_empty()
		and not analyze_plan.is_empty()
		and _runtime_is_local(runtime_after_analyze)
	)

	var review_started := Time.get_ticks_usec()
	var review := await specialist.review_code(
		"Review a tiny Python addition helper for correctness and propose concrete validation.",
		SAMPLE_CODE,
		"python"
	)
	var review_ms := float(Time.get_ticks_usec() - review_started) / 1000.0
	var runtime_after_review := client.runtime_info()
	var review_tests_value = review.get("tests", [])
	var review_tests: Array = review_tests_value if review_tests_value is Array else []
	var review_verdict := str(review.get("verdict", "")).strip_edges()
	var review_ok := (
		bool(review.get("ok", false))
		and not review_verdict.is_empty()
		and not review_tests.is_empty()
		and _runtime_is_local(runtime_after_review)
	)

	var explain_started := Time.get_ticks_usec()
	var explain := await specialist.explain_code(SAMPLE_CODE, "python")
	var explain_ms := float(Time.get_ticks_usec() - explain_started) / 1000.0
	var runtime_after_explain := client.runtime_info()
	var data_flow_value = explain.get("data_flow", [])
	var data_flow: Array = data_flow_value if data_flow_value is Array else []
	var explain_purpose := str(explain.get("purpose", "")).strip_edges()
	var explain_ok := (
		bool(explain.get("ok", false))
		and not explain_purpose.is_empty()
		and not data_flow.is_empty()
		and _runtime_is_local(runtime_after_explain)
	)

	var elapsed_ms := analyze_ms + review_ms + explain_ms
	var passed := (
		guard_expected
		and network_blocked
		and team_setup_ok
		and analyze_ok
		and review_ok
		and explain_ok
		and client.ollama_fallback_enabled()
		and _runtime_is_local(runtime_after_explain)
	)

	var report := {
		"schema_version": 2,
		"suite": "aurorafox_specialist_team_code_specialist_offline_v2",
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
			"self_primary": runtime_after_explain.get("self_primary", false),
			"external_ai_required": runtime_after_explain.get("external_ai_required", true),
			"compatibility_enabled": client.ollama_fallback_enabled(),
			"ollama_failures": runtime_after_explain.get("ollama_failures", -1),
			"last_runtime": runtime_after_explain.get("last_runtime", ""),
			"after_analyze": _runtime_evidence(runtime_after_analyze),
			"after_review": _runtime_evidence(runtime_after_review),
			"after_explain": _runtime_evidence(runtime_after_explain)
		},
		"specialist_team": {
			"team_instantiated": true,
			"team_setup_ok": team_setup_ok,
			"coder_parent_is_team": specialist != null and specialist.get_parent() == team,
			"coder_uses_same_ai_client": specialist != null and specialist.general_ai == client,
			"bounded_operations": ["analyze_request", "review_code", "explain_code"]
		},
		"operations": {
			"analyze_request": {
				"passed": analyze_ok,
				"elapsed_ms": analyze_ms,
				"result_ok": analyze.get("ok", false),
				"summary_present": not analyze_summary.is_empty(),
				"implementation_plan_steps": analyze_plan.size(),
				"languages": analyze.get("languages", []),
				"project_type": str(analyze.get("project_type", "")),
				"error": str(analyze.get("error", "")).substr(0, 500)
			},
			"review_code": {
				"passed": review_ok,
				"elapsed_ms": review_ms,
				"result_ok": review.get("ok", false),
				"verdict_present": not review_verdict.is_empty(),
				"validation_tests": review_tests.size(),
				"issues_count": (review.get("issues", []) as Array).size() if review.get("issues", []) is Array else -1,
				"error": str(review.get("error", "")).substr(0, 500)
			},
			"explain_code": {
				"passed": explain_ok,
				"elapsed_ms": explain_ms,
				"result_ok": explain.get("ok", false),
				"purpose_present": not explain_purpose.is_empty(),
				"data_flow_steps": data_flow.size(),
				"complexity": str(explain.get("complexity", "")),
				"error": str(explain.get("error", "")).substr(0, 500)
			}
		}
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
	var err := req.request("http://1.1.1.1/", PackedStringArray(["User-Agent: AuroraFox-CodeSpecialist-Smoke/2"]), HTTPClient.METHOD_GET)
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
