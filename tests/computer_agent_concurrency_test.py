from __future__ import annotations

import importlib.util
import os
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE_PATH = ROOT / "computer" / "computer_service.py"
TOKEN = "concurrency-token-1234567890"


def _load_service(tmp_path: Path):
    os.environ["AURORAFOX_COMPUTER_TOKEN"] = TOKEN
    os.environ["AURORAFOX_SANDBOX_ROOT"] = str(tmp_path / "sandbox")
    name = f"aurora_computer_concurrency_test_{time.time_ns()}"
    spec = importlib.util.spec_from_file_location(name, SERVICE_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def test_distinct_desktop_actions_are_serialized_without_poisoning_retry(tmp_path: Path, monkeypatch):
    service = _load_service(tmp_path)
    service.IS_WINDOWS = True
    monkeypatch.setattr(service, "_desktop_bounds", lambda: {"left": 0, "top": 0, "width": 100, "height": 100, "right": 100, "bottom": 100})
    started = threading.Event()
    release = threading.Event()
    calls: list[str] = []

    def blocking_worker(kind, payload=None, timeout=0):
        del timeout
        if kind != "action":
            return {"ok": True, "sha256": "screen"}
        action_id = str((payload or {}).get("action_id", ""))
        calls.append(action_id)
        if action_id == "first-action":
            started.set()
            assert release.wait(2.0)
        return {"ok": True, "done": False}

    monkeypatch.setattr(service, "_run_worker", blocking_worker)
    first = service.Action(type="click", x=10, y=10, action_id="first-action")
    second = service.Action(type="click", x=20, y=20, action_id="second-action")

    with ThreadPoolExecutor(max_workers=2) as pool:
        first_future = pool.submit(service._execute_action, first)
        assert started.wait(1.0)
        busy = service._execute_action(second)
        assert busy["ok"] is False
        assert busy["error"] == "computer_busy"
        assert busy["executed"] is False
        assert busy["retryable"] is False
        assert calls == ["first-action"]
        release.set()
        first_result = first_future.result(timeout=2.0)

    assert first_result["ok"] is True
    second_result = service._execute_action(second)
    assert second_result["ok"] is True
    assert calls == ["first-action", "second-action"]


def test_uncertain_unsafe_result_is_cached_and_never_replayed_automatically(tmp_path: Path, monkeypatch):
    service = _load_service(tmp_path)
    service.IS_WINDOWS = True
    monkeypatch.setattr(service, "_desktop_bounds", lambda: {"left": 0, "top": 0, "width": 100, "height": 100, "right": 100, "bottom": 100})
    calls: list[str] = []

    def crashed_worker(kind, payload=None, timeout=0):
        del timeout
        if kind != "action":
            return {"ok": True, "sha256": "screen"}
        calls.append(str((payload or {}).get("action_id", "")))
        return {"ok": False, "error": "malformed_worker_response", "message": "worker exited without result", "retryable": False}

    monkeypatch.setattr(service, "_run_worker", crashed_worker)
    request = service.Action(type="click", x=10, y=10, action_id="uncertain-action")
    first = service._execute_action(request)
    assert first["ok"] is False
    assert first["retryable"] is False
    assert first["retry_safety"] == "unsafe"
    assert first["uncertain_external_state"] is True
    second = service._execute_action(request)
    assert second["ok"] is False
    assert second["deduplicated"] is True
    assert second["uncertain_external_state"] is True
    assert calls == ["uncertain-action"]
