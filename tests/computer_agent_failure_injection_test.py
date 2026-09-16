from __future__ import annotations

import importlib.util
import os
import sys
import time
from pathlib import Path

from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
SERVICE_PATH = ROOT / "computer" / "computer_service.py"
TOKEN = "failure-injection-token-1234567890"


def _load_service(tmp_path: Path):
    os.environ["AURORAFOX_COMPUTER_TOKEN"] = TOKEN
    os.environ["AURORAFOX_SANDBOX_ROOT"] = str(tmp_path / "sandbox")
    name = f"aurora_computer_failure_test_{time.time_ns()}"
    spec = importlib.util.spec_from_file_location(name, SERVICE_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class _NoResultQueue:
    def get(self, timeout=0.5):
        del timeout
        raise RuntimeError("worker exited without a response")


class _MalformedQueue:
    def get(self, timeout=0.5):
        del timeout
        return "not-a-dictionary"


class _ExitedProcess:
    def start(self):
        return None

    def join(self, timeout=None):
        del timeout
        return None

    def is_alive(self):
        return False


class _FakeContext:
    def __init__(self, queue):
        self.queue = queue

    def Queue(self, maxsize=1):
        del maxsize
        return self.queue

    def Process(self, **kwargs):
        del kwargs
        return _ExitedProcess()


def _headers(allowed: bool = True) -> dict[str, str]:
    headers = {"X-AuroraFox-Computer-Token": TOKEN}
    if allowed:
        headers["X-AuroraFox-Autonomy-Allowed"] = "1"
    return headers


def test_worker_crash_or_empty_response_fails_closed_for_unsafe_action(tmp_path: Path, monkeypatch):
    service = _load_service(tmp_path)
    monkeypatch.setattr(service, "IS_WINDOWS", True)
    monkeypatch.setattr(service.mp, "get_context", lambda _method: _FakeContext(_NoResultQueue()))
    result = service._run_worker("action", {"type": "click", "x": 1, "y": 1}, timeout=0.1)
    assert result["ok"] is False
    assert result["error"] == "malformed_worker_response"
    assert result["retryable"] is False


def test_malformed_worker_payload_is_rejected_not_treated_as_success(tmp_path: Path, monkeypatch):
    service = _load_service(tmp_path)
    monkeypatch.setattr(service, "IS_WINDOWS", True)
    monkeypatch.setattr(service.mp, "get_context", lambda _method: _FakeContext(_MalformedQueue()))
    result = service._run_worker("action", {"type": "click", "x": 1, "y": 1}, timeout=0.1)
    assert result["ok"] is False
    assert result["error"] == "malformed_worker_response"
    assert result["retryable"] is False


def test_screenshot_worker_failure_is_graceful_and_retryable(tmp_path: Path, monkeypatch):
    service = _load_service(tmp_path)
    monkeypatch.setattr(service, "IS_WINDOWS", True)
    monkeypatch.setattr(service.mp, "get_context", lambda _method: _FakeContext(_NoResultQueue()))
    result = service._run_worker("screen", {}, timeout=0.1)
    assert result["ok"] is False
    assert result["error"] == "malformed_worker_response"
    assert result["retryable"] is True


def test_permission_denied_blocks_screen_and_action_before_worker(tmp_path: Path, monkeypatch):
    service = _load_service(tmp_path)
    monkeypatch.setattr(service, "IS_WINDOWS", True)
    called = {"worker": False}

    def should_not_run(*_args, **_kwargs):
        called["worker"] = True
        raise AssertionError("desktop primitive ran without explicit permission")

    monkeypatch.setattr(service, "_run_worker", should_not_run)
    client = TestClient(service.app)
    screen = client.get("/screen", headers=_headers(allowed=False))
    action = client.post(
        "/action",
        headers=_headers(allowed=False),
        json={"type": "click", "x": 10, "y": 10, "action_id": "denied-action"},
    )
    assert screen.status_code == 423
    assert action.status_code == 423
    assert called["worker"] is False


def test_unsupported_platform_capability_does_not_break_health(tmp_path: Path, monkeypatch):
    service = _load_service(tmp_path)
    monkeypatch.setattr(service, "IS_WINDOWS", False)
    client = TestClient(service.app)
    health = client.get("/health").json()
    caps = client.get("/capabilities", headers=_headers(allowed=False)).json()
    screen = client.get("/screen", headers=_headers()).json()
    assert health["ok"] is True
    assert health["computer_supported"] is False
    assert caps["ok"] is True
    assert caps["computer_supported"] is False
    assert screen["ok"] is False
    assert screen["error"] == "unsupported_platform"


def test_actual_runner_capability_matches_host_platform(tmp_path: Path):
    service = _load_service(tmp_path)
    expected_windows = os.name == "nt"
    client = TestClient(service.app)
    health = client.get("/health").json()
    caps = client.get("/capabilities", headers=_headers(allowed=False)).json()

    assert service.IS_WINDOWS is expected_windows
    assert health["computer_supported"] is expected_windows
    assert caps["computer_supported"] is expected_windows
    assert caps["screen"] is expected_windows
    assert caps["windows"] is expected_windows
    assert caps["mouse"] is expected_windows
    assert caps["keyboard"] is expected_windows
    assert health["planning_owner"] == "aurorafox_core"
    assert health["external_ai_required"] is False
    assert health["network_required"] is False
