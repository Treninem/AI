from __future__ import annotations

from pathlib import Path
import json
import multiprocessing
import pytest

from api.learning_sync import LearningSynchronizer
from api.learning_store import LearningStore


class FakeBridge:
    def __init__(self, fail: bool = False) -> None:
        self.fail = fail
        self.learn_calls: list[dict] = []
        self.feedback_calls: list[dict] = []

    def learn(self, payload: dict) -> dict:
        self.learn_calls.append(payload)
        if self.fail:
            return {"ok": False, "error": "offline"}
        return {"ok": True, "learned": True}

    def feedback(self, payload: dict) -> dict:
        self.feedback_calls.append(payload)
        if self.fail:
            return {"ok": False, "error": "offline"}
        return {"ok": True, "feedback_recorded": True}


def test_private_api_interaction_is_not_queued(tmp_path: Path) -> None:
    bridge = FakeBridge()
    sync = LearningSynchronizer(tmp_path, bridge)
    result = sync.record(
        "api_interaction",
        {"metadata": {"share_for_learning": False}, "content": "private"},
    )
    assert result["skipped_private"] is True
    assert result["event_id"] == ""
    assert bridge.learn_calls == []


def test_opted_in_learning_syncs_immediately(tmp_path: Path) -> None:
    bridge = FakeBridge()
    sync = LearningSynchronizer(tmp_path, bridge)
    result = sync.record(
        "api_interaction",
        {"metadata": {"share_for_learning": True}, "content": "shared"},
    )
    assert result["synced"] is True
    assert len(bridge.learn_calls) == 1
    assert sync.status()["pending"] == 0


def test_failed_sync_stays_pending_and_flush_retries(tmp_path: Path) -> None:
    bridge = FakeBridge(fail=True)
    sync = LearningSynchronizer(tmp_path, bridge)
    result = sync.record("external_knowledge", {"content": "knowledge"}, try_sync=True)
    assert result["synced"] is False
    assert sync.status()["pending"] == 1

    bridge.fail = False
    flushed = sync.flush(10)
    assert flushed["ok"] is True
    assert flushed["synced"] == 1
    assert flushed["pending"] == 0
    assert len(bridge.learn_calls) == 2


def test_feedback_is_retried(tmp_path: Path) -> None:
    bridge = FakeBridge(fail=True)
    sync = LearningSynchronizer(tmp_path, bridge)
    result = sync.feedback({"score": 0.5}, try_sync=True)
    assert result["synced"] is False
    assert sync.status()["pending"] == 1

    bridge.fail = False
    flushed = sync.flush(10)
    assert flushed["synced"] == 1
    assert len(bridge.feedback_calls) == 2


def _queue_writer(root: str, start, mode: str) -> None:
    store = LearningStore(Path(root))
    start.wait(10)
    for index in range(80):
        event = store.append("external_knowledge", {"writer": mode, "index": index})
        if mode == "sync":
            store.mark_synced({event["id"]})


def test_separate_processes_do_not_lose_appends(tmp_path: Path) -> None:
    context = multiprocessing.get_context("spawn")
    start = context.Event()
    processes = [context.Process(target=_queue_writer, args=(str(tmp_path), start, mode))
                 for mode in ("api", "sync")]
    for process in processes:
        process.start()
    start.set()
    for process in processes:
        process.join(30)
        if process.is_alive():
            process.terminate()
            process.join()
        assert process.exitcode == 0
    store = LearningStore(tmp_path)
    assert len(store.pending(None)) == 80
    events = [json.loads(line) for line in store.path.read_text().splitlines()]
    assert len(events) == 160
    assert len({event["id"] for event in events}) == 160


def test_retention_never_drops_pending_events(tmp_path: Path) -> None:
    store = LearningStore(tmp_path, max_events=1000)
    pending_ids = {store.append("external_knowledge", {"i": i})["id"] for i in range(1005)}
    acknowledged = store.append("external_knowledge", {"ack": True})
    store.mark_synced({acknowledged["id"]})
    assert {e["id"] for e in store.pending(None)} == pending_ids


def test_corrupt_queue_is_reported_not_empty(tmp_path: Path) -> None:
    store = LearningStore(tmp_path)
    store.path.write_text('{"id":', encoding="utf-8")
    with pytest.raises(ValueError, match="Corrupt"):
        store.pending()


def test_failed_atomic_replace_keeps_original(tmp_path: Path, monkeypatch) -> None:
    store = LearningStore(tmp_path)
    event = store.append("external_knowledge", {"content": "keep"})
    original = store.path.read_bytes()
    def fail_replace(*args):
        raise OSError("injected crash before replace")
    monkeypatch.setattr(Path, "replace", fail_replace)
    with pytest.raises(OSError):
        store.mark_synced({event["id"]})
    assert store.path.read_bytes() == original


def test_exception_reports_actual_attempts(tmp_path: Path) -> None:
    class Offline(FakeBridge):
        def learn(self, payload):
            raise ConnectionError("offline")
    sync = LearningSynchronizer(tmp_path, Offline())
    for _ in range(3):
        sync.record("external_knowledge", {}, try_sync=False)
    assert sync.flush(10) == {"ok": False, "attempted": 1, "synced": 0, "failed": 1, "pending": 3}


def test_flush_checkpoints_before_next_delivery(tmp_path: Path) -> None:
    class CheckpointBridge(FakeBridge):
        def learn(self, payload):
            if self.learn_calls:
                assert len(LearningStore(tmp_path).pending(None)) == 1
            return super().learn(payload)
    sync = LearningSynchronizer(tmp_path, CheckpointBridge())
    for _ in range(2):
        sync.record("external_knowledge", {}, try_sync=False)
    assert sync.flush(2)["synced"] == 2


def test_zero_time_budget_preserves_pending(tmp_path: Path) -> None:
    sync = LearningSynchronizer(tmp_path, FakeBridge())
    sync.record("external_knowledge", {}, try_sync=False)
    assert sync.flush(10, max_seconds=0) == {"ok": True, "attempted": 0, "synced": 0, "failed": 0, "pending": 1}


def test_daemon_reports_failure_and_uses_configured_data(tmp_path: Path, monkeypatch) -> None:
    from api import learning_daemon
    monkeypatch.setenv("AURORAFOX_USER_DIR", str(tmp_path))
    bridge = FakeBridge(fail=True)
    monkeypatch.setattr(learning_daemon, "AuroraRuntimeBridge", lambda **kwargs: bridge)
    LearningStore(tmp_path / "api").append("external_knowledge", {"content": "pending"})
    assert learning_daemon.main() == 1
    bridge.fail = False
    assert learning_daemon.main() == 0


def test_timer_install_is_not_silently_skipped() -> None:
    root = Path(__file__).resolve().parents[1]
    updater = (root / "deploy/reg_ru/update.sh").read_text()
    installer = (root / "deploy/reg_ru/install_learning_sync.sh").read_text()
    bootstrap = (root / "deploy/reg_ru/install.sh").read_text()
    assert 'bash deploy/reg_ru/install_learning_sync.sh' in updater
    assert '[[ -x "deploy/reg_ru/install_learning_sync.sh" ]]' not in updater
    assert "tests/test_learning_sync.py" in updater
    assert updater.index('test "${healthy}"') < updater.index('bash deploy/reg_ru/install_learning_sync.sh')
    assert 'install -m 0755 deploy/reg_ru/update.sh /usr/local/sbin/aurorafox-update' in updater
    assert 'bash /opt/aurorafox/repository/deploy/reg_ru/install_learning_sync.sh' in bootstrap
    assert 'systemctl start "${SERVICE}"' not in installer
    assert 'TimeoutStartSec=90s' in installer


def test_ack_cannot_change_another_owners_event(tmp_path: Path) -> None:
    store = LearningStore(tmp_path)
    a = store.append("external_knowledge", {"api_key_id": "a"})
    b = store.append("external_knowledge", {"api_key_id": "b"})
    assert store.mark_synced({a["id"], b["id"]}, owner="a") == 1
    assert [event["id"] for event in store.pending(None)] == [b["id"]]
    assert store.mark_synced({a["id"]}, owner="a") == 0


@pytest.mark.parametrize("url", ["http://localhost", "https://user:password@example.com", "https://example.com/x", "https://example.com?token=x"])
def test_pull_rejects_insecure_or_credential_urls(tmp_path: Path, url: str) -> None:
    from api.learning_pull import LearningPullClient
    with pytest.raises(ValueError):
        LearningPullClient(url, "token", tmp_path)


def test_pull_does_not_redeliver_after_lost_ack(tmp_path: Path) -> None:
    from api.learning_pull import LearningPullClient
    bridge = FakeBridge()
    client = LearningPullClient("https://example.com", "token", tmp_path, bridge)
    event = {"id": "durable-event", "kind": "external_knowledge", "payload": {"content": "shared"}}
    attempts = []
    def request(method, path, payload=None):
        if method == "GET":
            return {"ok": True, "events": [event]}
        attempts.append(payload)
        if len(attempts) == 1:
            raise ConnectionError("lost acknowledgement")
        return {"ok": True, "acknowledged": 1}
    client._request = request
    with pytest.raises(ConnectionError):
        client.run_once()
    assert client.run_once()["synced"] == 1
    assert len(bridge.learn_calls) == 1


def test_real_https_api_isolates_queue_and_ack(tmp_path: Path, monkeypatch) -> None:
    """Real TLS + uvicorn + durable queue, not a mocked FastAPI handler."""
    import os
    import shutil
    import socket
    import subprocess
    import sys
    import time
    import requests
    from api.auth import KeyStore
    from api.learning_pull import LearningPullClient

    openssl = shutil.which("openssl")
    if not openssl:
        pytest.skip("TLS integration requires openssl")
    cert, key = tmp_path / "cert.pem", tmp_path / "key.pem"
    subprocess.run([openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                    "-keyout", str(key), "-out", str(cert), "-days", "1",
                    "-subj", "/CN=localhost", "-addext", "subjectAltName=IP:127.0.0.1"],
                   check=True, capture_output=True)
    root = tmp_path / "data"
    keys = KeyStore(root / "api")
    token_a, owner_a = keys.create("A", ["learning.sync"])
    token_b, owner_b = keys.create("B", ["learning.sync"])
    token_guest, _ = keys.create("ordinary")
    store = LearningStore(root / "api")
    event_a = store.append("external_knowledge", {"content": "a", "api_key_id": owner_a["id"]})
    event_b = store.append("external_knowledge", {"content": "b", "api_key_id": owner_b["id"]})
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    origin = "https://127.0.0.1:%d" % port
    environment = dict(os.environ, AURORAFOX_USER_DIR=str(root), AURORAFOX_BRIDGE_PORT="1")
    server = subprocess.Popen([sys.executable, "-m", "uvicorn", "api.server:app", "--host", "127.0.0.1",
                               "--port", str(port), "--timeout-graceful-shutdown", "2",
                               "--ssl-certfile", str(cert), "--ssl-keyfile", str(key)],
                              env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            assert server.poll() is None, "API exited before accepting requests"
            try:
                if requests.get(origin + "/openapi.json", verify=str(cert), timeout=1).status_code == 200:
                    break
            except requests.RequestException:
                time.sleep(0.05)
        else:
            pytest.fail("API startup timed out")
        url = origin + "/v1/learning/pending"
        assert requests.get(url, verify=str(cert), timeout=3).status_code == 401
        headers = lambda token: {"Authorization": "Bearer " + token}
        assert requests.get(url, headers=headers(token_guest), verify=str(cert), timeout=3).status_code == 403
        response = requests.get(url, headers=headers(token_a), verify=str(cert), timeout=3)
        assert response.status_code == 200
        assert [e["id"] for e in response.json()["events"]] == [event_a["id"]]
        response = requests.post(origin + "/v1/learning/ack", headers=headers(token_a),
                                 json={"event_ids": [event_b["id"]]}, verify=str(cert), timeout=3)
        assert response.json()["acknowledged"] == 0
        monkeypatch.setenv("REQUESTS_CA_BUNDLE", str(cert))
        bridge = FakeBridge()
        consumer = LearningPullClient(origin, token_a, tmp_path / "pc", bridge)
        assert consumer.run_once() == {"ok": True, "synced": 1, "failed": 0}
        assert bridge.learn_calls == [event_a["payload"]]
        assert consumer.run_once()["synced"] == 0
        assert [e["id"] for e in store.pending(None)] == [event_b["id"]]
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait(timeout=5)


@pytest.mark.parametrize("previous_timer", [False, True])
def test_updater_restores_units_after_install_failure(tmp_path: Path, previous_timer: bool) -> None:
    """Execute real updater control flow with sandboxed paths and command doubles."""
    import os
    import shutil
    import subprocess
    if os.name == "nt" or os.geteuid() != 0 or not shutil.which("bash"):
        pytest.skip("Updater requires a Linux root test container")
    root = Path(__file__).resolve().parents[1]
    repo = tmp_path / "repository"
    config = tmp_path / "config"
    units = tmp_path / "units"
    commands = tmp_path / "bin"
    installed = tmp_path / "aurorafox-update"
    for path in (repo / "deploy/reg_ru", config, units, commands, tmp_path / "venv/bin"):
        path.mkdir(parents=True, exist_ok=True)
    (config / "aurorafox.env").write_text("AURORAFOX_GITHUB_REF=main\n")
    installed.write_text("old-installed-updater")
    for name in ("aurorafox-learning-sync.service", "aurorafox-learning-sync.timer"):
        if previous_timer:
            (units / name).write_text("old-" + name)
    source = (root / "deploy/reg_ru/update.sh").read_text()
    for before, after in (("/opt/aurorafox/repository", str(repo)), ("/etc/aurorafox", str(config)),
                          ("/etc/systemd/system", str(units)), ("/opt/aurorafox/venv", str(tmp_path / "venv")),
                          ("/usr/local/sbin/aurorafox-update", str(installed))):
        source = source.replace(before, after)
    script = tmp_path / "candidate-update.sh"
    script.write_text(source)
    def executable(path, text):
        path.write_text("#!/usr/bin/env bash\n" + text)
        path.chmod(0o755)
    executable(commands / "git", '''case "$1" in
remote) echo 'https://github.com/Treninem/AI.git';;
rev-parse) if [[ "$2" == HEAD ]]; then echo previous; else echo candidate; fi;;
esac
exit 0
''')
    executable(commands / "systemctl", '''echo "$*" >> "$TEST_COMMAND_LOG"
if [[ "$1" == is-enabled || "$1" == is-active ]]; then exit "$TEST_TIMER_STATUS"; fi
exit 0
''')
    executable(commands / "curl", "echo '{\"ok\":true}'\n")
    executable(tmp_path / "venv/bin/python", "exit 0\n")
    installer = repo / "deploy/reg_ru/install_learning_sync.sh"
    installer.write_text('''printf 'candidate service' > "$TEST_UNITS/aurorafox-learning-sync.service"
printf 'candidate timer' > "$TEST_UNITS/aurorafox-learning-sync.timer"
exit 7
''')
    environment = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                       TEST_COMMAND_LOG=str(tmp_path / "commands.log"), TEST_UNITS=str(units),
                       TEST_TIMER_STATUS="0" if previous_timer else "1")
    result = subprocess.run(["bash", str(script)], env=environment, capture_output=True, text=True, timeout=15)
    assert result.returncode == 7, result.stdout + result.stderr
    assert installed.read_text() == "old-installed-updater"
    for name in ("aurorafox-learning-sync.service", "aurorafox-learning-sync.timer"):
        if previous_timer:
            assert (units / name).read_text() == "old-" + name
        else:
            assert not (units / name).exists()
    assert (config / "build.env").read_text() == "AURORAFOX_BUILD_SHA=previous\n"
    log = (tmp_path / "commands.log").read_text()
    assert "restart aurorafox-api.service" in log
    if previous_timer:
        assert "enable aurorafox-learning-sync.timer" in log
        assert "start aurorafox-learning-sync.timer" in log
