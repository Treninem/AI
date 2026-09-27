from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from api.auth import KeyStore, allows

CONTRACT = "aurorafox.impuls.community.v1"
SOURCE = "impuls_anonymous"
ALLOWED_KINDS = {"dialogue_pattern", "moderation_feedback", "topic_trend"}
ACK_DISPOSITIONS = {"accepted", "rejected", "quarantined"}
ACK_REASONS = {
    "curated",
    "duplicate",
    "low_quality",
    "privacy_risk",
    "invalid_schema",
    "insufficient_diversity",
    "unverified_topic",
    "spam_or_advertising",
    "unsafe_style",
}
PROHIBITED_FIELD_NAMES = {
    "chat_id",
    "user_id",
    "message_id",
    "telegram_id",
    "username",
    "first_name",
    "last_name",
    "phone",
    "email",
    "address",
    "coordinates",
    "latitude",
    "longitude",
    "invite_link",
    "token",
    "password",
    "secret",
    "raw_text",
    "raw_message",
    "raw_messages",
    "private_chat",
    "conversation_id",
    "session_id",
}

_EMAIL_RE = re.compile(r"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b")
_PHONE_RE = re.compile(r"(?<!\d)(?:\+?\d[\s().-]*){10,15}(?!\d)")
_HANDLE_RE = re.compile(r"(?<!\w)@[A-Za-z0-9_]{4,32}\b")
_URL_RE = re.compile(r"(?i)\b(?:https?://|www\.|t\.me/|telegram\.me/)\S+")
_LONG_DIGITS_RE = re.compile(r"(?<!\d)\d{12,19}(?!\d)")
_SECRET_RE = re.compile(
    r"(?i)\b(?:bearer\s+[A-Za-z0-9._~+/=-]{16,}|(?:api[_-]?key|token|password|secret)\s*[:=]\s*\S{8,})"
)


def _clean_text(value: str, *, limit: int) -> str:
    clean = " ".join(str(value or "").replace("\x00", " ").split()).strip()
    return clean[:limit]


def _has_personal_or_secret_data(value: str) -> bool:
    text = str(value or "")
    return any(pattern.search(text) is not None for pattern in (_EMAIL_RE, _PHONE_RE, _HANDLE_RE, _URL_RE, _LONG_DIGITS_RE, _SECRET_RE))


def _walk_keys(value: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(value, dict):
        for key, item in value.items():
            found.add(str(key).strip().lower())
            found.update(_walk_keys(item))
    elif isinstance(value, list):
        for item in value:
            found.update(_walk_keys(item))
    return found


class CommunityLabels(BaseModel):
    model_config = ConfigDict(extra="forbid")

    intent: str = Field(default="", max_length=80)
    style: str = Field(default="", max_length=80)
    moderation_category: str = Field(default="", max_length=80)
    understand_only: bool = False
    spam: bool = False
    advertising: bool = False
    pii_detected: bool = False
    human_confirmed: bool = False
    requires_external_verification: bool = False

    @field_validator("intent", "style", "moderation_category")
    @classmethod
    def clean_labels(cls, value: str) -> str:
        return _clean_text(value, limit=80)


class CommunityEventRequest(BaseModel):
    """Strict anonymous contract for community-derived Evolution observations.

    Raw Telegram messages, identities, chat/session identifiers and arbitrary
    metadata are deliberately not representable. ImPULS must transform source
    traffic into an abstract pattern before crossing the network boundary.
    """

    model_config = ConfigDict(extra="forbid")

    schema: Literal[CONTRACT] = CONTRACT
    source: Literal[SOURCE] = SOURCE
    kind: Literal["dialogue_pattern", "moderation_feedback", "topic_trend"]
    language: str = Field(default="ru", min_length=2, max_length=16)
    topic: str = Field(default="", max_length=160)
    pattern: str = Field(default="", max_length=600)
    features: list[str] = Field(default_factory=list, max_length=16)
    labels: CommunityLabels = Field(default_factory=CommunityLabels)
    quality: float = Field(default=0.0, ge=0.0, le=1.0)
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    diversity_bucket: int = Field(default=0, ge=0, le=1000)
    observations: int = Field(default=1, ge=1, le=1_000_000)

    @field_validator("language")
    @classmethod
    def clean_language(cls, value: str) -> str:
        return _clean_text(value.lower(), limit=16)

    @field_validator("topic")
    @classmethod
    def clean_topic(cls, value: str) -> str:
        return _clean_text(value, limit=160)

    @field_validator("pattern")
    @classmethod
    def clean_pattern(cls, value: str) -> str:
        return _clean_text(value, limit=600)

    @field_validator("features")
    @classmethod
    def clean_features(cls, values: list[str]) -> list[str]:
        out: list[str] = []
        seen: set[str] = set()
        for raw in values:
            item = _clean_text(raw, limit=80).lower()
            if item and item not in seen:
                out.append(item)
                seen.add(item)
        return out[:16]

    @model_validator(mode="after")
    def enforce_privacy_and_semantics(self) -> "CommunityEventRequest":
        payload = self.model_dump()
        prohibited = sorted(_walk_keys(payload) & PROHIBITED_FIELD_NAMES)
        if prohibited:
            raise ValueError("prohibited personal fields: " + ", ".join(prohibited))

        inspect = [self.topic, self.pattern, *self.features]
        inspect.extend([self.labels.intent, self.labels.style, self.labels.moderation_category])
        if any(_has_personal_or_secret_data(value) for value in inspect if value):
            raise ValueError("event contains possible personal, contact, URL, payment or secret data")
        if self.labels.pii_detected:
            raise ValueError("events marked as containing PII cannot enter community learning")

        if self.kind == "dialogue_pattern":
            if not self.pattern:
                raise ValueError("dialogue_pattern requires an abstract pattern")
            if self.labels.spam or self.labels.advertising:
                raise ValueError("spam/advertising cannot be learned as desired dialogue")
        elif self.kind == "moderation_feedback":
            if not self.features and not self.labels.moderation_category:
                raise ValueError("moderation_feedback requires abstract features or category")
        elif self.kind == "topic_trend":
            if not self.topic:
                raise ValueError("topic_trend requires a normalized topic")
            if not self.labels.requires_external_verification:
                raise ValueError("topic_trend must require external verification")
        return self


class CommunityAckRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    event_ids: list[str] = Field(min_length=1, max_length=200)
    disposition: Literal["accepted", "rejected", "quarantined"]
    reason: str = Field(default="curated", min_length=1, max_length=64)

    @field_validator("event_ids")
    @classmethod
    def validate_ids(cls, values: list[str]) -> list[str]:
        out: list[str] = []
        for value in values:
            item = str(value).strip().lower()
            if not re.fullmatch(r"[0-9a-f]{32}", item):
                raise ValueError("event_ids must be 32 lowercase hex characters")
            if item not in out:
                out.append(item)
        return out

    @field_validator("reason")
    @classmethod
    def validate_reason(cls, value: str) -> str:
        clean = _clean_text(value, limit=64).lower()
        if clean not in ACK_REASONS:
            raise ValueError("unsupported acknowledgement reason")
        return clean


class CommunityLearningStore:
    """Small durable VPS mailbox for already-sanitized community observations.

    This store is intentionally separate from personal Memory/Knowledge and from
    the generic LearningSynchronizer queue. An ACK means the owner PC has
    classified the event; it never means Stable Core or model weights changed.
    """

    def __init__(self, root: Path, *, max_terminal_events: int = 10_000):
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.path = self.root / "community_learning.sqlite3"
        self.max_terminal_events = max(1000, int(max_terminal_events))
        self._lock = threading.RLock()
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=30.0, isolation_level=None)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA synchronous=FULL")
        connection.execute("PRAGMA busy_timeout=30000")
        return connection

    def _ensure_schema(self) -> None:
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS community_events (
                    id TEXT PRIMARY KEY,
                    source TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    status TEXT NOT NULL CHECK(status IN ('pending','leased','accepted','rejected','quarantined')),
                    lease_until INTEGER NOT NULL DEFAULT 0,
                    delivery_count INTEGER NOT NULL DEFAULT 0,
                    payload_sha256 TEXT NOT NULL UNIQUE,
                    payload_json TEXT NOT NULL,
                    ack_reason TEXT NOT NULL DEFAULT '',
                    acked_at INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX IF NOT EXISTS idx_community_pull
                    ON community_events(status, lease_until, created_at, id);
                CREATE INDEX IF NOT EXISTS idx_community_ack
                    ON community_events(acked_at, status);
                """
            )

    @staticmethod
    def _canonical_payload(event: CommunityEventRequest) -> tuple[str, str]:
        payload_json = json.dumps(event.model_dump(), ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        return payload_json, hashlib.sha256(payload_json.encode("utf-8")).hexdigest()

    def append(self, event: CommunityEventRequest) -> dict[str, Any]:
        payload_json, digest = self._canonical_payload(event)
        event_id = uuid.uuid4().hex
        now = int(time.time())
        with self._lock, self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            existing = connection.execute(
                "SELECT id, status FROM community_events WHERE payload_sha256=?", (digest,)
            ).fetchone()
            if existing is not None:
                connection.commit()
                return {"id": str(existing["id"]), "duplicate": True, "status": str(existing["status"])}
            connection.execute(
                "INSERT INTO community_events(id, source, kind, created_at, status, payload_sha256, payload_json) "
                "VALUES(?, ?, ?, ?, 'pending', ?, ?)",
                (event_id, event.source, event.kind, now, digest, payload_json),
            )
            connection.commit()
        return {"id": event_id, "duplicate": False, "status": "pending"}

    def pull(self, limit: int = 100, lease_seconds: int = 300) -> list[dict[str, Any]]:
        now = int(time.time())
        lease_until = now + max(30, min(int(lease_seconds), 1800))
        bounded_limit = max(1, min(int(limit), 200))
        with self._lock, self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            rows = connection.execute(
                "SELECT id, kind, created_at, delivery_count, payload_json "
                "FROM community_events "
                "WHERE status='pending' OR (status='leased' AND lease_until<=?) "
                "ORDER BY created_at, id LIMIT ?",
                (now, bounded_limit),
            ).fetchall()
            ids = [str(row["id"]) for row in rows]
            if ids:
                placeholders = ",".join("?" for _ in ids)
                connection.execute(
                    f"UPDATE community_events SET status='leased', lease_until=?, delivery_count=delivery_count+1 "
                    f"WHERE id IN ({placeholders})",
                    (lease_until, *ids),
                )
            connection.commit()

        out: list[dict[str, Any]] = []
        for row in rows:
            try:
                payload = json.loads(str(row["payload_json"]))
            except Exception:
                payload = {}
            out.append(
                {
                    "id": str(row["id"]),
                    "kind": str(row["kind"]),
                    "created_at": int(row["created_at"]),
                    "delivery_count": int(row["delivery_count"]) + 1,
                    "lease_until": lease_until,
                    "payload": payload if isinstance(payload, dict) else {},
                }
            )
        return out

    def ack(self, event_ids: list[str], disposition: str, reason: str) -> int:
        if disposition not in ACK_DISPOSITIONS:
            raise ValueError("unsupported disposition")
        now = int(time.time())
        normalized = list(dict.fromkeys(str(value).strip().lower() for value in event_ids if str(value).strip()))
        if not normalized:
            return 0
        placeholders = ",".join("?" for _ in normalized)
        with self._lock, self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                f"UPDATE community_events SET status=?, lease_until=0, ack_reason=?, acked_at=? "
                f"WHERE id IN ({placeholders}) AND status IN ('pending','leased')",
                (disposition, reason, now, *normalized),
            )
            changed = max(0, int(cursor.rowcount))
            self._compact_terminal(connection)
            connection.commit()
        return changed

    def _compact_terminal(self, connection: sqlite3.Connection) -> int:
        terminal = int(
            connection.execute(
                "SELECT COUNT(*) FROM community_events WHERE status IN ('accepted','rejected','quarantined')"
            ).fetchone()[0]
        )
        overflow = max(0, terminal - self.max_terminal_events)
        if not overflow:
            return 0
        cursor = connection.execute(
            "DELETE FROM community_events WHERE id IN ("
            "SELECT id FROM community_events WHERE status IN ('accepted','rejected','quarantined') "
            "ORDER BY acked_at, created_at, id LIMIT ?)",
            (overflow,),
        )
        return max(0, int(cursor.rowcount))

    def status(self) -> dict[str, Any]:
        now = int(time.time())
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT status, COUNT(*) AS n FROM community_events GROUP BY status"
            ).fetchall()
            expired_leases = int(
                connection.execute(
                    "SELECT COUNT(*) FROM community_events WHERE status='leased' AND lease_until<=?", (now,)
                ).fetchone()[0]
            )
        counts = {str(row["status"]): int(row["n"]) for row in rows}
        return {
            "ok": True,
            "contract": CONTRACT,
            "pending": counts.get("pending", 0),
            "leased": counts.get("leased", 0),
            "accepted": counts.get("accepted", 0),
            "rejected": counts.get("rejected", 0),
            "quarantined": counts.get("quarantined", 0),
            "expired_leases": expired_leases,
            "personal_data_allowed": False,
            "stable_core_promotion": False,
            "weight_training": False,
        }


def create_community_learning_router(root: Path, keys: KeyStore) -> APIRouter:
    store = CommunityLearningStore(root / "community_learning")
    router = APIRouter(tags=["evolution-community-learning"])

    def auth(authorization: str = Header(default="")) -> dict[str, Any]:
        if not authorization.startswith("Bearer "):
            raise HTTPException(401, "Missing AuroraFox bearer token")
        record = keys.verify(authorization[7:].strip())
        if record is None:
            raise HTTPException(401, "Invalid or revoked AuroraFox bearer token")
        return record

    @router.post("/v1/evolution/community/events")
    def ingest(req: CommunityEventRequest, record: dict[str, Any] = Depends(auth)) -> dict[str, Any]:
        if not allows(record, "memory.write"):
            raise HTTPException(403, "Bearer principal does not have scope: memory.write")
        result = store.append(req)
        return {"ok": True, "contract": CONTRACT, **result}

    @router.get("/v1/evolution/community/events/pull")
    def pull(
        limit: int = Query(default=100, ge=1, le=200),
        lease_seconds: int = Query(default=300, ge=30, le=1800),
        record: dict[str, Any] = Depends(auth),
    ) -> dict[str, Any]:
        if not allows(record, "memory.read"):
            raise HTTPException(403, "Bearer principal does not have scope: memory.read")
        events = store.pull(limit=limit, lease_seconds=lease_seconds)
        return {"ok": True, "contract": CONTRACT, "events": events}

    @router.post("/v1/evolution/community/events/ack")
    def ack(req: CommunityAckRequest, record: dict[str, Any] = Depends(auth)) -> dict[str, Any]:
        if not allows(record, "memory.read"):
            raise HTTPException(403, "Bearer principal does not have scope: memory.read")
        changed = store.ack(req.event_ids, req.disposition, req.reason)
        return {"ok": True, "acked": changed, "disposition": req.disposition, "reason": req.reason}

    @router.get("/v1/evolution/community/status")
    def status(record: dict[str, Any] = Depends(auth)) -> dict[str, Any]:
        if not allows(record, "memory.read"):
            raise HTTPException(403, "Bearer principal does not have scope: memory.read")
        return store.status()

    return router
