from __future__ import annotations

import importlib.util
import os
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
SERVICE_PATH = ROOT / "computer" / "computer_service.py"
TOKEN = "test-local-channel-token-1234567890"


def _spawn_safe_hanging_worker(kind, payload, queue):
    del kind, payload, queue
    time.sleep(5)


def _spawn_safe_success_worker(kind, payload, queue):
    del kind, payload
    queue.put({"ok": True, "marker": "ready"})


def _load_service(tmp_path: Path):
    os.environ["AURORAFOX_COMPUTER_TOKEN"] = TOKEN
    os.environ["AURORAFOX_SANDBOX_ROOT"] = str(tmp_path / "sandbox")
    os.environ.pop("AURORAFOX_ALLOW_DEGRADED_LOCAL_SANDBOX", None)
    name = f"aurora_computer_service_test_{time.time_ns()}"
    spec = importlib.util.spec_from_file_location(name, SERVICE_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _headers(*, autonomous: bool = True, token: str = TOKEN) -> dict[str, str]:
    result = {"X-AuroraFox-Computer-Token": token}
    if autonomous:
        result["X-AuroraFox-Autonomy-Allowed"] = "1"
    return result


def test_service_source_has_no_external_ai_planner_dependency():
    text = SERVICE_PATH.read_text(encoding="utf-8").lower()
    assert "ollama" not in text
    assert "openai" not in text
    assert "gemini" not in text
    assert "claude" not in text
    assert "requests.post" not in text
    requirements = (ROOT / "computer" / "requirements.txt").read_text(encoding="utf-8").lower()
    assert "requests" not in requirements
    installer = (ROOT / "computer" / "install_computer.ps1").read_text(encoding="utf-8").lower()
    assert "ollama pull" not in installer


def test_health_and_capability_contract_are_local_first(tmp_path: Path):
    service = _load_service(tmp_path)
    client = TestClient(service.app)
    health = client.get("/health").json()
    assert health["ok"] is True
    assert health["planning_owner"] == "aurorafox_core"
    assert health["service_side_ai_planning"] is False
    assert health["external_ai_required"] is False
    assert health["network_required"] is False
    assert health["degraded_local_sandbox_enabled"] is False
    caps = client.get("/capabilities", headers=_headers(autonomous=False)).json()
    assert caps["ok"] is True
    assert caps["service_side_planning"] is False
    assert caps["local_core_planning_required"] is True
    assert caps["degraded_local_sandbox_enabled"] is False


def test_sensitive_endpoints_require_private_channel_and_master_permission(tmp_path: Path):
    service = _load_service(tmp_path)
    client = TestClient(service.app)
    assert client.get("/screen").status_code == 401
    assert client.get("/screen", headers=_headers(token="wrong-token")).status_code == 401
    assert client.get("/screen", headers=_headers(autonomous=False)).status_code == 423


def test_service_side_plan_and_run_are_disabled_without_external_ai(tmp_path: Path):
    service = _load_service(tmp_path)
    client = TestClient(service.app)
    for path in ("/plan", "/run"):
        response = client.post(path, headers=_headers(), json={"goal": "open settings", "max_steps": 3, "auto_execute": True})
        assert response.status_code == 200
        body = response.json()
        assert body["ok"] is False
        assert body["error"] == "local_core_planning_required"
        assert body["retryable"] is False


def test_unsupported_platform_returns_graceful_contract(tmp_path: Path):
    service = _load_service(tmp_path)
    service.IS_WINDOWS = False
    client = TestClient(service.app)
    response = client.get("/screen", headers=_headers())
    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is False
    assert body["error"] == "unsupported_platform"
    assert body["retryable"] is False


def test_action_validation_idempotency_and_retry_safety(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    service = _load_service(tmp_path)
    service.IS_WINDOWS = True
    monkeypatch.setattr(service, "_desktop_bounds", lambda: {"left": -100, "top": 0, "width": 300, "height": 200, "right": 200, "bottom": 200})
    calls: list[tuple[str, dict]] = []

    def fake_worker(kind, payload=None, timeout=0):
        calls.append((kind, dict(payload or {})))
        return {"ok": True, "done": False}

    monkeypatch.setattr(service, "_run_worker", fake_worker)
    client = TestClient(service.app)
    payload = {"type": "click", "x": -50, "y": 20, "action_id": "task-1:action-1"}
    first = client.post("/action", headers=_headers(), json=payload).json()
    second = client.post("/action", headers=_headers(), json=payload).json()
    assert first["ok"] is True
    assert first["retryable"] is False
    assert first["retry_safety"] == "unsafe"
    assert second["deduplicated"] is True
    assert len([item for item in calls if item[0] == "action"]) == 1

    scroll_without_id = client.post("/action", headers=_headers(), json={"type": "scroll", "amount": 1})
    assert scroll_without_id.status_code == 400
    scroll = client.post("/action", headers=_headers(), json={"type": "scroll", "amount": 1, "action_id": "scroll-1"}).json()
    assert scroll["ok"] is True
    assert scroll["retryable"] is False
    assert scroll["retry_safety"] == "unsafe"

    out_of_bounds = client.post("/action", headers=_headers(), json={"type": "click", "x": 201, "y": 20, "action_id": "bounds"})
    assert out_of_bounds.status_code == 400
    malformed = client.post("/action", headers=_headers(), json={"type": "hotkey", "keys": [], "action_id": "keys"})
    assert malformed.status_code == 400


def test_unsafe_action_requires_idempotency_key(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    service = _load_service(tmp_path)
    service.IS_WINDOWS = True
    monkeypatch.setattr(service, "_desktop_bounds", lambda: {"left": 0, "top": 0, "width": 100, "height": 100, "right": 100, "bottom": 100})
    client = TestClient(service.app)
    response = client.post("/action", headers=_headers(), json={"type": "click", "x": 10, "y": 10})
    assert response.status_code == 400
    assert "action_id" in response.json()["detail"]


def test_concurrent_duplicate_action_id_executes_only_once(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    service = _load_service(tmp_path)
    service.IS_WINDOWS = True
    monkeypatch.setattr(service, "_desktop_bounds", lambda: {"left": 0, "top": 0, "width": 100, "height": 100, "right": 100, "bottom": 100})
    started = threading.Event()
    release = threading.Event()
    calls: list[str] = []

    def blocking_worker(kind, payload=None, timeout=0):
        del timeout
        if kind == "action":
            calls.append(str((payload or {}).get("action_id", "")))
            started.set()
            assert release.wait(2.0)
            return {"ok": True, "done": False}
        return {"ok": True, "sha256": "screen"}

    monkeypatch.setattr(service, "_run_worker", blocking_worker)
    request = service.Action(type="click", x=10, y=10, action_id="single-flight")
    with ThreadPoolExecutor(max_workers=2) as pool:
        first_future = pool.submit(service._execute_action, request)
        assert started.wait(1.0)
        duplicate = service._execute_action(request)
        assert duplicate["ok"] is False
        assert duplicate["error"] == "action_in_progress"
        assert duplicate["uncertain_external_state"] is True
        assert duplicate["retry_safety"] == "unsafe"
        release.set()
        first = first_future.result(timeout=2.0)
    assert first["ok"] is True
    assert calls == ["single-flight"]
    cached = service._execute_action(request)
    assert cached["ok"] is True
    assert cached["deduplicated"] is True
    assert calls == ["single-flight"]


def test_timeout_response_never_marks_unsafe_action_retryable(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    service = _load_service(tmp_path)
    service.IS_WINDOWS = True
    monkeypatch.setattr(service, "_desktop_bounds", lambda: {"left": 0, "top": 0, "width": 100, "height": 100, "right": 100, "bottom": 100})
    monkeypatch.setattr(service, "_run_worker", lambda *args, **kwargs: {"ok": False, "error": "timeout", "message": "bounded timeout", "retryable": True})
    client = TestClient(service.app)
    body = client.post("/action", headers=_headers(), json={"type": "click", "x": 10, "y": 10, "action_id": "unsafe-timeout"}).json()
    assert body["ok"] is False
    assert body["error"] == "timeout"
    assert body["retryable"] is False
    assert body["retry_safety"] == "unsafe"
    assert body["uncertain_external_state"] is True


def test_sandbox_rejects_traversal_absolute_and_symlink_escape(tmp_path: Path):
    service = _load_service(tmp_path)
    root = service.SANDBOX_ROOT
    root.mkdir(parents=True, exist_ok=True)
    with pytest.raises(Exception):
        service._safe_sandbox_path("../escape.txt")
    with pytest.raises(Exception):
        service._safe_sandbox_path(str((tmp_path / "absolute.txt").resolve()))

    outside = tmp_path / "outside"
    outside.mkdir()
    link = root / "link"
    try:
        link.symlink_to(outside, target_is_directory=True)
    except (OSError, NotImplementedError):
        pytest.skip("symlinks unavailable on this runner")
    with pytest.raises(Exception):
        service._safe_sandbox_path("link/secret.txt")


def test_sandbox_write_is_bounded_atomic_and_channel_protected(tmp_path: Path):
    service = _load_service(tmp_path)
    client = TestClient(service.app)
    response = client.post("/sandbox/write", headers=_headers(), json={"path": "w/result.txt", "content": "hello"})
    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert (service.SANDBOX_ROOT / "w" / "result.txt").read_text(encoding="utf-8") == "hello"
    leftovers = list((service.SANDBOX_ROOT / "w").glob("*.tmp")) + list((service.SANDBOX_ROOT / "w").glob(".*.tmp"))
    assert leftovers == []
    too_large = client.post("/sandbox/write", headers=_headers(), json={"path": "large.txt", "content": "x" * (service.MAX_WRITE_BYTES + 1)})
    assert too_large.status_code == 413


def test_degraded_local_process_sandbox_fails_closed_until_operator_opt_in(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    service = _load_service(tmp_path)
    client = TestClient(service.app)
    calls: list[list[str]] = []

    def fake_run_process(command, cwd, timeout, *, allow_network):
        del cwd, timeout, allow_network
        calls.append(list(command))
        return {"ok": True, "code": 0, "output": "ok", "mode": "local", "retryable": False}

    monkeypatch.setattr(service, "_run_process", fake_run_process)
    payload = {"command": ["python", "-c", "print('ok')"], "cwd": ".", "timeout": 5, "allow_network": False}
    blocked = client.post("/sandbox/exec", headers=_headers(), json=payload)
    assert blocked.status_code == 403
    assert "disabled by default" in blocked.json()["detail"]
    assert calls == []

    service.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    allowed = client.post("/sandbox/exec", headers=_headers(), json=payload)
    assert allowed.status_code == 200
    assert allowed.json()["ok"] is True
    assert allowed.json()["network_isolation_enforced"] is False
    assert calls == [["python", "-c", "print('ok')"]]


def test_command_allowlist_rejects_shell_escape_shapes(tmp_path: Path):
    service = _load_service(tmp_path)
    assert service._validate_command(["python", "script.py", "--flag"]) == ["python", "script.py", "--flag"]
    with pytest.raises(Exception):
        service._validate_command(["cmd.exe", "/c", "whoami"])
    with pytest.raises(Exception):
        service._validate_command(["python", "../outside.py"])
    with pytest.raises(Exception):
        service._validate_command(["python", str((tmp_path / "outside.py").resolve())])
    with pytest.raises(Exception):
        service._validate_command(["python", "bad\x00arg"])


def test_privacy_redaction_removes_common_secret_surfaces(tmp_path: Path):
    service = _load_service(tmp_path)
    text = service._redact("password=hunter2 token=abcdef123456 Bearer verysecrettoken123 cookie=sessionvalue")
    assert "hunter2" not in text
    assert "abcdef123456" not in text
    assert "verysecrettoken123" not in text
    assert "sessionvalue" not in text
    assert "[REDACTED]" in text


def test_worker_timeout_contract_terminates_hung_process(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    service = _load_service(tmp_path)
    service.IS_WINDOWS = True
    monkeypatch.setattr(service, "_worker_entry", _spawn_safe_hanging_worker)
    start = time.monotonic()
    result = service._run_worker("action", {"type": "wait"}, timeout=0.2)
    elapsed = time.monotonic() - start
    assert elapsed < 2.5
    assert result["ok"] is False
    assert result["error"] == "timeout"


def test_worker_result_queue_waits_bounded_time_for_feeder_flush(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    service = _load_service(tmp_path)
    service.IS_WINDOWS = True
    monkeypatch.setattr(service, "_worker_entry", _spawn_safe_success_worker)
    start = time.monotonic()
    result = service._run_worker("action", {"type": "done"}, timeout=1.0)
    elapsed = time.monotonic() - start
    assert elapsed < 2.5
    assert result == {"ok": True, "marker": "ready"}


def test_client_contract_has_bounded_timeouts_master_stop_and_android_graceful():
    text = (ROOT / "scripts" / "computer_client.gd").read_text(encoding="utf-8")
    assert "req.timeout = clampf(timeout_seconds" in text
    assert "240.0" not in text
    assert "master_stop" in text
    assert 'OS.get_name() != "Windows"' in text
    assert "local_core_planning_required" in text
    assert "X-AuroraFox-Computer-Token" in text
    assert "X-AuroraFox-Autonomy-Allowed" in text
