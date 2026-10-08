from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_windowed_voice_backend_does_not_require_console_tty() -> None:
    server = _text("voice/python/aurora_voice_server.py")
    builder = _text("voice/build_backend.ps1")
    assert "'--windowed'" in builder
    assert "log_config=None" in server
    assert "access_log=False" in server
    assert "use_colors=False" in server


def test_foreground_chat_does_not_repeat_long_core_startup() -> None:
    main = _text("scripts/main.gd")
    runtime = _text("scripts/desktop_local_runtime.gd")
    agent = _text("scripts/agent_core.gd")
    assert 'call_deferred("_recover_core_background")' in main
    assert "answer = await agent.run_task(task)" in main
    assert main.count("answer = await agent.run_task(task)") == 1
    assert "JOINED_WARMUP_ATTEMPTS := 120" in runtime
    assert "for _attempt in range(JOINED_WARMUP_ATTEMPTS)" in runtime
    assert "DEFAULT_CHAT_TIMEOUT_SECONDS := 90.0" in runtime
    assert "DEFAULT_CONTEXT_SIZE := 4096" in runtime
    assert "DEFAULT_PARALLEL_SLOTS := 1" in runtime
    assert '"--parallel", str(DEFAULT_PARALLEL_SLOTS)' in runtime
    assert "[AURORA_DIRECT_CHAT]" in runtime
    assert "if _is_direct_conversation(task):" in agent
    assert "return await _run_direct_conversation" in agent
    direct = agent.split("func _run_direct_conversation", 1)[1].split("func _is_direct_conversation", 1)[0]
    assert direct.count("await ai.chat(messages)") == 1
    assert "cognition.make_plan" not in direct
    assert "verify_answer" not in direct
    assert 'memory.retrieve(task, OwnerResourcePolicy.count(memory.memory.size() + memory.knowledge.size(), "chat_retrieval_items")' in direct
    assert '"chat_retrieval_items": 2' in _text("scripts/owner_resource_policy.gd")
    assert 'OwnerResourcePolicy.count(source.size(), "direct_history_items")' in direct
    assert 'OwnerResourcePolicy.clip(str(item.get("content", "")).strip_edges(), "direct_history_chars")' in direct


def test_retry_does_not_kill_an_active_or_healthy_local_core() -> None:
    runtime = _text("scripts/desktop_local_runtime.gd")
    core = _text("scripts/aurora_core_runtime.gd")

    # Defensive runtime guard: ordinary recovery cannot kill a process while
    # the bundled model is still loading. Explicit app teardown still can.
    assert "func stop(force := false) -> void:" in runtime
    stop_body = runtime.split("func stop(force := false) -> void:", 1)[1].split("func runtime_info", 1)[0]
    assert "if starting and not force:" in stop_body
    assert "return" in stop_body.split("if starting and not force:", 1)[1].split("OS.kill", 1)[0]
    assert "OS.kill(server_pid)" in stop_body
    assert "stop(true)" in runtime.split("func _exit_tree() -> void:", 1)[1].split("func is_available", 1)[0]

    # The higher-level user retry is deliberately non-destructive. The next
    # ensure_server() call owns the health check and restarts only if required.
    retry_body = core.split("func retry_local_now() -> void:", 1)[1].split("func _model_circuit_open", 1)[0]
    assert "_model_failures.clear()" in retry_body
    assert '_last_local_error = ""' in retry_body
    assert "desktop_runtime.stop()" not in retry_body
    assert "ensure_server()" in retry_body


def test_greeting_fast_path_and_status_labels_are_explicit() -> None:
    main = _text("scripts/main.gd")
    assert "func _fast_local_reply" in main
    assert '"привет"' in main
    assert "Привет! Я AuroraFox. Чем могу помочь?" in main
    assert "зарегистрировано инструментов: %d" in main
    assert "локальных записей памяти: %d" in main
    assert "Текстовый интерфейс готов • Core запускается в фоне" in main
    assert '"Готово • %d инструментов • память %d"' not in main


def test_named_tools_and_english_commands_keep_the_agent_path() -> None:
    agent = _text("scripts/agent_core.gd")
    assert "for tool_name in tools.tools.keys():" in agent
    assert "q.contains(str(tool_name).to_lower())" in agent
    assert '"use ", "run ", "open "' in agent
