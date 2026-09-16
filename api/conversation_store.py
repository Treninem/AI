from __future__ import annotations

import hashlib
import json
import threading
import time
from pathlib import Path
from typing import Any

from api.database import AuroraDatabase, atomic_write_text


class ConversationStore:
    LEGACY_MIGRATION_KEY = "migration.conversations.json.v1"

    def __init__(self, root: Path, max_messages: int = 120):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.max_messages = max(20, max_messages)
        self.database = AuroraDatabase(self.root.parent / "aurorafox.sqlite3")
        self._write_lock = threading.RLock()
        self._migrate_legacy_once()

    def _path(self, owner: str, conversation_id: str) -> Path:
        key = hashlib.sha256(f"{owner}:{conversation_id}".encode("utf-8")).hexdigest()
        return self.root / f"{key}.json"

    @staticmethod
    def _default(owner: str, conversation_id: str) -> dict[str, Any]:
        now = int(time.time())
        return {
            "owner": owner,
            "conversation_id": conversation_id,
            "messages": [],
            "created_at": now,
            "updated_at": now,
        }

    def _migrate_legacy_once(self) -> None:
        if self.database.get_meta(self.LEGACY_MIGRATION_KEY) is not None:
            return
        imported_conversations = 0
        imported_messages = 0
        with self.database.connection(write=True) as connection:
            for path in sorted(self.root.glob("*.json")):
                try:
                    data = json.loads(path.read_text(encoding="utf-8"))
                except Exception:
                    continue
                if not isinstance(data, dict) or not isinstance(data.get("messages"), list):
                    continue
                owner = str(data.get("owner", "")).strip()
                conversation_id = str(data.get("conversation_id", "")).strip()
                if not owner or not conversation_id:
                    continue
                exists = connection.execute(
                    "SELECT 1 FROM conversations WHERE owner=? AND conversation_id=?",
                    (owner, conversation_id),
                ).fetchone()
                if exists is not None:
                    continue
                created_at = int(data.get("created_at", int(time.time())))
                updated_at = int(data.get("updated_at", created_at))
                connection.execute(
                    "INSERT INTO conversations(owner, conversation_id, created_at, updated_at) VALUES(?, ?, ?, ?)",
                    (owner, conversation_id, created_at, updated_at),
                )
                imported_conversations += 1
                for item in data.get("messages", [])[-self.max_messages :]:
                    if not isinstance(item, dict):
                        continue
                    role = str(item.get("role", ""))
                    if role not in {"user", "assistant", "system"}:
                        continue
                    metadata = item.get("metadata", {})
                    if not isinstance(metadata, dict):
                        metadata = {}
                    connection.execute(
                        "INSERT INTO conversation_messages(owner, conversation_id, role, content, metadata_json, created_at) "
                        "VALUES(?, ?, ?, ?, ?, ?)",
                        (
                            owner,
                            conversation_id,
                            role,
                            str(item.get("content", "")),
                            json.dumps(metadata, ensure_ascii=False, separators=(",", ":")),
                            int(item.get("time", updated_at)),
                        ),
                    )
                    imported_messages += 1
            connection.execute(
                "INSERT INTO metadata(key, value, updated_at) VALUES(?, ?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
                (
                    self.LEGACY_MIGRATION_KEY,
                    json.dumps(
                        {"conversations": imported_conversations, "messages": imported_messages},
                        separators=(",", ":"),
                    ),
                    int(time.time()),
                ),
            )

    def get(self, owner: str, conversation_id: str) -> dict[str, Any]:
        with self.database.connection() as connection:
            row = connection.execute(
                "SELECT owner, conversation_id, created_at, updated_at FROM conversations "
                "WHERE owner=? AND conversation_id=?",
                (owner, conversation_id),
            ).fetchone()
            if row is None:
                return self._default(owner, conversation_id)
            message_rows = connection.execute(
                "SELECT role, content, metadata_json, created_at FROM conversation_messages "
                "WHERE owner=? AND conversation_id=? ORDER BY id",
                (owner, conversation_id),
            ).fetchall()
        messages: list[dict[str, Any]] = []
        for item in message_rows:
            try:
                metadata = json.loads(str(item["metadata_json"]))
            except Exception:
                metadata = {}
            if not isinstance(metadata, dict):
                metadata = {}
            messages.append(
                {
                    "role": str(item["role"]),
                    "content": str(item["content"]),
                    "metadata": metadata,
                    "time": int(item["created_at"]),
                }
            )
        return {
            "owner": str(row["owner"]),
            "conversation_id": str(row["conversation_id"]),
            "messages": messages,
            "created_at": int(row["created_at"]),
            "updated_at": int(row["updated_at"]),
        }

    def _write_legacy_mirror(self, owner: str, conversation_id: str, data: dict[str, Any] | None = None) -> None:
        payload = data if data is not None else self.get(owner, conversation_id)
        atomic_write_text(
            self._path(owner, conversation_id),
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            mode=0o600,
        )

    def append(
        self,
        owner: str,
        conversation_id: str,
        role: str,
        content: str,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        if role not in {"user", "assistant", "system"}:
            raise ValueError(f"Unsupported conversation role: {role}")
        now = int(time.time())
        safe_metadata = metadata if isinstance(metadata, dict) else {}
        with self._write_lock:
            with self.database.connection(write=True) as connection:
                connection.execute(
                    "INSERT INTO conversations(owner, conversation_id, created_at, updated_at) VALUES(?, ?, ?, ?) "
                    "ON CONFLICT(owner, conversation_id) DO UPDATE SET updated_at=excluded.updated_at",
                    (owner, conversation_id, now, now),
                )
                connection.execute(
                    "INSERT INTO conversation_messages(owner, conversation_id, role, content, metadata_json, created_at) "
                    "VALUES(?, ?, ?, ?, ?, ?)",
                    (
                        owner,
                        conversation_id,
                        role,
                        content,
                        json.dumps(safe_metadata, ensure_ascii=False, separators=(",", ":")),
                        now,
                    ),
                )
                connection.execute(
                    "DELETE FROM conversation_messages WHERE id IN ("
                    "SELECT id FROM conversation_messages WHERE owner=? AND conversation_id=? "
                    "ORDER BY id DESC LIMIT -1 OFFSET ?)",
                    (owner, conversation_id, self.max_messages),
                )
            data = self.get(owner, conversation_id)
            self._write_legacy_mirror(owner, conversation_id, data)
            return data

    def clear(self, owner: str, conversation_id: str) -> bool:
        with self._write_lock:
            with self.database.connection(write=True) as connection:
                cursor = connection.execute(
                    "DELETE FROM conversations WHERE owner=? AND conversation_id=?",
                    (owner, conversation_id),
                )
                changed = cursor.rowcount > 0
            self._path(owner, conversation_id).unlink(missing_ok=True)
            return changed

    def context(self, owner: str, conversation_id: str, limit: int = 24) -> list[dict[str, Any]]:
        with self.database.connection() as connection:
            rows = connection.execute(
                "SELECT role, content FROM conversation_messages WHERE owner=? AND conversation_id=? "
                "ORDER BY id DESC LIMIT ?",
                (owner, conversation_id, max(1, limit)),
            ).fetchall()
        return [
            {"role": str(item["role"]), "content": str(item["content"])}
            for item in reversed(rows)
            if str(item["role"]) in {"user", "assistant", "system"}
        ]
