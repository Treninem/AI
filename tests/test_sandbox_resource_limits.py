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
