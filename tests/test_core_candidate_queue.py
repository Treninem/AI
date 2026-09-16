from __future__ import annotations

import base64
import hashlib
import json
import multiprocessing
from pathlib import Path

import pytest

from api.auth import DEFAULT_SCOPES, KeyStore, allows
from api.core_candidate_queue import CoreCandidateQueue, CoreCandidateQueueError

ROOT = Path(__file__).resolve().parents[1]


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _submission(candidate_id: str = "candidate_001") -> tuple[dict, str, str]:
    base = "class_name MemoryStore\nextends Node\nfunc search(q):\n\treturn []\n"
    candidate = "class_name MemoryStore\nextends Node\nfunc search(q):\n\treturn [] if q == null else []\n"
    manifest = {
        "candidate_id": candidate_id,
        "target": "scripts/memory_store.gd",
        "base_sha256": _sha(base),
        "candidate_sha256": _sha(candidate),
        "verified": True,
        "promotion": "signed_update",
        "verification": {
            "source_contract": {"ok": True},
            "comparative_review": {"ok": True, "improvement": 1.25},
        },
    }
    encoded = base64.b64encode(candidate.encode("utf-8")).decode("ascii")
    return manifest, encoded, candidate


def test_default_api_keys_cannot_submit_core_candidates(tmp_path: Path) -> None:
    store = KeyStore(tmp_path / "keys")
    token, record = store.create("ordinary integration")
    verified = store.verify(token)
    assert verified is not None
    assert set(DEFAULT_SCOPES).issubset(set(record["scopes"]))
    assert not allows(verified, "core.candidate.submit")
    assert not allows(verified, "core.candidate.manage")


def test_server_exposes_candidate_routes_only_behind_explicit_scopes() -> None:
    server = (ROOT / "api" / "server.py").read_text(encoding="utf-8")
    assert '@app.post("/v1/core-candidates")' in server
    assert '_require(record, "core.candidate.submit")' in server
    assert '@app.get("/v1/core-candidates/status")' in server
    assert '_require(record, "core.candidate.manage")' in server
    assert 'str(row.get("owner", "")) == str(record.get("id", ""))' in server
    auth = (ROOT / "api" / "auth.py").read_text(encoding="utf-8")
    default_block = auth.split("DEFAULT_SCOPES = [", 1)[1].split("]", 1)[0]
    assert "core.candidate.submit" not in default_block
    assert "core.candidate.manage" not in default_block


def test_verified_candidate_is_queued_and_materialized_without_execution(tmp_path: Path) -> None:
    queue = CoreCandidateQueue(tmp_path / "api")
    manifest, encoded, candidate = _submission()
    result = queue.submit(manifest, encoded, owner="device-key", source="windows-client")
    assert result["ok"] is True
    assert result["state"] == "queued"
    assert result["owner"] == "device-key"

    bundle = tmp_path / "submission"
    materialized = queue.materialize_submission("candidate_001", bundle)
    assert materialized["ok"] is True
    assert (bundle / "candidate.json").is_file()
    assert (bundle / "scripts" / "memory_store.gd").read_text(encoding="utf-8") == candidate


def test_duplicate_submission_is_idempotent_but_id_reuse_with_other_bytes_is_rejected(tmp_path: Path) -> None:
    queue = CoreCandidateQueue(tmp_path / "api")
    manifest, encoded, _ = _submission()
    first = queue.submit(manifest, encoded, owner="one")
    second = queue.submit(manifest, encoded, owner="one")
    assert first["duplicate"] is False
    assert second["duplicate"] is True

    other_manifest, other_encoded, _ = _submission()
    other_manifest["candidate_sha256"] = hashlib.sha256(b"different").hexdigest()
    other_encoded = base64.b64encode(b"different").decode("ascii")
    with pytest.raises(CoreCandidateQueueError, match="candidate_id already exists"):
        queue.submit(other_manifest, other_encoded, owner="two")


def test_submission_rejects_protected_target_bad_sha_and_unverified_evidence(tmp_path: Path) -> None:
    queue = CoreCandidateQueue(tmp_path / "api")
    manifest, encoded, _ = _submission("candidate_bad")

    protected = dict(manifest)
    protected["target"] = "update/update_manager.gd"
    with pytest.raises(CoreCandidateQueueError, match="allowlist"):
        queue.submit(protected, encoded, owner="device")

    bad_sha = dict(manifest)
    bad_sha["candidate_sha256"] = "0" * 64
    with pytest.raises(CoreCandidateQueueError, match="does not match"):
        queue.submit(bad_sha, encoded, owner="device")

    unverified = dict(manifest)
    unverified["verified"] = False
    with pytest.raises(CoreCandidateQueueError, match="not verified locally"):
        queue.submit(unverified, encoded, owner="device")


def test_terminal_state_cannot_be_reopened(tmp_path: Path) -> None:
    queue = CoreCandidateQueue(tmp_path / "api")
    manifest, encoded, _ = _submission("candidate_terminal")
    queue.submit(manifest, encoded, owner="device")
    promoted = queue.set_state("candidate_terminal", "promoted", promotion_ref="refs/heads/core/promotion")
    assert promoted["state"] == "promoted"
    with pytest.raises(CoreCandidateQueueError, match="terminal candidate state"):
        queue.set_state("candidate_terminal", "queued")


@pytest.mark.parametrize("candidate_id", [".", ".."])
def test_candidate_id_cannot_name_parent_directory(tmp_path, candidate_id):
    queue = CoreCandidateQueue(tmp_path)
    manifest, encoded, _ = _submission(candidate_id)
    with pytest.raises(CoreCandidateQueueError, match="candidate_id"):
        queue.submit(manifest, encoded, owner="a")
    assert queue.get(candidate_id) == {}


def test_duplicate_cannot_disclose_other_owner_or_change_base(tmp_path):
    queue = CoreCandidateQueue(tmp_path)
    manifest, encoded, _ = _submission()
    queue.submit(manifest, encoded, owner="private-owner")
    with pytest.raises(CoreCandidateQueueError):
        queue.submit(manifest, encoded, owner="other-owner")
    manifest["base_sha256"] = "1" * 64
    with pytest.raises(CoreCandidateQueueError):
        queue.submit(manifest, encoded, owner="private-owner")


@pytest.mark.parametrize("field,value", [("target", "scripts/agent_core.gd"), ("base_sha256", "1" * 64), ("verified", False)])
def test_materialization_revalidates_persistent_manifest(tmp_path, field, value):
    queue = CoreCandidateQueue(tmp_path)
    manifest, encoded, _ = _submission()
    queue.submit(manifest, encoded, owner="a")
    manifest[field] = value
    (queue.queue_root / "candidate_001" / "candidate.json").write_text(json.dumps(manifest))
    destination = tmp_path / "existing"
    destination.mkdir()
    (destination / "keep.txt").write_text("preserve")
    with pytest.raises(CoreCandidateQueueError):
        CoreCandidateQueue(tmp_path).materialize_submission("candidate_001", destination)
    assert (destination / "keep.txt").read_text() == "preserve"


def _concurrent_submit(root, index, result_queue):
    queue = CoreCandidateQueue(Path(root), max_items=2)
    manifest, encoded, _ = _submission("concurrent_" + str(index))
    try:
        queue.submit(manifest, encoded, owner="a")
        result_queue.put("queued")
    except CoreCandidateQueueError:
        result_queue.put("full")


def test_multiple_processes_cannot_overfill_queue(tmp_path):
    context = multiprocessing.get_context("spawn")
    results = context.Queue()
    workers = [context.Process(target=_concurrent_submit, args=(str(tmp_path), i, results)) for i in range(6)]
    for worker in workers:
        worker.start()
    try:
        statuses = [results.get(timeout=30) for _ in workers]
        for worker in workers:
            worker.join(timeout=10)
            assert worker.exitcode == 0
        assert statuses.count("queued") == 2
        assert statuses.count("full") == 4
        assert CoreCandidateQueue(tmp_path).status()["items"] == 2
    finally:
        for worker in workers:
            if worker.is_alive():
                worker.terminate()
                worker.join(timeout=5)
        results.close()


def test_materialization_cannot_delete_persistent_queue(tmp_path):
    queue = CoreCandidateQueue(tmp_path / "api")
    manifest, encoded, _ = _submission()
    queue.submit(manifest, encoded, owner="a")
    for destination in (tmp_path, queue.root, queue.queue_root, queue.queue_root / "candidate_001"):
        with pytest.raises(CoreCandidateQueueError, match="overlaps"):
            queue.materialize_submission("candidate_001", destination)
    assert queue.get("candidate_001")["state"] == "queued"
