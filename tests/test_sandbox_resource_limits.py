"""Real authenticated service calls and filesystem owner-limit regressions."""
import importlib.util
import sys
import time
import os
import pytest
from pathlib import Path
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
TOKEN = "sandbox-test-channel-token-1234567890"
HEADERS = {"X-AuroraFox-Computer-Token": TOKEN, "X-AuroraFox-Autonomy-Allowed": "1"}


def service(tmp_path, monkeypatch):
    monkeypatch.setenv("AURORAFOX_COMPUTER_TOKEN", TOKEN)
    monkeypatch.setenv("AURORAFOX_SANDBOX_ROOT", str(tmp_path / "sandbox"))
    name = "sandbox_limits_" + str(time.time_ns())
    spec = importlib.util.spec_from_file_location(name, ROOT / "computer/computer_service.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module, TestClient(module.app)


def test_actual_tree_more_than_default_cap_and_zero_unlimited(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    work = module.SANDBOX_ROOT / "fixture/work"
    work.mkdir(parents=True)
    for i in range(2001):
        (work / f"file_{i}").write_text("x")
    base = "/sandbox/workspace/tree?workspace=fixture"
    limited = client.get(base, headers=HEADERS).json()
    assert len(limited["items"]) == 2000 and limited["truncated"] and limited["partial"]
    exact = client.get(base + "&max_items=2001", headers=HEADERS).json()
    assert len(exact["items"]) == 2001 and not exact["truncated"]
    unlimited = client.get(base + "&max_items=0", headers=HEADERS).json()
    assert len(unlimited["items"]) == 2001 and not unlimited["partial"]
    assert client.get(base + "&max_items=-1", headers=HEADERS).status_code == 400
    assert client.get(base).status_code == 401


def test_real_read_larger_than_old_five_mb_accepts_raised_or_zero(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    path = module.SANDBOX_ROOT / "large.txt"
    data = "x" * 5000001
    path.write_text(data)
    base = "/sandbox/read?path=large.txt"
    assert client.get(base, headers=HEADERS).status_code == 413
    for suffix in ["&max_bytes=5000001", "&max_bytes=0"]:
        response = client.get(base + suffix, headers=HEADERS)
        assert response.status_code == 200 and response.json()["text"] == data
    assert client.get(base + "&max_bytes=-1", headers=HEADERS).status_code == 400
    assert client.get(base).status_code == 401


def test_tree_excludes_outside_links_and_flags_incomplete_coverage(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    work = module.SANDBOX_ROOT / "fixture/work"
    work.mkdir(parents=True)
    outside = tmp_path / "private"
    outside.mkdir()
    (outside / "secret").write_text("private")
    try:
        (work / "linked").symlink_to(outside, target_is_directory=True)
    except OSError:
        if os.name == "nt":
            pytest.skip("Windows fixture requires symlink creation privilege")
        raise
    response = client.get("/sandbox/workspace/tree?workspace=fixture&max_items=0", headers=HEADERS).json()
    assert response["items"] == [] and response["unsafe_paths_skipped"] == 1 and response["partial"]
    assert client.get("/sandbox/read?path=fixture/work/linked/secret&max_bytes=0", headers=HEADERS).status_code == 400


def test_read_budget_is_checked_before_opening_oversized_source(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    (module.SANDBOX_ROOT / "large").write_bytes(b"oversized")
    def denied_open(*_args, **_kwargs):
        raise AssertionError("oversized file must be denied before allocation/open")
    monkeypatch.setattr(module.os, "open", denied_open)
    response = client.get("/sandbox/read?path=large&max_bytes=2", headers=HEADERS)
    assert response.status_code == 413


def test_real_utf8_write_owner_exact_raised_zero_and_rejected_overflow(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    content = "я" * 1000001
    actual_bytes = len(content.encode("utf-8"))
    payload = {"path": "large.txt", "content": content}
    assert client.post("/sandbox/write", headers=HEADERS, json=payload).status_code == 413
    assert not (module.SANDBOX_ROOT / "large.txt").exists()
    for budget in [actual_bytes, 0]:
        response = client.post("/sandbox/write", headers=HEADERS, json={**payload, "max_bytes": budget})
        assert response.status_code == 200 and response.json()["ok"]
        assert (module.SANDBOX_ROOT / "large.txt").read_bytes() == content.encode("utf-8")
    assert client.post("/sandbox/write", headers=HEADERS, json={**payload, "max_bytes": actual_bytes - 1}).status_code == 413
    assert (module.SANDBOX_ROOT / "large.txt").read_bytes() == content.encode("utf-8")
    assert client.post("/sandbox/write", headers=HEADERS, json={**payload, "max_bytes": -1}).status_code == 422
    assert client.post("/sandbox/write", json={**payload, "max_bytes": 0}).status_code == 401


def test_real_snapshot_entries_can_exceed_default_or_disable_owner_cap(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    work = module.SANDBOX_ROOT / "fixture/work"
    work.mkdir(parents=True)
    for index in range(5001):
        (work / str(index)).write_bytes(b"x")
    payload = {"workspace": "fixture", "label": "limit"}
    assert client.post("/sandbox/workspace/snapshot", headers=HEADERS, json=payload).status_code == 413
    for budget in [5001, 0]:
        response = client.post("/sandbox/workspace/snapshot", headers=HEADERS, json={**payload, "max_entries": budget})
        assert response.status_code == 200 and response.json()["entries"] == 5001
    assert client.post("/sandbox/workspace/snapshot", headers=HEADERS, json={**payload, "max_entries": -1}).status_code == 422


def test_snapshot_byte_failure_and_rollback_preserve_current_work(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    work = module.SANDBOX_ROOT / "fixture/work"
    work.mkdir(parents=True)
    (work / "content").write_bytes(b"original")
    base = {"workspace": "fixture", "max_entries": 0}
    denied = client.post("/sandbox/workspace/snapshot", headers=HEADERS, json={**base, "max_bytes": 7})
    assert denied.status_code == 413 and (work / "content").read_bytes() == b"original"
    for budget in [8, 0]:
        snap = client.post("/sandbox/workspace/snapshot", headers=HEADERS, json={**base, "max_bytes": budget}).json()
        assert snap["ok"] and snap["bytes"] == 8
        (work / "content").write_bytes(b"modified")
        payload = {**base, "snapshot": snap["snapshot"], "max_bytes": 7}
        assert client.post("/sandbox/workspace/rollback", headers=HEADERS, json=payload).status_code == 413
        assert (work / "content").read_bytes() == b"modified"
        accepted = client.post("/sandbox/workspace/rollback", headers=HEADERS, json={**payload, "max_bytes": budget})
        assert accepted.status_code == 200 and (work / "content").read_bytes() == b"original"
    assert client.post("/sandbox/workspace/rollback", json={**base, "snapshot": snap["snapshot"], "max_bytes": 0}).status_code == 401


def test_snapshot_reparse_entries_rejected_with_unlimited_owner_budgets(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    work = module.SANDBOX_ROOT / "fixture/work"
    work.mkdir(parents=True)
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "private").write_bytes(b"private")
    try:
        (work / "link").symlink_to(outside, target_is_directory=True)
    except OSError:
        if os.name == "nt": pytest.skip("Windows fixture requires symlink creation privilege")
        raise
    response = client.post("/sandbox/workspace/snapshot", headers=HEADERS, json={"workspace": "fixture", "max_entries": 0, "max_bytes": 0})
    assert response.status_code == 400 and (outside / "private").read_bytes() == b"private"


@pytest.mark.skipif(os.name != "nt", reason="NTFS junction requires Windows")
def test_real_windows_junction_snapshot_does_not_read_outside_tree(tmp_path, monkeypatch):
    import subprocess
    module, client = service(tmp_path, monkeypatch)
    work = module.SANDBOX_ROOT / "fixture/work"
    work.mkdir(parents=True)
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "private").write_bytes(b"private")
    junction = work / "junction"
    result = subprocess.run(["cmd", "/c", "mklink", "/J", str(junction), str(outside)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    try:
        response = client.post("/sandbox/workspace/snapshot", headers=HEADERS, json={"workspace": "fixture", "max_entries": 0, "max_bytes": 0})
        assert response.status_code == 400
        assert (outside / "private").read_bytes() == b"private"
    finally:
        os.rmdir(junction)


def _wait_for_file(path, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists(): return
        time.sleep(0.01)
    raise AssertionError(f"Fixture did not start: {path.name}")


def test_actual_owned_process_and_descendant_cancel_after_master_stop(tmp_path, monkeypatch):
    import concurrent.futures
    import json
    import subprocess
    module, client = service(tmp_path, monkeypatch)
    module.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    root = module.SANDBOX_ROOT
    (root / "owned.py").write_text(
        "import os,sys,time,json,subprocess\nfrom pathlib import Path\n"
        "child=subprocess.Popen([sys.executable,'-c',\"import time;time.sleep(60)\"])\n"
        "Path('owned-pids').write_text(json.dumps([os.getpid(),child.pid]))\n"
        "while True:\n Path('heartbeat').write_text(str(time.time_ns()))\n time.sleep(0.02)\n"
    )
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(client.post, "/sandbox/exec", headers=HEADERS, json={"command": [sys.executable, "owned.py"], "timeout": 60, "execution_id": "owned-master-stop"})
        try:
            _wait_for_file(root / "owned-pids")
            pids = json.loads((root / "owned-pids").read_text())
            # Cancellation remains authorized with master-stop header absent/0.
            stopped = client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN, "X-AuroraFox-Autonomy-Allowed": "0"}, json={"execution_id": "owned-master-stop"})
            assert stopped.status_code == 200 and stopped.json()["termination_confirmed"]
            result = future.result(timeout=5).json()
            assert not result["ok"] and result["error"] == "cancelled" and not result["retryable"]
            _wait_for_file(root / "heartbeat")
            heartbeat = (root / "heartbeat").read_bytes()
            time.sleep(0.1)
            assert (root / "heartbeat").read_bytes() == heartbeat
            for pid in pids:
                if os.name == "nt":
                    listing = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"], capture_output=True, text=True, timeout=3)
                    assert f'"{pid}"' not in listing.stdout
                else:
                    proc = Path(f"/proc/{pid}/stat")
                    assert not proc.exists() or proc.read_text().split(")", 1)[1].split()[0] == "Z"
        finally:
            module._cancel_execution("owned-master-stop")


def test_cancel_before_start_and_reused_execution_never_spawn(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    module.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    payload = {"execution_id": "cancel-before-start"}
    assert client.post("/sandbox/cancel", json=payload).status_code == 401
    assert client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN}, json=payload).json()["termination_confirmed"]
    command = {**payload, "command": [sys.executable, "-c", "from pathlib import Path;Path('must-not-exist').write_text('bad')"]}
    response = client.post("/sandbox/exec", headers=HEADERS, json=command).json()
    assert not response["ok"] and response["error"] == "cancelled"
    assert not (module.SANDBOX_ROOT / "must-not-exist").exists()
    good = {"execution_id": "execute-once", "command": [sys.executable, "-c", "print('once')"]}
    assert client.post("/sandbox/exec", headers=HEADERS, json=good).json()["ok"]
    repeated = client.post("/sandbox/exec", headers=HEADERS, json=good).json()
    assert not repeated["ok"] and repeated["error"] == "execution_id_reused"


def test_actual_process_shutdown_and_timeout_terminate_owned_execution(tmp_path, monkeypatch):
    import concurrent.futures
    module, _client = service(tmp_path, monkeypatch)
    root = module.SANDBOX_ROOT
    code = "from pathlib import Path;import time;Path('started').write_text('yes');time.sleep(60)"
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(module._run_process, [sys.executable, "-c", code], root, 60, allow_network=False, execution_id="shutdown-owned")
        try:
            _wait_for_file(root / "started")
            module._cancel_all_processes()
            assert future.result(timeout=5)["error"] == "cancelled"
            late = module._run_process([sys.executable, "-c", "from pathlib import Path;Path('late').write_text('bad')"], root, 1, allow_network=False, execution_id="late-after-stop")
            assert late["error"] == "service_stopping" and not (root / "late").exists()
        finally:
            module._cancel_all_processes()
    module, _client = service(tmp_path / "timeout-case", monkeypatch)
    root = module.SANDBOX_ROOT
    timed = module._run_process([sys.executable, "-c", "import time;time.sleep(60)"], root, 0.1, allow_network=False, execution_id="timeout-owned")
    assert timed["error"] == "timeout" and timed["termination_confirmed"] and not timed["retryable"]


def test_actual_daemon_container_cancel_removes_owned_container(tmp_path, monkeypatch):
    if os.getenv("AURORAFOX_REQUIRE_CONTAINER_CANCEL") != "1":
        pytest.skip("Actual Docker fixture is mandatory in Linux CI; not enabled locally")
    import concurrent.futures
    import subprocess
    import shutil
    assert shutil.which("docker"), "Docker fixture was required but runtime is absent"
    module, client = service(tmp_path, monkeypatch)
    root = module.SANDBOX_ROOT
    (root / "owned.py").write_text("from pathlib import Path\nimport time\nPath('container-started').write_text('yes')\nwhile True:\n Path('container-heartbeat').write_text(str(time.time_ns()))\n time.sleep(0.02)\n")
    payload = {"execution_id": "actual-container-cancel", "command": ["python", "owned.py"], "timeout": 60}
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(client.post, "/sandbox/container_exec", headers=HEADERS, json=payload)
        try:
            _wait_for_file(root / "container-started", timeout=20)
            with module._execution_lock:
                engine, name = module._execution_records[payload["execution_id"]]["container"]
            running = subprocess.run([engine, "inspect", "--format", "{{.State.Running}}", name], capture_output=True, text=True, timeout=5)
            assert running.returncode == 0 and running.stdout.strip() == "true"
            stopped = client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN}, json={"execution_id": payload["execution_id"]}).json()
            assert stopped["termination_confirmed"] and not stopped["uncertain_external_state"]
            result = future.result(timeout=5).json()
            assert result["error"] == "cancelled" and not result["retryable"]
            remaining = subprocess.run([engine, "ps", "--all", "--filter", f"name=^{name}$", "--format", "{{.Names}}"], capture_output=True, text=True, timeout=5)
            assert remaining.returncode == 0 and remaining.stdout.strip() == ""
        finally:
            module._cancel_execution(payload["execution_id"])


def _spawn_owned_gui_worker(_kind, payload, _queue):
    Path(payload["marker"]).write_text("started")
    time.sleep(60)


def test_actual_gui_worker_is_owned_and_stopped_before_sidecar_restart(tmp_path, monkeypatch):
    import concurrent.futures
    module, client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    monkeypatch.setattr(module, "_worker_entry", _spawn_owned_gui_worker)
    marker = module.SANDBOX_ROOT / "gui-started"
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(module._run_worker, "action", {"marker": str(marker)}, 60)
        try:
            _wait_for_file(marker)
            stopped = client.post("/sandbox/cancel_all", headers={"X-AuroraFox-Computer-Token": TOKEN}).json()
            assert stopped["termination_confirmed"]
            result = future.result(timeout=5)
            assert not result["ok"] and not result["retryable"]
            assert module._gui_workers == set()
            blocked = client.post("/action", headers=HEADERS, json={"type": "done"})
            assert blocked.status_code == 503
        finally:
            module._cancel_all_processes()


def test_failed_stop_retains_actual_process_ownership_for_retry(tmp_path, monkeypatch):
    import concurrent.futures
    module, client = service(tmp_path, monkeypatch)
    root = module.SANDBOX_ROOT
    terminate = module._terminate_process_tree
    code = "from pathlib import Path;import time;Path('started').write_text('yes');time.sleep(60)"
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(module._run_process, [sys.executable, "-c", code], root, 60, allow_network=False, execution_id="failed-stop")
        try:
            _wait_for_file(root / "started")
            monkeypatch.setattr(module, "_terminate_process_tree", lambda _process: False)
            unconfirmed = client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN}, json={"execution_id": "failed-stop"}).json()
            assert not unconfirmed["ok"] and unconfirmed["uncertain_external_state"] and not unconfirmed["retryable"]
            with module._execution_lock:
                assert module._execution_records["failed-stop"]["process"].poll() is None
            monkeypatch.setattr(module, "_terminate_process_tree", terminate)
            confirmed = client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN}, json={"execution_id": "failed-stop"}).json()
            assert confirmed["termination_confirmed"]
            assert future.result(timeout=5)["error"] == "cancelled"
        finally:
            monkeypatch.setattr(module, "_terminate_process_tree", terminate)
            module._cancel_execution("failed-stop")
