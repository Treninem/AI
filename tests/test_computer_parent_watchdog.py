"""Parent lifecycle checks must distinguish death from a failed probe."""

import importlib.util
import os
import sys
import time
from pathlib import Path

import pytest


SERVICE = Path(__file__).resolve().parents[1] / "computer" / "computer_service.py"


def _service(tmp_path, monkeypatch):
    monkeypatch.setenv("AURORAFOX_SANDBOX_ROOT", str(tmp_path / "sandbox"))
    name = f"computer_parent_watchdog_{time.time_ns()}"
    spec = importlib.util.spec_from_file_location(name, SERVICE)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class _WindowsProcessAPI:
    def __init__(self, handle, state=0x102, error=0):
        self.handle = handle
        self.state = state
        self.error = error
        self.opened = []
        self.closed = []

    def OpenProcess(self, access, inherit, pid):
        self.opened.append((access, inherit, pid))
        return self.handle

    def GetLastError(self):
        return self.error

    def WaitForSingleObject(self, handle, millis):
        assert millis == 0
        return self.state

    def CloseHandle(self, handle):
        self.closed.append(handle)


def test_windows_exact_handle_states_and_probe_failures(tmp_path, monkeypatch):
    service = _service(tmp_path, monkeypatch)
    for handle, state, error, expected in [
        (41, 0x102, 0, True),   # exact process is still running
        (42, 0, 0, False),      # exact process has exited
        (43, 0xFFFFFFFF, 0, None),  # wait failed
        (0, 0, 5, None),        # access denied is not confirmed death
        (0, 0, 87, False),      # invalid PID is confirmed absent
    ]:
        api = _WindowsProcessAPI(handle, state, error)
        assert service._parent_alive(123, windows_api=api, platform="nt") is expected
        assert api.opened == [(0x00100000, False, 123)]
        assert api.closed == ([handle] if handle else [])


def test_watchdog_does_not_stop_on_transient_probe_error(tmp_path, monkeypatch):
    service = _service(tmp_path, monkeypatch)
    service.PARENT_PID = 123
    observed = []
    states = iter([None, True, False])
    monkeypatch.setattr(service.time, "sleep", lambda _: None)
    monkeypatch.setattr(service, "_parent_alive", lambda _: next(states))
    monkeypatch.setattr(service, "_cancel_all_processes", lambda: observed.append("cancel"))

    class Stopped(Exception):
        pass

    def exit_once(code):
        observed.append(("exit", code))
        raise Stopped

    monkeypatch.setattr(service.os, "_exit", exit_once)
    with pytest.raises(Stopped):
        service._parent_watchdog()
    assert observed == ["cancel", ("exit", 0)]


def test_posix_permission_is_alive_and_missing_pid_is_dead(tmp_path, monkeypatch):
    service = _service(tmp_path, monkeypatch)
    def denied(pid, signal):
        raise PermissionError(pid)
    monkeypatch.setattr(service.os, "kill", denied)
    assert service._parent_alive(123, platform="posix") is True
    def missing(pid, signal):
        raise ProcessLookupError(pid)
    monkeypatch.setattr(service.os, "kill", missing)
    assert service._parent_alive(123, platform="posix") is False


@pytest.mark.skipif(sys.platform != "win32", reason="native Windows process handle")
def test_real_windows_parent_handle_sees_current_process(tmp_path, monkeypatch):
    service = _service(tmp_path, monkeypatch)
    assert service._parent_alive(os.getpid()) is True
