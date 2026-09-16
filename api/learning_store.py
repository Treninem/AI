from __future__ import annotations

import json
import threading
import time
import uuid
from pathlib import Path
from typing import Any

from api.database import AuroraDatabase, atomic_write_text


class LearningStore:
    LEGACY_MIGRATION_KEY = "migration.learning_events.jsonl.v1"

    def __init__(self, root: Path, max_events: int = 10000):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.path = self.root / "learning_events.jsonl"
        self.max_events = max(1000, max_events)
        self.database = AuroraDatabase(self.root / "aurorafox.sqlite3")
        self._write_lock = threading.RLock()
        self._migrate_legacy_once()

    @staticmethod
    def _row_event(row: Any) -> dict[str, Any]:
        try:
            payload = json.loads(str(row["payload_json"]))
        except Exception:
            payload = {}
        if not isinstance(payload, dict):
            payload = {}
        return {
            "id": str(row["id"]),
            "kind": str(row["kind"]),
            "time": int(row["created_at"]),
            "synced": bool(row["synced"]),
            "payload": payload,
        }

    def _migrate_legacy_once(self) -> None:
        if self.database.get_meta(self.LEGACY_MIGRATION_KEY) is not None:
            return
        imported = 0
        malformed = 0
        lines: list[str] = []
        if self.path.is_file():
            try:
                lines = self.path.read_text(encoding="utf-8").splitlines()
            except Exception:
                lines = []

        parsed: list[tuple[int, dict[str, Any]]] = []
        for sequence, line in enumerate(lines):
            try:
                event = json.loads(line)
            except Exception:
                malformed += 1
                continue
            if not isinstance(event, dict):
                malformed += 1
                continue
            event_id = str(event.get("id", "")).strip()
            kind = str(event.get("kind", "")).strip()
            payload = event.get("payload", {})
            if not event_id or not kind or not isinstance(payload, dict):
                malformed += 1
                continue
            parsed.append((sequence, event))

        # A migration must never turn a retention limit into data loss. Preserve
        # every unsynced item, then spend any remaining history budget on the
        # newest already-synced records.
        pending = [(sequence, event) for sequence, event in parsed if not bool(event.get("synced", False))]
        synced = [(sequence, event) for sequence, event in parsed if bool(event.get("synced", False))]
        synced_budget = max(0, self.max_events - len(pending))
        selected = pending + (synced[-synced_budget:] if synced_budget else [])
        selected.sort(key=lambda item: item[0])

        with self.database.connection(write=True) as connection:
            for _, event in selected:
                before = connection.total_changes
                connection.execute(
                    "INSERT OR IGNORE INTO learning_events(id, kind, created_at, synced, payload_json) "
                    "VALUES(?, ?, ?, ?, ?)",
                    (
                        str(event.get("id", "")).strip(),
                        str(event.get("kind", "")).strip(),
                        int(event.get("time", int(time.time()))),
                        1 if bool(event.get("synced", False)) else 0,
                        json.dumps(event.get("payload", {}), ensure_ascii=False, separators=(",", ":")),
                    ),
                )
                if connection.total_changes > before:
                    imported += 1
            connection.execute(
                "INSERT INTO metadata(key, value, updated_at) VALUES(?, ?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
                (
                    self.LEGACY_MIGRATION_KEY,
                    json.dumps(
                        {
                            "imported": imported,
                            "malformed": malformed,
                            "pending_preserved": len(pending),
                        },
                        separators=(",", ":"),
                    ),
                    int(time.time()),
                ),
            )
        self._rewrite_legacy_mirror()

    def _all_events(self) -> list[dict[str, Any]]:
        with self.database.connection() as connection:
            rows = connection.execute(
                "SELECT id, kind, created_at, synced, payload_json FROM learning_events "
                "ORDER BY created_at, rowid"
            ).fetchall()
        return [self._row_event(row) for row in rows]

    def _events_for_legacy_mirror(self) -> list[dict[str, Any]]:
        """Keep every pending event in the rollback mirror.

        ``max_events`` is a history cap, never a durability cap. If the server is
        offline long enough to accumulate more pending events than the nominal
        limit, all of them remain recoverable and the store reports over-capacity
        until synchronization makes safe compaction possible.
        """

        events = self._all_events()
        pending = [event for event in events if not bool(event.get("synced", False))]
        synced = [event for event in events if bool(event.get("synced", False))]
        synced_budget = max(0, self.max_events - len(pending))
        keep_synced = synced[-synced_budget:] if synced_budget else []
        keep_ids = {str(event.get("id", "")) for event in pending + keep_synced}
        return [event for event in events if str(event.get("id", "")) in keep_ids]

    def _rewrite_legacy_mirror(self) -> None:
        events = self._events_for_legacy_mirror()
        payload = "".join(
            json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n"
            for event in events
        )
        atomic_write_text(self.path, payload, mode=0o600)

    def _append_legacy_mirror(self, event: dict[str, Any]) -> None:
        line = json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("a", encoding="utf-8", newline="\n") as stream:
            stream.write(line)
            stream.flush()
        try:
            if self.path.stat().st_size > 32 * 1024 * 1024:
                self._rewrite_legacy_mirror()
        except OSError:
            pass

    def _compact_synced_history(self, connection: Any) -> int:
        total = int(connection.execute("SELECT COUNT(*) FROM learning_events").fetchone()[0])
        overflow = max(0, total - self.max_events)
        if overflow <= 0:
            return 0
        cursor = connection.execute(
            "DELETE FROM learning_events WHERE id IN ("
            "SELECT id FROM learning_events WHERE synced=1 "
            "ORDER BY created_at, rowid LIMIT ?)",
            (overflow,),
        )
        return max(0, int(cursor.rowcount))

    def append(self, kind: str, payload: dict[str, Any]) -> dict[str, Any]:
        event = {
            "id": uuid.uuid4().hex,
            "kind": kind,
            "time": int(time.time()),
            "synced": False,
            "payload": payload,
        }
        with self._write_lock:
            with self.database.connection(write=True) as connection:
                connection.execute(
                    "INSERT INTO learning_events(id, kind, created_at, synced, payload_json) VALUES(?, ?, ?, 0, ?)",
                    (
                        event["id"],
                        kind,
                        event["time"],
                        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
                    ),
                )
                compacted = self._compact_synced_history(connection) > 0
            if compacted:
                self._rewrite_legacy_mirror()
            else:
                self._append_legacy_mirror(event)
            return event

    def pending(self, limit: int = 100) -> list[dict[str, Any]]:
        with self.database.connection() as connection:
            rows = connection.execute(
                "SELECT id, kind, created_at, synced, payload_json FROM learning_events "
                "WHERE synced=0 ORDER BY created_at, rowid LIMIT ?",
                (max(1, limit),),
            ).fetchall()
        return [self._row_event(row) for row in rows]

    def mark_synced(self, event_ids: set[str]) -> int:
        normalized = sorted({str(value) for value in event_ids if str(value)})
        if not normalized:
            return 0
        placeholders = ",".join("?" for _ in normalized)
        with self._write_lock:
            with self.database.connection(write=True) as connection:
                cursor = connection.execute(
                    f"UPDATE learning_events SET synced=1 WHERE synced=0 AND id IN ({placeholders})",
                    tuple(normalized),
                )
                changed = int(cursor.rowcount)
                compacted = self._compact_synced_history(connection)
            if changed or compacted:
                self._rewrite_legacy_mirror()
            return changed

    def status(self) -> dict[str, Any]:
        with self.database.connection() as connection:
            total = int(connection.execute("SELECT COUNT(*) FROM learning_events").fetchone()[0])
            pending = int(connection.execute("SELECT COUNT(*) FROM learning_events WHERE synced=0").fetchone()[0])
        return {
            "ok": True,
            "total": total,
            "pending": pending,
            "max_events": self.max_events,
            "over_capacity": max(0, total - self.max_events),
            "pending_protected": True,
            "database": str(self.database.path),
        }
