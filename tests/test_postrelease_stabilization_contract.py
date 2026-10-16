"""Regression guards for the V1.5.0.x installed chat, Core/Voice and Android stall fixes.

These inspect real product code paths; actual Windows process inventory, Android
frame traces and Android inference remain mandatory device-level acceptance.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def between(text: str, start: str, end: str) -> str:
    return text.split(start, 1)[1].split(end, 1)[0]


def test_windows_core_owns_startup_before_await_and_joins_waiters() -> None:
    source = read("scripts/desktop_local_runtime.gd")
    owner = between(source, "func ensure_server(", "func _wait_owned_server_ready(")
    assert owner.index("if starting:") < owner.index("starting = true")
    assert owner.index("starting = true") < owner.index("await _wait_owned_server_ready(")
    assert "_wait_for_existing_start(model_absolute_path)" in owner
    assert owner.count("OS.create_process(") == 1
    assert "return await _wait_owned_server_ready(server_pid, true)" in owner
    assert "stop()" not in owner
    stop = between(source, "func stop(", "func runtime_info(")
    assert "_kill_owned_server_only()" in stop
    assert "if starting and not force:" in stop
    assert "func _exit_tree()" in source and "stop(true)" in source


def test_voice_exit_terminates_only_its_owned_backend() -> None:
    source = read("voice/voice_bridge.gd")
    shutdown = between(source, "func _exit_tree()", "func _process(")
    assert "backend_pid > 0" in shutdown
    assert "OS.is_process_running(backend_pid)" in shutdown
    assert "OS.kill(backend_pid)" in shutdown
    assert "socket.close()" in shutdown
    executable = "\n".join(line for line in shutdown.splitlines() if not line.lstrip().startswith("#"))
    assert '/shutdown' not in executable


def test_chat_does_not_mask_all_core_errors_as_loading() -> None:
    source = read("scripts/main.gd")
    failure = between(source, 'if answer.begins_with("Ошибка модели:"):', "AuroraVoice.set_ai_working(false)")
    assert 'get("starting", false)' in failure
    assert '"core_startup_status" if loading else "core_error"' in failure
    assert "Не удалось получить ответ от локального Core" in failure


def test_android_first_run_copy_and_inference_are_nonblocking() -> None:
    bundled = read("scripts/bundled_core_model.gd")
    first_run = between(bundled, "static func runtime_candidate()", "static func windows_packaged_path()")
    assert "ensure_android_private_copy()" not in first_run
    assert "static func ensure_android_private_copy()" in bundled
    assert "FileAccess.get_sha256(temp).to_lower()" in bundled

    runtime = read("scripts/android_local_runtime.gd")
    assert "WorkerThreadPool.add_task(" in runtime
    assert "WorkerThreadPool.is_task_completed(" in runtime
    chat = between(runtime, "func chat_async(", "func synthesize_speech(")
    assert 'startChatLocalAsync' in chat
    assert 'pollChatLocalAsync' in chat
    assert 'await get_tree().create_timer' in chat

    routing = read("scripts/aurora_core_runtime.gd")
    assert "await android_runtime.ensure_bundled_model_ready()" in routing
    assert "await android_runtime.chat_async(" in routing
    assert "AuroraBundledCoreModel.bundled_available()" in routing


def test_android_native_generation_runs_off_main_thread_and_is_single_flight() -> None:
    src = read("android_plugin/plugin/src/main/java/com/aurorafox/runtime/GodotAndroidPlugin.kt")
    async_start = between(src, "fun startChatLocalAsync(", "fun pollChatLocalAsync(")
    assert "coreChatBusy.compareAndSet(false, true)" in async_start
    assert "coreChatExecutor.execute" in async_start
    assert "native.chat(" in async_start.split("coreChatExecutor.execute", 1)[1]
    assert "coreChatBusy.set(false)" in async_start
    async_poll = between(src, "fun pollChatLocalAsync(", "fun synthesizeSpeechLocal(")
    assert "status\" to \"running" in async_poll
    assert "status\" to \"completed" in async_poll
    assert "coreChatJobs.remove(jobId, job)" in async_poll
    assert "Thread(runnable, \"AuroraFoxCoreInference\")" in src


def test_normal_chat_uses_worker_for_large_local_knowledge() -> None:
    client = read("scripts/ai_client.gd")
    assert "class KnowledgeContextJob extends RefCounted" in client
    assert "KnowledgeStore.new().context_for(query)" in client
    normal = between(client, "func chat(messages: Array,", "func chat_with_compatibility(")
    assert "await _with_knowledge_async(messages)" in normal
    assert "_with_knowledge(messages)" not in normal
    worker = between(client, "func _with_knowledge_async(", "func _with_knowledge(")
    assert "WorkerThreadPool.add_task(" in worker
    assert "WorkerThreadPool.is_task_completed(task_id)" in worker
    assert "await get_tree().create_timer(" in worker
    assert "WorkerThreadPool.wait_for_task_completion(task_id)" in worker


def test_request_startup_does_not_poison_model_health() -> None:
    core = read("scripts/aurora_core_runtime.gd")
    failed = between(core, "var model_failure := bool(result.get(", "func _chat_local_model(")
    assert "if not model_failure:" in failed
    assert "return result" in failed
    startup = read("scripts/desktop_local_runtime.gd")
    assert '"failure_scope": "startup", "model_failure": false' in startup
    assert "func _wait_for_existing_start(" in startup


def test_android_e2e_waits_for_async_provision_before_integrity_gate() -> None:
    suite = read("benchmarks/core/android_godot_benchmark.gd")
    snippet = between(suite, "var runtime_before := client.runtime_info()", 'var caps: Dictionary =')
    assert "await client.core_runtime.android_runtime.ensure_bundled_model_ready()" in snippet
    assert snippet.index("await client.core_runtime.android_runtime.ensure_bundled_model_ready()") < snippet.index("FileAccess.get_sha256(model_path)")
