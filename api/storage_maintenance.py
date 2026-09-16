from __future__ import annotations

import os
import shutil
import threading
import time
from pathlib import Path
from typing import Any

from api.database import AuroraDatabase


DEFAULT_RETENTION_SECONDS = 14 * 24 * 60 * 60
DEFAULT_MAINTENANCE_INTERVAL_SECONDS = 6 * 60 * 60
DEFAULT_WARN_DATABASE_BYTES = 192 * 1024 * 1024
DEFAULT_MIN_FREE_BYTES = 256 * 1024 * 1024
DEFAULT_WARN_SYNC_CHANGES = 500_000
DEFAULT_WARN_OPEN_CONFLICTS = 10_000
MAINTENANCE_META_KEY = "storage_maintenance.last_run_epoch"


class StorageMaintenance:
    """Bound server storage without deleting durable user/pending state.

    Only terminal authentication artifacts and already-resolved sync conflicts
    are eligible for deletion. Conversation history, sync entities/change history,
    unresolved conflicts, accounts/guests/devices and learning events are never
    pruned here. This intentionally prefers durability over an artificial row cap.
    """

    def __init__(
        self,
        database: AuroraDatabase,
        root: Path,
        *,
        retention_seconds: int = DEFAULT_RETENTION_SECONDS,
        interval_seconds: int = DEFAULT_MAINTENANCE_INTERVAL_SECONDS,
        warn_database_bytes: int = DEFAULT_WARN_DATABASE_BYTES,
        min_free_bytes: int = DEFAULT_MIN_FREE_BYTES,
        warn_sync_changes: int = DEFAULT_WARN_SYNC_CHANGES,
        warn_open_conflicts: int = DEFAULT_WARN_OPEN_CONFLICTS,
    ):
        self.database = database
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.retention_seconds = max(3600, int(retention_seconds))
        self.interval_seconds = max(60, int(interval_seconds))
        self.warn_database_bytes = max(1, int(warn_database_bytes))
        self.min_free_bytes = max(1, int(min_free_bytes))
        self.warn_sync_changes = max(1, int(warn_sync_changes))
        self.warn_open_conflicts = max(1, int(warn_open_conflicts))
        self._lock = threading.Lock()

    @classmethod
    def from_env(cls, database: AuroraDatabase, root: Path) -> "StorageMaintenance":
        def _integer(name: str, default: int) -> int:
            try:
                return int(os.getenv(name, str(default)))
            except ValueError:
                return default

        return cls(
            database,
            root,
            retention_seconds=_integer("AURORAFOX_STORAGE_RETENTION_SECONDS", DEFAULT_RETENTION_SECONDS),
            interval_seconds=_integer(
                "AURORAFOX_STORAGE_MAINTENANCE_INTERVAL_SECONDS",
                DEFAULT_MAINTENANCE_INTERVAL_SECONDS,
            ),
            warn_database_bytes=_integer(
                "AURORAFOX_STORAGE_WARN_DATABASE_BYTES", DEFAULT_WARN_DATABASE_BYTES
            ),
            min_free_bytes=_integer("AURORAFOX_STORAGE_MIN_FREE_BYTES", DEFAULT_MIN_FREE_BYTES),
            warn_sync_changes=_integer("AURORAFOX_STORAGE_WARN_SYNC_CHANGES", DEFAULT_WARN_SYNC_CHANGES),
            warn_open_conflicts=_integer(
                "AURORAFOX_STORAGE_WARN_OPEN_CONFLICTS", DEFAULT_WARN_OPEN_CONFLICTS
            ),
        )

    def prune_safe(self, *, now: int | None = None) -> dict[str, Any]:
        current = int(time.time()) if now is None else int(now)
        cutoff = current - self.retention_seconds
        removed: dict[str, int] = {}
        with self.database.connection(write=True) as connection:
            cursor = connection.execute(
                "DELETE FROM account_tokens WHERE "
                "(expires_at < ? OR (used_at IS NOT NULL AND used_at < ?) OR "
                "(revoked_at IS NOT NULL AND revoked_at < ?))",
                (cutoff, cutoff, cutoff),
            )
            removed["account_tokens"] = max(0, int(cursor.rowcount))

            # Consumed refresh tokens stay until their original expiry so replay
            # detection remains effective for the token's complete validity window.
            cursor = connection.execute(
                "DELETE FROM refresh_tokens WHERE expires_at < ? "
                "OR (revoked_at IS NOT NULL AND revoked_at < ?)",
                (cutoff, cutoff),
            )
            removed["refresh_tokens"] = max(0, int(cursor.rowcount))

            # A session is removable only after it is stale/revoked and there is
            # no still-valid refresh token that could legitimately use it.
            cursor = connection.execute(
                "DELETE FROM auth_sessions AS s WHERE "
                "((s.revoked_at IS NOT NULL AND s.revoked_at < ?) OR s.access_expires_at < ?) "
                "AND NOT EXISTS ("
                "SELECT 1 FROM refresh_tokens r WHERE r.session_id=s.id "
                "AND r.expires_at>=? AND r.revoked_at IS NULL AND r.consumed_at IS NULL"
                ")",
                (cutoff, cutoff, current),
            )
            removed["auth_sessions"] = max(0, int(cursor.rowcount))

            cursor = connection.execute(
                "DELETE FROM sync_conflicts WHERE resolved_at IS NOT NULL AND resolved_at < ?",
                (cutoff,),
            )
            removed["resolved_sync_conflicts"] = max(0, int(cursor.rowcount))

        return {
            "ok": True,
            "cutoff": cutoff,
            "removed": removed,
            "protected": [
                "accounts",
                "guests",
                "devices",
                "conversations",
                "conversation_messages",
                "learning_events",
                "sync_entities",
                "sync_changes",
                "unresolved_sync_conflicts",
            ],
        }

    def maybe_prune(self, *, force: bool = False, now: int | None = None) -> dict[str, Any]:
        current = int(time.time()) if now is None else int(now)
        with self._lock:
            if not force:
                raw_last = self.database.get_meta(MAINTENANCE_META_KEY)
                try:
                    last_run = int(raw_last) if raw_last is not None else 0
                except ValueError:
                    last_run = 0
                elapsed = current - last_run
                if last_run > 0 and elapsed < self.interval_seconds:
                    return {
                        "ok": True,
                        "ran": False,
                        "next_in_seconds": max(1, self.interval_seconds - max(0, elapsed)),
                    }
            result = self.prune_safe(now=current)
            self.database.set_meta(MAINTENANCE_META_KEY, str(current))
            return {"ok": True, "ran": True, **result}

    def status(self) -> dict[str, Any]:
        database_bytes = 0
        for suffix in ("", "-wal", "-shm"):
            path = Path(str(self.database.path) + suffix)
            try:
                database_bytes += path.stat().st_size
            except FileNotFoundError:
                pass

        usage = shutil.disk_usage(self.root)
        with self.database.connection() as connection:
            sync_changes = int(connection.execute("SELECT COUNT(*) FROM sync_changes").fetchone()[0])
            open_conflicts = int(
                connection.execute(
                    "SELECT COUNT(*) FROM sync_conflicts WHERE resolved_at IS NULL"
                ).fetchone()[0]
            )
            pending_learning = int(
                connection.execute("SELECT COUNT(*) FROM learning_events WHERE synced=0").fetchone()[0]
            )

        warnings: list[str] = []
        if database_bytes >= self.warn_database_bytes:
            warnings.append("database_size")
        if sync_changes >= self.warn_sync_changes:
            warnings.append("sync_history")
        if open_conflicts >= self.warn_open_conflicts:
            warnings.append("open_sync_conflicts")
        if pending_learning:
            warnings.append("pending_learning_protected")

        hard_pressure = usage.free < self.min_free_bytes
        if hard_pressure:
            warnings.append("disk_free_critical")
        return {
            "ok": not hard_pressure,
            "pressure": bool(warnings),
            "hard_pressure": hard_pressure,
            "warnings": warnings,
            "database_bytes": database_bytes,
            "disk_free_bytes": int(usage.free),
            "sync_changes": sync_changes,
            "open_sync_conflicts": open_conflicts,
            "pending_learning": pending_learning,
            "retention_seconds": self.retention_seconds,
        }
