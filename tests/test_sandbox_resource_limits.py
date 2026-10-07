"""Real authenticated service calls and filesystem owner-limit regressions."""
import importlib.util
import json
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
    (root / "owned.py").write_text('import os,sys,time,json,subprocess\nfrom pathlib import Path\ndef metadata():\n    data = {"pid": os.getpid(), "proc_pid": os.getpid()}\n    if os.name != "nt":\n        raw = Path("/proc/self/stat").read_text()\n        data["proc_pid"] = int(raw.split()[0])\n        data["birth"] = raw.split(")", 1)[1].split()[19]\n    return data\nif len(sys.argv) > 1:\n    Path("child-heartbeat").write_text(str(time.time_ns()))\n    Path("child-info").write_text(json.dumps(metadata()))\n    while True:\n        Path("child-heartbeat").write_text(str(time.time_ns()))\n        time.sleep(0.02)\nchild = subprocess.Popen([sys.executable, "owned.py", "child"])\nwhile not Path("child-info").exists(): time.sleep(0.01)\nPath("heartbeat").write_text(str(time.time_ns()))\nPath("owned-pids").write_text(json.dumps([metadata(), json.loads(Path("child-info").read_text())]))\nwhile True:\n    Path("heartbeat").write_text(str(time.time_ns()))\n    time.sleep(0.02)\n')
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(client.post, "/sandbox/exec", headers=HEADERS, json={"command": [sys.executable, "owned.py"], "timeout": 0, "execution_id": "owned-master-stop"})
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
            child_heartbeat = (root / "child-heartbeat").read_bytes()
            time.sleep(0.1)
            assert (root / "heartbeat").read_bytes() == heartbeat
            assert (root / "child-heartbeat").read_bytes() == child_heartbeat
            for metadata in pids:
                pid = metadata["pid"]
                if os.name == "nt":
                    listing = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"], capture_output=True, text=True, timeout=3)
                    assert f'"{pid}"' not in listing.stdout
                else:
                    proc = Path(f"/proc/{metadata['proc_pid']}/stat")
                    if proc.exists():
                        fields = proc.read_text().split(")", 1)[1].split()
                        assert fields[19] != metadata["birth"] or fields[0] == "Z", f"Owned PID {pid} still live: state={fields[0]} pgrp={fields[2]}"
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
    monkeypatch.setenv("AURORAFOX_CONTAINER_ENGINE", "docker")
    module, client = service(tmp_path, monkeypatch)
    root = module.SANDBOX_ROOT
    (root / "owned.py").write_text("from pathlib import Path\nimport time\nPath('container-started').write_text('yes')\nwhile True:\n Path('container-heartbeat').write_text(str(time.time_ns()))\n time.sleep(0.02)\n")
    payload = {"execution_id": "actual-container-cancel", "command": ["python", "owned.py"], "timeout": 60}
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(client.post, "/sandbox/container_exec", headers=HEADERS, json=payload)
        try:
            deadline = time.monotonic() + 20
            while not (root / "container-started").exists():
                if future.done():
                    response = future.result()
                    pytest.fail(f"Docker fixture exited before readiness: HTTP {response.status_code}: {response.text}")
                if time.monotonic() >= deadline:
                    pytest.fail("Docker fixture did not produce its readiness marker within 20 seconds")
                time.sleep(0.01)
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


@pytest.mark.parametrize("iteration", range(5))
def test_actual_gui_worker_is_owned_and_stopped_before_sidecar_restart(tmp_path, monkeypatch, iteration):
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
            owner_job = module._execution_records["failed-stop"].get("job")
            if owner_job is not None:
                terminate_job = owner_job.terminate
                monkeypatch.setattr(owner_job, "terminate", lambda: False)
            else:
                monkeypatch.setattr(module, "_terminate_process_tree", lambda _process: False)
            unconfirmed = client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN}, json={"execution_id": "failed-stop"}).json()
            assert not unconfirmed["ok"] and unconfirmed["uncertain_external_state"] and not unconfirmed["retryable"]
            with module._execution_lock:
                assert module._execution_records["failed-stop"]["process"].poll() is None
            if owner_job is not None:
                monkeypatch.setattr(owner_job, "terminate", terminate_job)
            else:
                monkeypatch.setattr(module, "_terminate_process_tree", terminate)
            confirmed = client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN}, json={"execution_id": "failed-stop"}).json()
            assert confirmed["termination_confirmed"]
            assert future.result(timeout=5)["error"] == "cancelled"
        finally:
            monkeypatch.setattr(module, "_terminate_process_tree", terminate)
            module._cancel_execution("failed-stop")


@pytest.mark.parametrize("timeout", [0, 10001, 1000000000000000000])
def test_actual_process_accepts_owner_zero_raised_and_huge_deadline(tmp_path, monkeypatch, timeout):
    module, client = service(tmp_path, monkeypatch)
    module.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    response = client.post("/sandbox/exec", headers=HEADERS, json={"command": [sys.executable, "-c", "print('owner deadline verified')"], "timeout": timeout, "execution_id": "owner-deadline"})
    assert response.status_code == 200
    assert response.json()["ok"] and "owner deadline verified" in response.json()["output"]
    assert client.post("/sandbox/exec", headers=HEADERS, json={"command": [sys.executable], "timeout": -1}).status_code == 422


def test_actual_app_lifespan_shutdown_terminates_owned_process(tmp_path, monkeypatch):
    import concurrent.futures
    module, _client = service(tmp_path, monkeypatch)
    root = module.SANDBOX_ROOT
    code = "from pathlib import Path;import time;Path('lifespan-started').write_text('yes');time.sleep(60)"
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = None
        try:
            with TestClient(module.app):
                future = pool.submit(module._run_process, [sys.executable, "-c", code], root, 0, allow_network=False, execution_id="lifespan-owned")
                _wait_for_file(root / "lifespan-started")
            result = future.result(timeout=5)
            assert result["error"] == "cancelled" and module._execution_stopping
            assert module._execution_records["lifespan-owned"]["process"] is None
        finally:
            module._cancel_all_processes()


@pytest.mark.parametrize("budget", [120000, 120001, 0, 3])
def test_actual_owner_output_reports_partial_and_redacts_before_clip(tmp_path, monkeypatch, budget):
    module, client = service(tmp_path, monkeypatch)
    module.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    result = client.post("/sandbox/exec", headers=HEADERS, json={
        "command": [sys.executable, "-c", "import sys;sys.stdout.write('x'*120001);sys.stderr.write(' password=supersecret')"],
        "timeout": 5, "output_chars": budget,
    }).json()
    assert result["ok"] and result["code"] == 0
    expected = "x" * 120001 + " password=[REDACTED]"
    assert result["output"] == (expected[:budget] if budget else expected)
    assert result["output_chars_total"] == len(expected)
    assert result["partial"] == result["truncated"] == result["limit_reached"] == (budget > 0 and len(expected) > budget)
    assert "supersecret" not in result["output"]
    assert client.post("/sandbox/exec", headers=HEADERS, json={"command": [sys.executable], "output_chars": -1}).status_code == 422
    assert client.post("/sandbox/exec", json={"command": [sys.executable]}).status_code == 401


def _spawn_large_worker_response(_kind, _payload, queue):
    queue.put({"ok": True, "image": "x" * 1048576})


def test_actual_large_spawned_worker_response_drains_before_join(tmp_path, monkeypatch):
    module, _client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    monkeypatch.setattr(module, "_worker_entry", _spawn_large_worker_response)
    started = time.monotonic()
    result = module._run_worker("screen", {}, timeout=3)
    assert result.get("ok"), result
    assert len(result["image"]) == 1048576
    assert time.monotonic() - started < 5
    assert module._gui_workers == set()


@pytest.mark.parametrize("budget", [4097, 4098, 0, 4096])
def test_actual_combined_raw_capture_budget_and_unicode_bytes(tmp_path, monkeypatch, budget):
    module, client = service(tmp_path, monkeypatch)
    module.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    result = client.post("/sandbox/exec", headers=HEADERS, json={
        "command": [sys.executable, "-c", "import sys;sys.stdout.buffer.write(('Ж'*2048).encode());sys.stderr.buffer.write(b'x')"],
        "timeout": 5, "capture_bytes": budget, "output_chars": 0,
    }).json()
    if budget and budget < 4097:
        assert not result["ok"] and result["error"] == "output_budget" and result["output"] == ""
        assert result["termination_confirmed"] and not result["uncertain_external_state"]
        assert result["captured_bytes"] == budget
    else:
        assert result["ok"] and result["output"] == "Ж" * 2048 + "x"
        assert result["captured_bytes"] == 4097 and not result["output_decoding_replaced"]
    assert client.post("/sandbox/exec", headers=HEADERS, json={"command": [sys.executable], "capture_bytes": -1}).status_code == 422


def test_actual_infinite_output_producer_stops_at_owner_budget(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    module.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    started = time.monotonic()
    result = client.post("/sandbox/exec", headers=HEADERS, json={
        "execution_id": "infinite-output", "command": [sys.executable, "-c", "import os\nwhile True: os.write(1,b'password=supersecret '*1000);os.write(2,b'x'*1000)"],
        "timeout": 0, "capture_bytes": 128, "output_chars": 0,
    }).json()
    assert time.monotonic() - started < 5
    assert result["error"] == "output_budget" and result["captured_bytes"] <= 128
    assert result["output"] == "" and "supersecret" not in str(result)
    assert result["termination_confirmed"] and not result["uncertain_external_state"] and not result["retryable"]
    assert module._execution_records["infinite-output"]["process"] is None
    assert all(not thread.is_alive() for thread in module._execution_records["infinite-output"]["capture_threads"])


def test_actual_default_capture_ceiling_and_invalid_utf8_are_truthful(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    module.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    result = client.post("/sandbox/exec", headers=HEADERS, json={
        "command": [sys.executable, "-c", "import os;os.write(1,b'x'*(8388608+1))"], "timeout": 5,
    }).json()
    assert result["error"] == "output_budget" and result["capture_budget_bytes"] == 8388608
    decoded = client.post("/sandbox/exec", headers=HEADERS, json={
        "command": [sys.executable, "-c", "import os;os.write(1,bytes([255]))"], "timeout": 5,
    }).json()
    assert decoded["ok"] and decoded["output_decoding_replaced"] and decoded["output"] == "�"


def test_actual_departed_parent_descendant_pipe_is_stopped_not_claimed_complete(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    module.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    root = module.SANDBOX_ROOT
    worker = "import sys,time,subprocess\nfrom pathlib import Path\nif len(sys.argv)>1:\n while True:\n  Path('pipe-heartbeat').write_text(str(time.time_ns()))\n  time.sleep(0.02)\nelse:\n subprocess.Popen([sys.executable,'pipe.py','child'])\n"
    (root / "pipe.py").write_text(worker)
    result = client.post("/sandbox/exec", headers=HEADERS, json={
        "execution_id": "departed-parent", "command": [sys.executable, "pipe.py"], "timeout": 0,
    }).json()
    assert result["error"] == "output_capture_incomplete" and not result["retryable"]
    assert result["termination_confirmed"] and not result["uncertain_external_state"]
    before = (root / "pipe-heartbeat").read_text()
    time.sleep(0.1)
    assert (root / "pipe-heartbeat").read_text() == before
    assert all(not thread.is_alive() for thread in module._execution_records["departed-parent"]["capture_threads"])


def test_actual_capture_read_failure_cancels_producer_without_fake_success(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    module.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    def unavailable(_stream):
        raise OSError("isolated capture read failure")
    monkeypatch.setattr(module, "_read_capture_chunk", unavailable)
    started = time.monotonic()
    result = client.post("/sandbox/exec", headers=HEADERS, json={
        "command": [sys.executable, "-c", "import time;time.sleep(60)"], "timeout": 0,
    }).json()
    assert time.monotonic() - started < 5
    assert not result["ok"] and result["error"] == "output_capture_failed"
    assert result["termination_confirmed"] and not result["uncertain_external_state"] and not result["retryable"]


def test_actual_unlimited_output_redacts_json_whitespace_and_short_bearer(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    module.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    code = "import json;print(json.dumps({'token':'json secret words','authorization':'Bearer q','private_key':'tiny'}));print('password markedsecret; Bearer z')"
    result = client.post("/sandbox/exec", headers=HEADERS, json={
        "command": [sys.executable, "-c", code], "timeout": 5, "capture_bytes": 0, "output_chars": 0,
    }).json()
    assert result["ok"] and not result["partial"]
    assert all(secret not in result["output"] for secret in ["json secret words", "Bearer q", "tiny", "markedsecret", "Bearer z"])
    assert "[REDACTED]" in result["output"]


@pytest.mark.skipif(os.name != "nt", reason="Genuine Windows Job Object kill-on-close requires Windows")
def test_actual_windows_job_close_stops_suspended_owned_process(tmp_path):
    import subprocess
    from computer.windows_job import WindowsJob
    job = WindowsJob()
    process = subprocess.Popen([sys.executable, "-c", "from pathlib import Path;import time;Path('job-started').write_text('yes');time.sleep(60)"],
                               cwd=tmp_path, creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | 0x4)
    try:
        assert not (tmp_path / "job-started").exists()
        job.assign_and_resume(process.pid)
        _wait_for_file(tmp_path / "job-started")
        assert job.active_count() == 1
        job.close()
        process.wait(timeout=5)
        assert process.poll() is not None
    finally:
        job.close()
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)


@pytest.mark.skipif(os.name != "nt", reason="Genuine Windows suspended launch failure requires Windows")
def test_actual_windows_ownership_failure_never_runs_command(tmp_path, monkeypatch):
    from computer.windows_job import WindowsJob
    module, client = service(tmp_path, monkeypatch)
    module.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    job = WindowsJob()
    def unavailable(_pid):
        raise OSError("isolated assignment failure before thread resume")
    monkeypatch.setattr(job, "assign_and_resume", unavailable)
    monkeypatch.setattr(module, "_new_windows_job", lambda: job)
    result = client.post("/sandbox/exec", headers=HEADERS, json={
        "execution_id": "unowned-never-start", "command": [sys.executable, "-c", "from pathlib import Path;Path('unauthorized-start').write_text('bad')"], "timeout": 5,
    }).json()
    assert result["error"] == "process_ownership_failed" and not result["retryable"]
    assert result["termination_confirmed"] and not result["uncertain_external_state"]
    assert not (module.SANDBOX_ROOT / "unauthorized-start").exists()
    assert module._execution_records["unowned-never-start"]["process"] is None


@pytest.mark.skipif(os.name != "nt", reason="Genuine Windows departed-parent Job Object accounting requires Windows")
def test_actual_windows_background_descendant_without_pipes_is_owned(tmp_path, monkeypatch):
    import subprocess
    module, client = service(tmp_path, monkeypatch)
    module.ALLOW_DEGRADED_LOCAL_SANDBOX = True
    root = module.SANDBOX_ROOT
    worker = "import sys,os,time,subprocess\nfrom pathlib import Path\nif len(sys.argv)>1:\n Path('job-child-pid').write_text(str(os.getpid()))\n while True:\n  Path('job-child-heartbeat').write_text(str(time.time_ns()))\n  time.sleep(0.02)\nelse:\n subprocess.Popen([sys.executable,'job-background.py','child'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n while not Path('job-child-heartbeat').exists(): time.sleep(0.01)\n"
    (root / "job-background.py").write_text(worker)
    result = client.post("/sandbox/exec", headers=HEADERS, json={
        "execution_id": "background-descendant", "command": [sys.executable, "job-background.py"], "timeout": 5,
    }).json()
    assert result["error"] == "background_descendants" and not result["retryable"]
    assert result["termination_confirmed"] and not result["uncertain_external_state"]
    before = (root / "job-child-heartbeat").read_text()
    time.sleep(0.1)
    assert (root / "job-child-heartbeat").read_text() == before
    pid = (root / "job-child-pid").read_text()
    listing = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH"], capture_output=True, text=True, timeout=5)
    assert pid not in listing.stdout
    assert module._execution_records["background-descendant"].get("job") is None


@pytest.mark.skipif(os.name != "nt", reason="Genuine Windows job handle loss after holder termination requires Windows")
def test_actual_windows_holder_termination_kills_owned_child(tmp_path):
    import subprocess
    pid_file = tmp_path / "holder-child-pid"
    child_code = "from pathlib import Path;import os,time;Path(" + repr(str(pid_file)) + ").write_text(str(os.getpid()));time.sleep(60)"
    holder_code = "from computer.windows_job import WindowsJob;import subprocess,sys,time;job=WindowsJob();child=subprocess.Popen([sys.executable,'-c'," + repr(child_code) + "],creationflags=subprocess.CREATE_NEW_PROCESS_GROUP|4);job.assign_and_resume(child.pid);time.sleep(60)"
    holder = subprocess.Popen([sys.executable, "-c", holder_code], cwd=ROOT)
    child_pid = None
    child_gone = False
    try:
        _wait_for_file(pid_file)
        child_pid = pid_file.read_text()
        holder.terminate()
        holder.wait(timeout=5)
        deadline = time.monotonic() + 5
        while True:
            listing = subprocess.run(["tasklist", "/FI", f"PID eq {child_pid}", "/NH"], capture_output=True, text=True, timeout=5)
            if child_pid not in listing.stdout:
                child_gone = True
                break
            assert time.monotonic() < deadline, "Job child survived termination of its sole handle holder"
            time.sleep(0.02)
    finally:
        if holder.poll() is None:
            holder.terminate()
            holder.wait(timeout=5)
        if child_pid and not child_gone:
            subprocess.run(["taskkill", "/PID", child_pid, "/T", "/F"], capture_output=True, timeout=5)


def _spawn_gui_api_hanging_worker(kind, payload, _queue):
    root = Path(os.environ["AURORAFOX_SANDBOX_ROOT"])
    (root / "gui-api-started").write_text(str(payload["__execution_id"]) + ":" + kind)
    while True:
        (root / "gui-api-heartbeat").write_text(str(time.time_ns()))
        time.sleep(0.02)


def _spawn_gui_api_success_worker(_kind, _payload, queue):
    root = Path(os.environ["AURORAFOX_SANDBOX_ROOT"])
    with (root / "gui-api-launches").open("a") as count: count.write("started\n")
    queue.put({"ok": True, "done": True})


@pytest.mark.parametrize("route,body", [("/action", {"type": "wait", "seconds": 0}), ("/windows", None), ("/screen", None)])
def test_actual_gui_header_cancellation_stops_only_owned_worker(tmp_path, monkeypatch, route, body):
    import concurrent.futures
    module, client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    module.GUI_TIMEOUT_SECONDS = module.ACTION_TIMEOUT_SECONDS = 60
    monkeypatch.setattr(module, "_worker_entry", _spawn_gui_api_hanging_worker)
    root = module.SANDBOX_ROOT
    other = "from pathlib import Path;import time;Path('other-started').write_text('yes');time.sleep(60)"
    headers = {**HEADERS, "X-AuroraFox-Execution-ID": "owned-gui-header"}
    with concurrent.futures.ThreadPoolExecutor() as pool:
        remaining = pool.submit(module._run_process, [sys.executable, "-c", other], root, 60, allow_network=False, execution_id="unrelated-owned-process")
        future = pool.submit(client.post, route, headers=headers, json={**body, "execution_id": "model-spoof"}) if body else pool.submit(client.get, route, headers=headers)
        try:
            _wait_for_file(root / "gui-api-started")
            _wait_for_file(root / "other-started")
            assert (root / "gui-api-started").read_text().startswith("owned-gui-header:")
            assert "model-spoof" not in module._execution_records
            stopped = client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN}, json={"execution_id": "owned-gui-header"}).json()
            assert stopped["termination_confirmed"] and not stopped["uncertain_external_state"]
            result = future.result(timeout=5).json()
            assert result["error"] == "cancelled" and not result["retryable"]
            before = (root / "gui-api-heartbeat").read_text()
            time.sleep(0.1)
            assert (root / "gui-api-heartbeat").read_text() == before
            assert not remaining.done() and module._execution_records["unrelated-owned-process"]["process"].poll() is None
            assert not module._execution_stopping
        finally:
            module._cancel_all_processes()
            remaining.result(timeout=5)


def test_actual_gui_precancel_reused_id_and_header_validation_never_launch(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    monkeypatch.setattr(module, "_worker_entry", _spawn_gui_api_success_worker)
    root = module.SANDBOX_ROOT
    client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN}, json={"execution_id": "gui-precancel"})
    result = client.post("/action", headers={**HEADERS, "X-AuroraFox-Execution-ID": "gui-precancel"}, json={"type": "done"}).json()
    assert result["error"] == "cancelled" and not (root / "gui-api-launches").exists()
    headers = {**HEADERS, "X-AuroraFox-Execution-ID": "gui-one-use"}
    assert client.post("/action", headers=headers, json={"type": "done"}).json()["ok"]
    reused = client.post("/action", headers=headers, json={"type": "done"}).json()
    assert reused["error"] == "execution_id_reused" and not reused["retryable"]
    assert (root / "gui-api-launches").read_text().count("started") == 1
    assert client.post("/action", headers={**HEADERS, "X-AuroraFox-Execution-ID": "x" * 161}, json={"type": "done"}).status_code == 422
    assert client.post("/action", headers={**HEADERS, "X-AuroraFox-Execution-ID": "bad?identity"}, json={"type": "done"}).status_code == 422
    assert client.post("/action", headers={"X-AuroraFox-Execution-ID": "gui-no-auth"}, json={"type": "done"}).status_code == 401


def test_actual_unsafe_gui_cancel_before_verification_never_starts_next_phase(tmp_path, monkeypatch):
    import concurrent.futures
    module, client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    module.GUI_TIMEOUT_SECONDS = 60
    monkeypatch.setattr(module, "_worker_entry", _spawn_gui_api_hanging_worker)
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(client.post, "/action", headers={**HEADERS, "X-AuroraFox-Execution-ID": "gui-before-phase"},
                             json={"type": "press", "keys": ["a"], "verify": True, "action_id": "unsafe-gui-phase"})
        try:
            _wait_for_file(module.SANDBOX_ROOT / "gui-api-started")
            assert (module.SANDBOX_ROOT / "gui-api-started").read_text().endswith(":screen")
            stopped = client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN}, json={"execution_id": "gui-before-phase"}).json()
            assert stopped["termination_confirmed"] and stopped["uncertain_external_state"]
            result = future.result(timeout=5).json()
            assert result["error"] == "cancelled" and result["uncertain_external_state"] and not result["retryable"]
            assert (module.SANDBOX_ROOT / "gui-api-started").read_text().endswith(":screen")
        finally:
            module._cancel_all_processes()


def test_actual_gui_failed_stop_retains_worker_queue_and_native_owner(tmp_path, monkeypatch):
    import concurrent.futures
    module, client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    module.ACTION_TIMEOUT_SECONDS = 60
    monkeypatch.setattr(module, "_worker_entry", _spawn_gui_api_hanging_worker)
    real_stop = module._stop_gui_worker
    job = None
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(client.post, "/action", headers={**HEADERS, "X-AuroraFox-Execution-ID": "gui-failed-stop"}, json={"type": "wait"})
        try:
            _wait_for_file(module.SANDBOX_ROOT / "gui-api-started")
            job = module._execution_records["gui-failed-stop"].get("job")
            if job is not None:
                terminate_job = job.terminate
                monkeypatch.setattr(job, "terminate", lambda: False)
            monkeypatch.setattr(module, "_stop_gui_worker", lambda _worker, seconds=2: False)
            failed = client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN}, json={"execution_id": "gui-failed-stop"}).json()
            assert not failed["termination_confirmed"] and failed["uncertain_external_state"]
            result = future.result(timeout=5).json()
            assert not result["ok"] and not result["retryable"] and result["uncertain_external_state"]
            record = module._execution_records["gui-failed-stop"]
            assert record["worker"].is_alive() and record["worker_queue"] is not None and not record["finished"]
            monkeypatch.setattr(module, "_stop_gui_worker", real_stop)
            if job is not None: monkeypatch.setattr(job, "terminate", terminate_job)
            stopped = client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN}, json={"execution_id": "gui-failed-stop"}).json()
            assert stopped["termination_confirmed"] and not stopped["uncertain_external_state"]
            assert record["worker"] is None and record["worker_queue"] is None and record.get("job") is None
            assert module._gui_workers == set()
        finally:
            monkeypatch.setattr(module, "_stop_gui_worker", real_stop)
            if job is not None: monkeypatch.setattr(job, "terminate", terminate_job)
            module._cancel_all_processes()


class _ObservedLaunchGate:
    def __init__(self, gate, entered):
        self.gate, self.entered = gate, entered
    def wait(self, timeout):
        self.entered.set()
        return self.gate.wait(timeout)


def test_actual_bootstrap_waits_for_parent_authority_before_worker_code(tmp_path, monkeypatch):
    import multiprocessing as mp
    from computer.owned_gui_worker import run_owned_worker
    monkeypatch.setenv("AURORAFOX_SANDBOX_ROOT", str(tmp_path))
    context = mp.get_context("spawn")
    gate, entered = context.Event(), context.Event()
    queue = context.Queue(maxsize=1)
    process = context.Process(target=run_owned_worker, args=(_spawn_gui_api_success_worker, "action", {}, queue, _ObservedLaunchGate(gate, entered)))
    process.start()
    try:
        assert entered.wait(timeout=5), "Bootstrap never reached its authority gate"
        assert not (tmp_path / "gui-api-launches").exists()
        gate.set()
        assert queue.get(timeout=5)["ok"]
        process.join(timeout=5)
        assert not process.is_alive()
        assert (tmp_path / "gui-api-launches").read_text().count("started") == 1
    finally:
        if process.is_alive():
            process.terminate()
            process.join(timeout=5)
        queue.close()


def _uia_fixture(windows=2, controls=2, *, broken=False):
    from types import SimpleNamespace
    class Element:
        element_info = SimpleNamespace(name="fallback", control_type="Button", automation_id="identifier")
        def window_text(self): return "NameLong"
        def rectangle(self):
            if broken: raise RuntimeError("unavailable element")
            return SimpleNamespace(left=0, top=0, right=1, bottom=1)
        def descendants(self): return [Element() for _ in range(controls)]
    return SimpleNamespace(windows=lambda: [Element() for _ in range(windows)])


@pytest.mark.parametrize("key,cap", [("uia_items", 2), ("uia_windows", 1), ("uia_controls", 1), ("uia_name_chars", 3), ("uia_type_chars", 3), ("uia_id_chars", 3)])
def test_uia_owner_caps_report_real_overflow_and_zero_restores_coverage(tmp_path, monkeypatch, key, cap):
    module, _ = service(tmp_path, monkeypatch)
    unlimited = {k: 0 for k in module.GuiResourceLimits.model_fields}
    limited = module._collect_uia(_uia_fixture(), {**unlimited, key: cap})
    assert limited["ok"] and limited["partial"] and limited["limit_reached"]
    assert key in limited["limit_reasons"]
    complete = module._collect_uia(_uia_fixture(), unlimited)
    assert len(complete["items"]) == 6 and not complete["partial"] and not complete["limit_reached"]
    assert complete["items"][-1]["automation_id"] == "identifier"


def test_uia_exact_fit_and_failed_elements_are_distinct_from_overflow(tmp_path, monkeypatch):
    module, _ = service(tmp_path, monkeypatch)
    limits = module.GuiResourceLimits(uia_items=6, uia_windows=2, uia_controls=2, uia_name_chars=8, uia_type_chars=6, uia_id_chars=10).model_dump()
    complete = module._collect_uia(_uia_fixture(), limits)
    assert len(complete["items"]) == 6 and not complete["partial"]
    failed = module._collect_uia(_uia_fixture(broken=True), limits)
    assert failed["ok"] and failed["partial"] and failed["failed_elements"] == 2
    assert not failed["items"] and not failed["limit_reached"]


@pytest.mark.parametrize("bad", ['[]', '{"worker_seconds":-1}', '{"uia_items":-1}', 'invalid', '{"worker_seconds":1e100}'])
def test_gui_resource_header_rejects_bad_policy_before_worker_start(tmp_path, monkeypatch, bad):
    module, client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    monkeypatch.setattr(module, "_worker_entry", _spawn_gui_api_success_worker)
    result = client.get("/windows", headers={**HEADERS, "X-AuroraFox-GUI-Limits": bad})
    assert result.status_code == 422 and not (module.SANDBOX_ROOT / "gui-api-launches").exists()


def _spawn_gui_result_then_hanging_worker(_kind, _payload, queue):
    root = Path(os.environ["AURORAFOX_SANDBOX_ROOT"])
    queue.put({"ok": True, "items": []})
    (root / "gui-api-started").write_text("response queued")
    while True: time.sleep(0.02)


def test_zero_gui_deadline_keeps_waiting_after_response_and_remains_cancellable(tmp_path, monkeypatch):
    import concurrent.futures
    module, client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    monkeypatch.setattr(module, "_worker_entry", _spawn_gui_result_then_hanging_worker)
    headers = {**HEADERS, "X-AuroraFox-Execution-ID": "zero-gui-budget", "X-AuroraFox-GUI-Limits": '{"worker_seconds":0}'}
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(client.get, "/windows", headers=headers)
        try:
            _wait_for_file(module.SANDBOX_ROOT / "gui-api-started")
            time.sleep(0.3)
            assert not future.done(), "zero deadline became an implicit post-response timeout"
            stopped = client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token": TOKEN}, json={"execution_id":"zero-gui-budget"}).json()
            assert stopped["termination_confirmed"]
            result = future.result(timeout=5).json()
            assert result["error"] == "cancelled" and not result["retryable"]
        finally: module._cancel_all_processes()


@pytest.mark.parametrize("key,body,default,over", [
    ("action_text_chars", {"type":"type", "text":"x" * 20001}, 20000, 20001),
    ("action_keys", {"type":"hotkey", "keys":["a"] * 13}, 12, 13),
    ("action_clicks", {"type":"click", "x":1, "y":1, "clicks":4}, 3, 4),
    ("action_scroll", {"type":"scroll", "amount":-101}, 100, 101),
    ("action_seconds", {"type":"wait", "seconds":6}, 5, 6),
])
def test_action_owner_budget_rejects_before_effect_and_allows_exact_raised_zero(tmp_path, monkeypatch, key, body, default, over):
    module, client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    monkeypatch.setattr(module, "_worker_entry", _spawn_gui_api_success_worker)
    monkeypatch.setattr(module, "_desktop_bounds", lambda: {"left":0,"top":0,"right":10,"bottom":10,"width":10,"height":10})
    response = client.post("/action", headers=HEADERS, json={**body,"action_id":"denied", "_gui_limits":{key:0}})
    assert response.status_code == 413 and response.json()["detail"]["budget"] == key
    assert not response.json()["detail"]["executed"] and not (module.SANDBOX_ROOT / "gui-api-launches").exists()
    for cap in [over, 0]:
        headers = {**HEADERS,"X-AuroraFox-GUI-Limits":json.dumps({key:cap})}
        result = client.post("/action", headers=headers, json={**body,"action_id":f"accepted-{cap}"}).json()
        assert result["ok"], result
    exact = dict(body)
    if key == "action_text_chars": exact["text"] = exact["text"][:default]
    elif key == "action_keys": exact["keys"] = exact["keys"][:default]
    elif key == "action_clicks": exact["clicks"] = default
    elif key == "action_scroll": exact["amount"] = -default
    elif key == "action_seconds": exact["seconds"] = default
    assert client.post("/action", headers=HEADERS, json={**exact,"action_id":"exact-default"}).json()["ok"]
    assert len((module.SANDBOX_ROOT / "gui-api-launches").read_text().splitlines()) == 3


@pytest.mark.parametrize("body", [{"type":"wait", "seconds":-1}, {"type":"wait", "seconds":"NaN"}, {"type":"wait", "seconds":"Infinity"}, {"type":"click", "clicks":0}])
def test_unlimited_action_owner_policy_keeps_numeric_boundaries(tmp_path, monkeypatch, body):
    module, client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    headers = {**HEADERS,"X-AuroraFox-GUI-Limits":'{"action_seconds":0,"action_clicks":0}'}
    assert client.post("/action", headers=headers, json=body).status_code == 422
    assert not module._execution_records


def test_unlimited_unsafe_action_worker_is_cancellable_and_keeps_effect_uncertainty(tmp_path, monkeypatch):
    import concurrent.futures
    module, client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    monkeypatch.setattr(module, "_worker_entry", _spawn_gui_api_hanging_worker)
    headers = {**HEADERS,"X-AuroraFox-Execution-ID":"unsafe-unlimited","X-AuroraFox-GUI-Limits":'{"action_worker_seconds":0}'}
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(client.post, "/action", headers=headers, json={"type":"press","keys":["a"],"action_id":"unsafe-owner-zero"})
        try:
            _wait_for_file(module.SANDBOX_ROOT / "gui-api-started")
            assert not future.done()
            stopped = client.post("/sandbox/cancel", headers={"X-AuroraFox-Computer-Token":TOKEN}, json={"execution_id":"unsafe-unlimited"}).json()
            assert stopped["termination_confirmed"] and stopped["uncertain_external_state"]
            result = future.result(timeout=5).json()
            assert result["error"] == "cancelled" and not result["retryable"] and result["uncertain_external_state"]
        finally: module._cancel_all_processes()


def test_action_result_eviction_never_replays_consumed_unsafe_identity(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    monkeypatch.setattr(module, "_worker_entry", _spawn_gui_api_success_worker)
    headers = {**HEADERS,"X-AuroraFox-GUI-Limits":'{"action_results":1}'}
    for identity in ["first-unsafe", "second-unsafe"]:
        assert client.post("/action", headers=headers, json={"type":"press","keys":["a"],"action_id":identity}).json()["ok"]
    assert "first-unsafe" not in module._action_cache and "first-unsafe" in module._action_consumed
    replay = client.post("/action", headers=headers, json={"type":"press","keys":["a"],"action_id":"first-unsafe"}).json()
    assert replay["error"] == "action_result_evicted" and replay["deduplicated"] and replay["uncertain_external_state"]
    assert not replay["retryable"] and not replay["executed"]
    assert len((module.SANDBOX_ROOT / "gui-api-launches").read_text().splitlines()) == 2


def test_action_identity_capacity_denies_new_work_without_forgetting_prior_ids(tmp_path, monkeypatch):
    module, client = service(tmp_path, monkeypatch)
    module.IS_WINDOWS = True
    monkeypatch.setattr(module, "_worker_entry", _spawn_gui_api_success_worker)
    body = {"type":"press","keys":["a"]}
    headers = {**HEADERS,"X-AuroraFox-GUI-Limits":'{"action_results":0,"action_identities":1}'}
    assert client.post("/action", headers=headers, json={**body,"action_id":"retained"}).json()["ok"]
    denied = client.post("/action", headers=headers, json={**body,"action_id":"new"}).json()
    assert denied["error"] == "action_identity_capacity" and not denied["executed"] and denied["limit_reached"]
    assert client.post("/action", headers=headers, json={**body,"action_id":"retained"}).json()["deduplicated"]
    unlimited = {**HEADERS,"X-AuroraFox-GUI-Limits":'{"action_results":0,"action_identities":0}'}
    assert client.post("/action", headers=unlimited, json={**body,"action_id":"new"}).json()["ok"]
    assert len(module._action_cache) == 2 and len((module.SANDBOX_ROOT / "gui-api-launches").read_text().splitlines()) == 2


def test_unexpected_action_exception_consumes_identity_before_retry(tmp_path, monkeypatch):
    module, _ = service(tmp_path, monkeypatch)
    def broken_worker(*_args): raise RuntimeError("after possible input")
    monkeypatch.setattr(module, "_run_worker", broken_worker)
    request = module.Action(type="press", keys=["a"], action_id="unexpected-effect")
    with pytest.raises(RuntimeError): module._execute_action(request)
    monkeypatch.setattr(module, "_run_worker", lambda *_args: pytest.fail("replayed after unexpected exception"))
    result = module._execute_action(request)
    assert result["error"] == "action_result_evicted" and not result["retryable"] and result["uncertain_external_state"]
