from __future__ import annotations

import base64
import hashlib
import threading
from concurrent.futures import ThreadPoolExecutor
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


def test_concurrent_duplicate_submission_is_serialized_and_idempotent(tmp_path: Path) -> None:
    queue = CoreCandidateQueue(tmp_path / "api")
    manifest, encoded, _ = _submission("candidate_parallel")
    start = threading.Barrier(8)

    def submit(index: int):
        start.wait(timeout=3)
        return queue.submit(manifest, encoded, owner=f"device-{index}")

    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(submit, range(8)))

    assert sum(1 for item in results if item["duplicate"] is False) == 1
    assert sum(1 for item in results if item["duplicate"] is True) == 7
    assert len([path for path in queue.queue_root.iterdir() if path.is_dir()]) == 1
    row = queue.get("candidate_parallel")
    assert row["state"] == "queued"
    assert row["candidate_sha256"] == manifest["candidate_sha256"]


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
