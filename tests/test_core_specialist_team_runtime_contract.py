from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SMOKE = ROOT / "benchmarks" / "core" / "code_specialist_smoke.gd"
CODE_SPECIALIST = ROOT / "scripts" / "code_specialist.gd"
AGENT_CORE = ROOT / "scripts" / "agent_core.gd"
DESKTOP_RUNTIME = ROOT / "scripts" / "desktop_local_runtime.gd"
ANDROID_RUNTIME = ROOT / "scripts" / "android_local_runtime.gd"
BUNDLED_CORE = ROOT / "scripts" / "bundled_core_model.gd"
CORE_RUNTIME = ROOT / "scripts" / "aurora_core_runtime.gd"
AI_CLIENT = ROOT / "scripts" / "ai_client.gd"
MAIN = ROOT / "scripts" / "main.gd"
SMOKE_RUNNER = ROOT / "benchmarks" / "core" / "run_windows_code_specialist_smoke.ps1"
WORKFLOW = ROOT / ".github" / "workflows" / "core-benchmarks.yml"

EXPECTED_OPERATIONS = (
    "analyze_request",
    "generate_code",
    "debug_code",
    "review_code",
    "explain_code",
    "refactor_code",
    "generate_tests",
    "reason_across_files",
)


def test_code_specialist_exposes_complete_local_coding_surface() -> None:
    code = CODE_SPECIALIST.read_text(encoding="utf-8")
    for operation in EXPECTED_OPERATIONS:
        assert f"func {operation}(" in code
    assert "return await general_ai.chat(messages, temperature)" in code
    assert "HTTPRequest" not in code
    assert "/api/chat" not in code
    assert "qwen3-coder" not in code.lower()
    assert "ollama" not in code.lower()


def test_code_specialist_repairs_incomplete_generated_test_suites() -> None:
    code = CODE_SPECIALIST.read_text(encoding="utf-8")
    assert "func _valid_test_output(" in code
    assert "func _repair_generated_tests_response(" in code
    assert "cases.size() >= 2" in code
    assert "if not _valid_test_output(parsed):" in code
    assert "Test Engineer repair returned incomplete tests" in code
    assert 'repaired["repaired_structure"] = true' in code


def test_specialist_team_runtime_smoke_uses_real_owned_code_specialist_path() -> None:
    smoke = SMOKE.read_text(encoding="utf-8")
    assert "SpecialistTeam.new()" in smoke
    assert "team.setup(client)" in smoke
    assert "specialist := team.coder" in smoke
    for operation in EXPECTED_OPERATIONS:
        assert f"specialist.{operation}(" in smoke
        assert f'"{operation}":' in smoke or f'"{operation}"' in smoke
    assert "team_setup_ok" in smoke
    assert "specialist.get_parent() == team" in smoke
    assert "specialist.general_ai == client" in smoke
    assert 'str(info.get("last_runtime", "")) == "aurora_core_desktop"' in smoke
    assert 'int(info.get("ollama_failures", -1)) == 0' in smoke
    assert '"per_operation_runtime": runtime_evidence' in smoke
    assert 'client.configure_ollama_compatibility("http://127.0.0.1:9", "benchmark-must-not-run")' in smoke
    assert "client.set_ollama_fallback(true)" in smoke
    assert "http://1.1.1.1/" in smoke


def test_specialist_team_runtime_smoke_is_fail_fast_before_full_benchmark() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    start = workflow.index("- name: Run real SpecialistTeam / CodeSpecialist through bundled Core offline")
    end = workflow.index("- name: Run real bundled Core benchmark offline")
    specialist_step = workflow[start:end]
    assert "id: code_specialist_smoke" in specialist_step
    assert "continue-on-error: true" not in specialist_step
    assert "run_windows_code_specialist_smoke.ps1" in specialist_step
    assert start < end


def test_agent_core_handles_no_tool_retrieval_and_repairs_args_before_execution() -> None:
    agent = AGENT_CORE.read_text(encoding="utf-8")
    assert "if tool_catalog.is_empty():" in agent
    assert '"direct_no_tools": true' in agent
    assert "Не возвращай JSON tool-call" in agent
    assert "args = await _complete_tool_args(task, tool_name, args)" in agent
    assert "func _complete_tool_args(" in agent
    assert "func _explicit_task_arg(" in agent
    assert "Structural repair happens before any tool call" in agent
    completion_pos = agent.index("args = await _complete_tool_args(task, tool_name, args)")
    call_pos = agent.index("var tool_result = await tools.call_tool(tool_name, args)")
    assert completion_pos < call_pos


def test_core_requests_have_product_bounds_and_terse_mobile_desktop_limits() -> None:
    runtime = DESKTOP_RUNTIME.read_text(encoding="utf-8")
    android = ANDROID_RUNTIME.read_text(encoding="utf-8")
    runner = SMOKE_RUNNER.read_text(encoding="utf-8")
    assert "DEFAULT_CHAT_MAX_TOKENS := 2048" in runtime
    assert "TERSE_CHAT_MAX_TOKENS := 128" in runtime
    assert "DEFAULT_CONTEXT_SIZE := 4096" in runtime
    assert "DEFAULT_PARALLEL_SLOTS := 1" in runtime
    assert "DEFAULT_CHAT_TIMEOUT_SECONDS := 90.0" in runtime
    assert '"max_tokens": max_tokens' in runtime
    assert 'options.get("timeout_seconds", DEFAULT_CHAT_TIMEOUT_SECONDS)' in runtime
    assert 'clampi(int(options.get("max_tokens", default_max_tokens)), 64, 8192)' in runtime
    assert 'payload["reasoning_effort"] = "none"' in runtime
    assert "_is_strict_structured_request(messages)" in runtime
    assert 'prompt.contains("return strict json only")' in runtime
    assert '"model_failure": false' in runtime
    assert 'if not raw.strip_edges().is_empty()' in runtime
    assert '"--ctx-size", str(DEFAULT_CONTEXT_SIZE)' in runtime
    assert "DEFAULT_CHAT_MAX_TOKENS := 384" in android
    assert "TERSE_CHAT_MAX_TOKENS := 16" in android
    assert 'request_options["max_tokens"] = TERSE_CHAT_MAX_TOKENS if terse_request else DEFAULT_CHAT_MAX_TOKENS' in android
    assert "[int]$TimeoutSeconds = 900" in runner
    assert "AURORAFOX_CODE_SPECIALIST_TIMEOUT_DIAGNOSTICS" in runner


def test_request_scoped_core_failures_do_not_quarantine_a_valid_model() -> None:
    runtime = DESKTOP_RUNTIME.read_text(encoding="utf-8")
    core = (ROOT / "scripts" / "aurora_core_runtime.gd").read_text(encoding="utf-8")
    assert '"failure_scope": "request"' in runtime
    assert 'var model_failure := bool(result.get("model_failure", true))' in core
    assert "if model_failure:" in core
    assert "_record_model_failure(candidate, error)" in core
    assert core.index("if model_failure:") < core.index("_record_model_failure(candidate, error)")


def test_windows_prefers_packaged_core_and_normal_chat_recovers_without_setup() -> None:
    bundled = BUNDLED_CORE.read_text(encoding="utf-8")
    core = CORE_RUNTIME.read_text(encoding="utf-8")
    client = AI_CLIENT.read_text(encoding="utf-8")
    main = MAIN.read_text(encoding="utf-8")

    windows_block = bundled.split('if OS.get_name() == "Windows":', 1)[1].split('if _valid_gguf(ACTIVE_MODEL):', 1)[0]
    assert "_valid_bundled_file(packaged)" in windows_block
    assert "return packaged" in windows_block
    assert bundled.index("return packaged") < bundled.index("return ACTIVE_MODEL")
    assert "AuroraBundledCoreModel.windows_packaged_path()" in core
    assert "if packaged != model_path and _looks_like_gguf(packaged):" in core
    assert "func retry_local_now()" in core
    assert "_model_failures.clear()" in core
    assert "desktop_runtime.stop()" in core
    assert "func retry_core_now()" in client
    assert "core_runtime.retry_local_now()" in client
    assert 'if answer.begins_with("Ошибка модели:"):' in main
    assert "ai.retry_core_now()" in main
    assert main.count("await agent.run_task(task)") == 1
    assert "call_deferred(\"_recover_core_background\")" in main
    assert "устанавливать или настраивать ничего не нужно" in main
    assert main.index("ai.retry_core_now()") < main.index('chats.add_message("assistant", answer)')


def test_core_engine_resolution_uses_actions_token_without_weakening_verification() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    start = workflow.index("- name: Prepare verified bundled AuroraFox Core")
    end = workflow.index("- name: Save bundled Core weights cache")
    prepare_step = workflow[start:end]
    assert "AURORAFOX_GITHUB_TOKEN: ${{ github.token }}" in prepare_step
    assert "GH_TOKEN: ${{ github.token }}" in prepare_step
    assert "prepare_bundled_windows_core.ps1" in prepare_step
    assert "if ($LASTEXITCODE -ne 0)" in prepare_step


def test_performance_baseline_comes_only_from_successful_main_benchmark_runs() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "actions: read" in workflow
    assert "Resolve latest successful main benchmark baseline" in workflow
    assert "/actions/runs?branch=main&event=push&status=success&per_page=100" in workflow
    assert "$_.name -eq 'AuroraFox Core Benchmarks'" in workflow
    assert 'artifactName = "aurorafox-core-benchmark-$headSha"' in workflow
    assert "AURORAFOX_CORE_BASELINE_BOOTSTRAP" in workflow
    assert "steps.baseline.outputs.path" in workflow
    assert "--baseline" in workflow
