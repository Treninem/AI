from __future__ import annotations

import hashlib
import json
import secrets
import time
from pathlib import Path
from typing import Any

from api.account_store import AccountError, ConflictError
from api.database import AuroraDatabase


SYNC_ENTITY_TYPES = {
    "memory",
    "knowledge",
    "conversation",
    "project",
    "settings",
    "skill",
    "training_result",
    "version_metadata",
    "sync_metadata",
    "file_metadata",
}
MAX_ENTITY_BYTES = 1024 * 1024


class SyncStore:
    """Incremental per-principal synchronization with conflict preservation.

    The server never accepts user_id as authority: callers pass a principal that
    came from a verified account/guest token. Each mutation is revisioned and
    appended to sync_changes, allowing devices to pull from a durable cursor.
    Stale writes are preserved in sync_conflicts rather than silently winning.
    """

    def __init__(self, root: Path):
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.database = AuroraDatabase(self.root / "aurorafox.sqlite3")

    @staticmethod
    def _now() -> int:
        return int(time.time())

    @staticmethod
    def _principal(principal: dict[str, Any]) -> tuple[str, str, str]:
        kind = str(principal.get("principal_kind", ""))
        principal_id = str(principal.get("principal_id", ""))
        device_id = str(principal.get("device_id", ""))
        if kind not in {"account", "guest"} or not principal_id or not device_id:
            raise AccountError("Verified personal principal required")
        return kind, principal_id, device_id

    @staticmethod
    def _canonical_payload(payload: Any) -> tuple[str, str]:
        if not isinstance(payload, (dict, list, str, int, float, bool)) and payload is not None:
            raise AccountError("Sync payload must be JSON-compatible")
        text = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        if len(text.encode("utf-8")) > MAX_ENTITY_BYTES:
            raise AccountError("Sync entity exceeds size limit")
        return text, hashlib.sha256(text.encode("utf-8")).hexdigest()

    @staticmethod
    def _validate_identity(entity_type: str, entity_id: str) -> tuple[str, str]:
        normalized_type = str(entity_type).strip()
        normalized_id = str(entity_id).strip()
        if normalized_type not in SYNC_ENTITY_TYPES:
            raise AccountError(f"Unsupported sync entity type: {normalized_type}")
        if not normalized_id or len(normalized_id) > 256:
            raise AccountError("Sync entity id must contain 1..256 characters")
        return normalized_type, normalized_id

    @staticmethod
    def _row_entity(row: Any) -> dict[str, Any]:
        try:
            payload = json.loads(str(row["payload_json"]))
        except Exception:
            payload = None
        return {
            "entity_type": str(row["entity_type"]),
            "entity_id": str(row["entity_id"]),
            "revision": int(row["revision"]),
            "payload": payload,
            "checksum": str(row["checksum"]),
            "origin_device_id": str(row["origin_device_id"]),
            "updated_at": int(row["updated_at"]),
            "deleted": bool(row["deleted"]),
        }

    def push(self, principal: dict[str, Any], items: list[dict[str, Any]]) -> dict[str, Any]:
        kind, principal_id, device_id = self._principal(principal)
        if len(items) > 200:
            raise AccountError("A sync push may contain at most 200 entities")
        results: list[dict[str, Any]] = []
        now = self._now()
        with self.database.connection(write=True) as connection:
            for raw in items:
                if not isinstance(raw, dict):
                    raise AccountError("Sync item must be an object")
                entity_type, entity_id = self._validate_identity(
                    str(raw.get("entity_type", "")), str(raw.get("entity_id", ""))
                )
                base_revision = int(raw.get("base_revision", 0))
                if base_revision < 0:
                    raise AccountError("base_revision cannot be negative")
                deleted = bool(raw.get("deleted", False))
                payload_json, checksum = self._canonical_payload(raw.get("payload", {}))
                current = connection.execute(
                    "SELECT * FROM sync_entities WHERE principal_kind=? AND principal_id=? "
                    "AND entity_type=? AND entity_id=?",
                    (kind, principal_id, entity_type, entity_id),
                ).fetchone()

                if current is not None and str(current["checksum"]) == checksum and bool(current["deleted"]) == deleted:
                    results.append({"status": "unchanged", **self._row_entity(current)})
                    continue

                current_revision = int(current["revision"]) if current is not None else 0
                if base_revision != current_revision:
                    conflict_id = secrets.token_hex(16)
                    connection.execute(
                        "INSERT INTO sync_conflicts(id, principal_kind, principal_id, entity_type, entity_id, "
                        "current_revision, incoming_base_revision, incoming_payload_json, incoming_checksum, "
                        "incoming_deleted, origin_device_id, created_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (
                            conflict_id,
                            kind,
                            principal_id,
                            entity_type,
                            entity_id,
                            current_revision,
                            base_revision,
                            payload_json,
                            checksum,
                            1 if deleted else 0,
                            device_id,
                            now,
                        ),
                    )
                    results.append(
                        {
                            "status": "conflict",
                            "conflict_id": conflict_id,
                            "entity_type": entity_type,
                            "entity_id": entity_id,
                            "current_revision": current_revision,
                            "incoming_base_revision": base_revision,
                            "current": self._row_entity(current) if current is not None else None,
                            "incoming": {
                                "payload": json.loads(payload_json),
                                "checksum": checksum,
                                "deleted": deleted,
                                "origin_device_id": device_id,
                            },
                        }
                    )
                    continue

                revision = current_revision + 1
                connection.execute(
                    "INSERT INTO sync_entities(principal_kind, principal_id, entity_type, entity_id, revision, "
                    "payload_json, checksum, origin_device_id, updated_at, deleted) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
                    "ON CONFLICT(principal_kind, principal_id, entity_type, entity_id) DO UPDATE SET "
                    "revision=excluded.revision, payload_json=excluded.payload_json, checksum=excluded.checksum, "
                    "origin_device_id=excluded.origin_device_id, updated_at=excluded.updated_at, deleted=excluded.deleted",
                    (
                        kind,
                        principal_id,
                        entity_type,
                        entity_id,
                        revision,
                        payload_json,
                        checksum,
                        device_id,
                        now,
                        1 if deleted else 0,
                    ),
                )
                cursor = connection.execute(
                    "INSERT INTO sync_changes(principal_kind, principal_id, entity_type, entity_id, revision, "
                    "payload_json, checksum, origin_device_id, updated_at, deleted) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        kind,
                        principal_id,
                        entity_type,
                        entity_id,
                        revision,
                        payload_json,
                        checksum,
                        device_id,
                        now,
                        1 if deleted else 0,
                    ),
                )
                results.append(
                    {
                        "status": "applied",
                        "entity_type": entity_type,
                        "entity_id": entity_id,
                        "revision": revision,
                        "checksum": checksum,
                        "cursor": int(cursor.lastrowid),
                        "updated_at": now,
                        "deleted": deleted,
                    }
                )
        return {"ok": True, "results": results}

    def pull(
        self,
        principal: dict[str, Any],
        *,
        cursor: int = 0,
        limit: int = 200,
    ) -> dict[str, Any]:
        kind, principal_id, _ = self._principal(principal)
        safe_cursor = max(0, int(cursor))
        safe_limit = min(500, max(1, int(limit)))
        with self.database.connection() as connection:
            rows = connection.execute(
                "SELECT seq, entity_type, entity_id, revision, payload_json, checksum, origin_device_id, "
                "updated_at, deleted FROM sync_changes WHERE principal_kind=? AND principal_id=? AND seq>? "
                "ORDER BY seq LIMIT ?",
                (kind, principal_id, safe_cursor, safe_limit),
            ).fetchall()
            max_row = connection.execute(
                "SELECT COALESCE(MAX(seq), 0) FROM sync_changes WHERE principal_kind=? AND principal_id=?",
                (kind, principal_id),
            ).fetchone()
        changes: list[dict[str, Any]] = []
        next_cursor = safe_cursor
        for row in rows:
            next_cursor = max(next_cursor, int(row["seq"]))
            item = self._row_entity(row)
            item["cursor"] = int(row["seq"])
            changes.append(item)
        latest_cursor = int(max_row[0]) if max_row is not None else next_cursor
        return {
            "ok": True,
            "cursor": next_cursor,
            "latest_cursor": latest_cursor,
            "has_more": next_cursor < latest_cursor,
            "changes": changes,
        }

    def conflicts(self, principal: dict[str, Any], limit: int = 100) -> list[dict[str, Any]]:
        kind, principal_id, _ = self._principal(principal)
        with self.database.connection() as connection:
            rows = connection.execute(
                "SELECT id, entity_type, entity_id, current_revision, incoming_base_revision, "
                "incoming_payload_json, incoming_checksum, incoming_deleted, origin_device_id, created_at "
                "FROM sync_conflicts WHERE principal_kind=? AND principal_id=? AND resolved_at IS NULL "
                "ORDER BY created_at, id LIMIT ?",
                (kind, principal_id, min(500, max(1, int(limit)))),
            ).fetchall()
        output: list[dict[str, Any]] = []
        for row in rows:
            try:
                payload = json.loads(str(row["incoming_payload_json"]))
            except Exception:
                payload = None
            output.append(
                {
                    "id": str(row["id"]),
                    "entity_type": str(row["entity_type"]),
                    "entity_id": str(row["entity_id"]),
                    "current_revision": int(row["current_revision"]),
                    "incoming_base_revision": int(row["incoming_base_revision"]),
                    "incoming": {
                        "payload": payload,
                        "checksum": str(row["incoming_checksum"]),
                        "deleted": bool(row["incoming_deleted"]),
                        "origin_device_id": str(row["origin_device_id"]),
                    },
                    "created_at": int(row["created_at"]),
                }
            )
        return output

    def resolve_conflict(
        self,
        principal: dict[str, Any],
        conflict_id: str,
        *,
        expected_revision: int,
        payload: Any,
        deleted: bool = False,
    ) -> dict[str, Any]:
        kind, principal_id, device_id = self._principal(principal)
        payload_json, checksum = self._canonical_payload(payload)
        now = self._now()
        with self.database.connection(write=True) as connection:
            conflict = connection.execute(
                "SELECT * FROM sync_conflicts WHERE id=? AND principal_kind=? AND principal_id=? AND resolved_at IS NULL",
                (conflict_id, kind, principal_id),
            ).fetchone()
            if conflict is None:
                raise ConflictError("Sync conflict not found or already resolved")
            current = connection.execute(
                "SELECT * FROM sync_entities WHERE principal_kind=? AND principal_id=? AND entity_type=? AND entity_id=?",
                (kind, principal_id, str(conflict["entity_type"]), str(conflict["entity_id"])),
            ).fetchone()
            current_revision = int(current["revision"]) if current is not None else 0
            if current_revision != int(expected_revision):
                raise ConflictError("Sync entity changed again; refresh conflict state before resolving")
            revision = current_revision + 1
            connection.execute(
                "INSERT INTO sync_entities(principal_kind, principal_id, entity_type, entity_id, revision, "
                "payload_json, checksum, origin_device_id, updated_at, deleted) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
                "ON CONFLICT(principal_kind, principal_id, entity_type, entity_id) DO UPDATE SET "
                "revision=excluded.revision, payload_json=excluded.payload_json, checksum=excluded.checksum, "
                "origin_device_id=excluded.origin_device_id, updated_at=excluded.updated_at, deleted=excluded.deleted",
                (
                    kind,
                    principal_id,
                    str(conflict["entity_type"]),
                    str(conflict["entity_id"]),
                    revision,
                    payload_json,
                    checksum,
                    device_id,
                    now,
                    1 if deleted else 0,
                ),
            )
            cursor = connection.execute(
                "INSERT INTO sync_changes(principal_kind, principal_id, entity_type, entity_id, revision, "
                "payload_json, checksum, origin_device_id, updated_at, deleted) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    kind,
                    principal_id,
                    str(conflict["entity_type"]),
                    str(conflict["entity_id"]),
                    revision,
                    payload_json,
                    checksum,
                    device_id,
                    now,
                    1 if deleted else 0,
                ),
            )
            connection.execute(
                "UPDATE sync_conflicts SET resolved_at=?, resolution_revision=? WHERE id=?",
                (now, revision, conflict_id),
            )
        return {
            "ok": True,
            "conflict_id": conflict_id,
            "entity_type": str(conflict["entity_type"]),
            "entity_id": str(conflict["entity_id"]),
            "revision": revision,
            "checksum": checksum,
            "cursor": int(cursor.lastrowid),
            "deleted": deleted,
        }

    @staticmethod
    def _conversation_target_id(connection, account_owner: str, guest_id: str, original_id: str) -> str:
        exists = connection.execute(
            "SELECT 1 FROM conversations WHERE owner=? AND conversation_id=?",
            (account_owner, original_id),
        ).fetchone()
        if exists is None:
            return original_id
        prefix = f"guest-{guest_id[:8]}-"
        base = (prefix + original_id)[:240]
        candidate = base
        index = 1
        while connection.execute(
            "SELECT 1 FROM conversations WHERE owner=? AND conversation_id=?",
            (account_owner, candidate),
        ).fetchone() is not None:
            suffix = f"-{index}"
            candidate = base[: 256 - len(suffix)] + suffix
            index += 1
        return candidate

    def migrate_guest_to_account(
        self,
        guest_principal: dict[str, Any],
        account_principal: dict[str, Any],
    ) -> dict[str, Any]:
        guest_kind, guest_id, guest_device_id = self._principal(guest_principal)
        account_kind, account_id, account_device_id = self._principal(account_principal)
        if guest_kind != "guest" or account_kind != "account":
            raise AccountError("Guest-to-account migration requires one verified guest and one verified account")
        guest_owner = f"guest:{guest_id}"
        account_owner = f"account:{account_id}"
        now = self._now()
        moved_conversations = 0
        renamed_conversations = 0
        moved_entities = 0
        duplicate_entities = 0
        conflict_entities = 0

        with self.database.connection(write=True) as connection:
            guest = connection.execute(
                "SELECT id, migrated_to_account, revoked_at FROM guests WHERE id=?",
                (guest_id,),
            ).fetchone()
            account = connection.execute(
                "SELECT id, disabled_at FROM accounts WHERE id=?",
                (account_id,),
            ).fetchone()
            if guest is None or guest["revoked_at"] is not None or guest["migrated_to_account"] is not None:
                raise AccountError("Guest identity is not available for migration")
            if account is None or account["disabled_at"] is not None:
                raise AccountError("Account is not available for migration")

            conversation_rows = connection.execute(
                "SELECT conversation_id, created_at, updated_at FROM conversations WHERE owner=? ORDER BY created_at, conversation_id",
                (guest_owner,),
            ).fetchall()
            for conversation in conversation_rows:
                original_id = str(conversation["conversation_id"])
                target_id = self._conversation_target_id(connection, account_owner, guest_id, original_id)
                if target_id != original_id:
                    renamed_conversations += 1
                connection.execute(
                    "INSERT INTO conversations(owner, conversation_id, created_at, updated_at) VALUES(?, ?, ?, ?)",
                    (
                        account_owner,
                        target_id,
                        int(conversation["created_at"]),
                        int(conversation["updated_at"]),
                    ),
                )
                connection.execute(
                    "INSERT INTO conversation_messages(owner, conversation_id, role, content, metadata_json, created_at) "
                    "SELECT ?, ?, role, content, metadata_json, created_at FROM conversation_messages "
                    "WHERE owner=? AND conversation_id=? ORDER BY id",
                    (account_owner, target_id, guest_owner, original_id),
                )
                connection.execute(
                    "DELETE FROM conversations WHERE owner=? AND conversation_id=?",
                    (guest_owner, original_id),
                )
                moved_conversations += 1

            entities = connection.execute(
                "SELECT * FROM sync_entities WHERE principal_kind='guest' AND principal_id=? "
                "ORDER BY entity_type, entity_id",
                (guest_id,),
            ).fetchall()
            for entity in entities:
                entity_type = str(entity["entity_type"])
                entity_id = str(entity["entity_id"])
                current = connection.execute(
                    "SELECT * FROM sync_entities WHERE principal_kind='account' AND principal_id=? "
                    "AND entity_type=? AND entity_id=?",
                    (account_id, entity_type, entity_id),
                ).fetchone()
                if current is None:
                    connection.execute(
                        "INSERT INTO sync_entities(principal_kind, principal_id, entity_type, entity_id, revision, "
                        "payload_json, checksum, origin_device_id, updated_at, deleted) VALUES('account', ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (
                            account_id,
                            entity_type,
                            entity_id,
                            int(entity["revision"]),
                            str(entity["payload_json"]),
                            str(entity["checksum"]),
                            account_device_id,
                            max(now, int(entity["updated_at"])),
                            int(entity["deleted"]),
                        ),
                    )
                    connection.execute(
                        "INSERT INTO sync_changes(principal_kind, principal_id, entity_type, entity_id, revision, "
                        "payload_json, checksum, origin_device_id, updated_at, deleted) VALUES('account', ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (
                            account_id,
                            entity_type,
                            entity_id,
                            int(entity["revision"]),
                            str(entity["payload_json"]),
                            str(entity["checksum"]),
                            account_device_id,
                            max(now, int(entity["updated_at"])),
                            int(entity["deleted"]),
                        ),
                    )
                    moved_entities += 1
                elif str(current["checksum"]) == str(entity["checksum"]) and int(current["deleted"]) == int(entity["deleted"]):
                    duplicate_entities += 1
                else:
                    connection.execute(
                        "INSERT INTO sync_conflicts(id, principal_kind, principal_id, entity_type, entity_id, "
                        "current_revision, incoming_base_revision, incoming_payload_json, incoming_checksum, "
                        "incoming_deleted, origin_device_id, created_at) VALUES(?, 'account', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (
                            secrets.token_hex(16),
                            account_id,
                            entity_type,
                            entity_id,
                            int(current["revision"]),
                            int(entity["revision"]),
                            str(entity["payload_json"]),
                            str(entity["checksum"]),
                            int(entity["deleted"]),
                            guest_device_id,
                            now,
                        ),
                    )
                    conflict_entities += 1
                connection.execute(
                    "DELETE FROM sync_entities WHERE principal_kind='guest' AND principal_id=? AND entity_type=? AND entity_id=?",
                    (guest_id, entity_type, entity_id),
                )

            connection.execute(
                "UPDATE guests SET migrated_to_account=?, revoked_at=?, updated_at=? WHERE id=?",
                (account_id, now, now, guest_id),
            )
            connection.execute(
                "UPDATE devices SET revoked_at=COALESCE(revoked_at, ?) WHERE guest_id=?",
                (now, guest_id),
            )

        return {
            "ok": True,
            "guest_id": guest_id,
            "account_id": account_id,
            "moved_conversations": moved_conversations,
            "renamed_conversations": renamed_conversations,
            "moved_entities": moved_entities,
            "duplicate_entities": duplicate_entities,
            "conflict_entities": conflict_entities,
        }
