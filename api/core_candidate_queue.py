from __future__ import annotations

import base64
import hashlib
import json
import re
import shutil
import tempfile
import time
from pathlib import Path, PurePosixPath
from typing import Any

ALLOWED_TARGETS = {
    "scripts/cognition_layer.gd",
    "scripts/agent_core.gd",
    "scripts/memory_store.gd",
    "agent/goals.gd",
}
MAX_SOURCE_BYTES = 1024 * 1024
MAX_ENCODED_BYTES = 2 * 1024 * 1024
MAX_QUEUE_ITEMS = 200
CANDIDATE_ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,80}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
TERMINAL_STATES = {"promoted", "rejected", "expired"}
VALID_STATES = {"received", "queued", "verifying", "promoted", "rejected", "expired"}


class CoreCandidateQueueError(ValueError):
    pass


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().lower()


def _safe_target(value: Any) -> str:
    target = str(value or "").strip()
    if "\\" in target or target.startswith("/"):
        raise CoreCandidateQueueError("candidate target must be a canonical repository path")
    parts = PurePosixPath(target).parts
    if not parts or any(part in {"", ".", ".."} for part in parts):
        raise CoreCandidateQueueError("candidate target contains unsafe path components")
    if target not in ALLOWED_TARGETS:
        raise CoreCandidateQueueError("candidate target is outside the Core promotion allowlist")
    return target


def _decode_source(content_base64: str) -> bytes:
    if not content_base64 or len(content_base64) > MAX_ENCODED_BYTES:
        raise CoreCandidateQueueError("candidate source payload is empty or too large")
    try:
        raw = base64.b64decode(content_base64, validate=True)
    except Exception as exc:
        raise CoreCandidateQueueError("candidate source is not valid base64") from exc
    if not raw or len(raw) > MAX_SOURCE_BYTES:
        raise CoreCandidateQueueError("candidate source is empty or exceeds the 1 MiB limit")
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise CoreCandidateQueueError("candidate source must be UTF-8 text") from exc
    return raw


def validate_submission(manifest: dict[str, Any], content_base64: str) -> tuple[dict[str, Any], bytes]:
    if not isinstance(manifest, dict):
        raise CoreCandidateQueueError("candidate manifest must be an object")
    candidate_id = str(manifest.get("candidate_id", "")).strip()
    if not CANDIDATE_ID_RE.fullmatch(candidate_id):
        raise CoreCandidateQueueError("candidate_id is missing or unsafe")
    target = _safe_target(manifest.get("target"))
    base_sha = str(manifest.get("base_sha256", "")).lower()
    candidate_sha = str(manifest.get("candidate_sha256", "")).lower()
    if not SHA256_RE.fullmatch(base_sha) or not SHA256_RE.fullmatch(candidate_sha):
        raise CoreCandidateQueueError("candidate manifest must contain valid SHA-256 values")
    if base_sha == candidate_sha:
        raise CoreCandidateQueueError("candidate is byte-identical to its declared base")
    if manifest.get("verified") is not True:
        raise CoreCandidateQueueError("candidate was not verified locally")
    if str(manifest.get("promotion", "")) != "signed_update":
        raise CoreCandidateQueueError("candidate is not staged for trusted signed-update promotion")
    verification = manifest.get("verification")
    if not isinstance(verification, dict):
        raise CoreCandidateQueueError("candidate verification evidence is missing")
    source_contract = verification.get("source_contract")
    review = verification.get("comparative_review")
    if not isinstance(source_contract, dict) or source_contract.get("ok") is not True:
        raise CoreCandidateQueueError("candidate source-contract evidence is missing or failed")
    if not isinstance(review, dict) or review.get("ok") is not True:
        raise CoreCandidateQueueError("candidate comparative-review evidence is missing or failed")
    raw = _decode_source(content_base64)
    actual_sha = _sha256(raw)
    if actual_sha != candidate_sha:
        raise CoreCandidateQueueError("candidate source SHA-256 does not match manifest")
    clean = json.loads(json.dumps(manifest, ensure_ascii=False))
    clean["candidate_id"] = candidate_id
    clean["target"] = target
    clean["base_sha256"] = base_sha
    clean["candidate_sha256"] = candidate_sha
    return clean, raw


class CoreCandidateQueue:
    def __init__(self, root: Path, max_items: int = MAX_QUEUE_ITEMS):
        self.root = root.resolve()
        self.queue_root = self.root / "core_candidates"
        self.queue_root.mkdir(parents=True, exist_ok=True)
        self.max_items = max(1, int(max_items))

    def submit(
        self,
        manifest: dict[str, Any],
        content_base64: str,
        *,
        owner: str,
        source: str = "aurorafox-client",
    ) -> dict[str, Any]:
        clean, raw = validate_submission(manifest, content_base64)
        candidate_id = clean["candidate_id"]
        target = clean["target"]
        existing = self.get(candidate_id)
        if existing:
            if existing.get("candidate_sha256") == clean["candidate_sha256"]:
                return {"ok": True, "duplicate": True, **existing}
            raise CoreCandidateQueueError("candidate_id already exists with different bytes")
        self._trim_if_needed()
        now = int(time.time())
        record = {
            "candidate_id": candidate_id,
            "target": target,
            "base_sha256": clean["base_sha256"],
            "candidate_sha256": clean["candidate_sha256"],
            "state": "queued",
            "owner": str(owner)[:128],
            "source": str(source)[:128],
            "received_at": now,
            "updated_at": now,
            "size_bytes": len(raw),
            "promotion_ref": "",
            "promotion_run": "",
            "error": "",
        }
        final_dir = self.queue_root / candidate_id
        with tempfile.TemporaryDirectory(prefix="aurora-core-candidate-", dir=str(self.queue_root)) as tmp_name:
            tmp = Path(tmp_name)
            (tmp / target).parent.mkdir(parents=True, exist_ok=True)
            (tmp / target).write_bytes(raw)
            (tmp / "candidate.json").write_text(
                json.dumps(clean, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
            (tmp / "queue.json").write_text(
                json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
            tmp.rename(final_dir)
        return {"ok": True, "duplicate": False, **record}

    def get(self, candidate_id: str) -> dict[str, Any]:
        if not CANDIDATE_ID_RE.fullmatch(str(candidate_id or "")):
            return {}
        path = self.queue_root / candidate_id / "queue.json"
        if not path.is_file():
            return {}
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            return value if isinstance(value, dict) else {}
        except Exception:
            return {}

    def list(self, limit: int = 50, state: str = "") -> list[dict[str, Any]]:
        wanted = str(state or "").strip()
        if wanted and wanted not in VALID_STATES:
            raise CoreCandidateQueueError("unknown candidate queue state")
        rows: list[dict[str, Any]] = []
        for path in self.queue_root.iterdir():
            if not path.is_dir() or not CANDIDATE_ID_RE.fullmatch(path.name):
                continue
            row = self.get(path.name)
            if not row or (wanted and row.get("state") != wanted):
                continue
            rows.append(row)
        rows.sort(key=lambda item: int(item.get("updated_at", 0)), reverse=True)
        return rows[: max(1, min(int(limit), 200))]

    def set_state(
        self,
        candidate_id: str,
        state: str,
        *,
        promotion_ref: str = "",
        promotion_run: str = "",
        error: str = "",
    ) -> dict[str, Any]:
        if state not in VALID_STATES:
            raise CoreCandidateQueueError("unknown candidate queue state")
        row = self.get(candidate_id)
        if not row:
            raise CoreCandidateQueueError("candidate is not present in queue")
        current = str(row.get("state", ""))
        if current in TERMINAL_STATES and current != state:
            raise CoreCandidateQueueError("terminal candidate state cannot be changed")
        row["state"] = state
        row["updated_at"] = int(time.time())
        if promotion_ref:
            row["promotion_ref"] = str(promotion_ref)[:512]
        if promotion_run:
            row["promotion_run"] = str(promotion_run)[:512]
        row["error"] = str(error)[:4000]
        self._write_json(self.queue_root / candidate_id / "queue.json", row)
        return {"ok": True, **row}

    def materialize_submission(self, candidate_id: str, destination: Path) -> dict[str, Any]:
        row = self.get(candidate_id)
        if not row:
            raise CoreCandidateQueueError("candidate is not present in queue")
        bundle = self.queue_root / candidate_id
        target = _safe_target(row.get("target"))
        manifest_path = bundle / "candidate.json"
        source_path = bundle / target
        if not manifest_path.is_file() or not source_path.is_file():
            raise CoreCandidateQueueError("queued candidate bundle is incomplete")
        if _sha256(source_path.read_bytes()) != str(row.get("candidate_sha256", "")):
            raise CoreCandidateQueueError("queued candidate bytes failed SHA-256 verification")
        destination = destination.resolve()
        if destination.exists():
            shutil.rmtree(destination)
        (destination / target).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(manifest_path, destination / "candidate.json")
        shutil.copyfile(source_path, destination / target)
        return {
            "ok": True,
            "candidate_id": candidate_id,
            "target": target,
            "destination": str(destination),
            "candidate_sha256": row["candidate_sha256"],
        }

    def status(self) -> dict[str, Any]:
        rows = self.list(self.max_items)
        counts: dict[str, int] = {state: 0 for state in VALID_STATES}
        for row in rows:
            state = str(row.get("state", ""))
            if state in counts:
                counts[state] += 1
        return {"ok": True, "root": str(self.queue_root), "items": len(rows), "states": counts}

    def _trim_if_needed(self) -> None:
        rows = self.list(self.max_items + 50)
        if len(rows) < self.max_items:
            return
        removable = [row for row in reversed(rows) if row.get("state") in TERMINAL_STATES]
        while len(rows) >= self.max_items and removable:
            row = removable.pop(0)
            candidate_id = str(row.get("candidate_id", ""))
            path = self.queue_root / candidate_id
            if path.is_dir():
                shutil.rmtree(path)
            rows = [item for item in rows if item.get("candidate_id") != candidate_id]
        if len(rows) >= self.max_items:
            raise CoreCandidateQueueError("Core candidate queue is full; no terminal item can be evicted")

    @staticmethod
    def _write_json(path: Path, payload: dict[str, Any]) -> None:
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tmp.replace(path)
