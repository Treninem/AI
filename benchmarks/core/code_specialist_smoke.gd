extends SceneTree

const DEFAULT_REPORT := "user://code-specialist-smoke.json"

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

	var started := Time.get_ticks_usec()
	var result := await specialist.analyze_request(
		"Create a tiny Python function add_numbers(a, b) that returns their sum. Give a practical implementation and validation plan.",
		[{"path": "sample.py"}]
	)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var runtime_after := client.runtime_info()
	var plan_value = result.get("implementation_plan", [])
	var plan: Array = plan_value if plan_value is Array else []
	var summary := str(result.get("summary", "")).strip_edges()
	var passed := (
		guard_expected
		and network_blocked
		and team_setup_ok
		and bool(result.get("ok", false))
		and not summary.is_empty()
		and not plan.is_empty()
		and client.ollama_fallback_enabled()
		and str(runtime_after.get("last_runtime", "")) == "aurora_core_desktop"
		and int(runtime_after.get("ollama_failures", -1)) == 0
		and bool(runtime_after.get("self_primary", false))
		and not bool(runtime_after.get("external_ai_required", true))
	)

	var report := {
		"schema_version": 1,
		"suite": "aurorafox_specialist_team_code_specialist_offline_v1",
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
			"last_runtime": runtime_after.get("last_runtime", ""),
			"self_primary": runtime_after.get("self_primary", false),
			"external_ai_required": runtime_after.get("external_ai_required", true),
			"compatibility_enabled": client.ollama_fallback_enabled(),
			"ollama_failures": runtime_after.get("ollama_failures", -1)
		},
		"specialist_team": {
			"team_instantiated": true,
			"team_setup_ok": team_setup_ok,
			"coder_parent_is_team": specialist != null and specialist.get_parent() == team,
			"coder_uses_same_ai_client": specialist != null and specialist.general_ai == client,
			"bounded_operation": "analyze_request"
		},
		"specialist": {
			"result_ok": result.get("ok", false),
			"summary_present": not summary.is_empty(),
			"implementation_plan_steps": plan.size(),
			"languages": result.get("languages", []),
			"project_type": str(result.get("project_type", "")),
			"error": str(result.get("error", "")).substr(0, 500)
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

func _probe_external_network() -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 3.0
	root.add_child(req)
	var err := req.request("http://1.1.1.1/", PackedStringArray(["User-Agent: AuroraFox-CodeSpecialist-Smoke/1"]), HTTPClient.METHOD_GET)
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
