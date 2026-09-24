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
    assert "memory.retrieve(task, 2" in direct
    assert "source.size() - 4" in direct
    assert ".substr(0, 800)" in direct


def test_greeting_fast_path_and_status_labels_are_explicit() -> None:
    main = _text("scripts/main.gd")
    assert "func _fast_local_reply" in main
    assert '"привет"' in main
    assert "Привет! Я AuroraFox. Чем могу помочь?" in main
    assert "зарегистрировано инструментов: %d" in main
    assert "локальных записей памяти: %d" in main
    assert "Текстовый интерфейс готов • Core запускается в фоне" in main
    assert '"Готово • %d инструментов • память %d"' not in main
