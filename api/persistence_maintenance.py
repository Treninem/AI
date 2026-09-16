from __future__ import annotations

import argparse
import json
import os
import shutil
import time
from pathlib import Path
from typing import Any

from api.database import AuroraDatabase


DEFAULT_RETENTION_SECONDS = 7 * 24 * 60 * 60
DEFAULT_MAINTENANCE_INTERVAL_SECONDS = 6 * 60 * 60
DEFAULT_WARN_DATABASE_BYTES = 512 * 1024 * 1024
DEFAULT_BACKUP_MAX_BYTES = 256 * 1024 * 1024
DEFAULT_WARN_SYNC_CHANGES = 1_000_000
DEFAULT_WARN_OPEN_CONFLICTS = 10_000
DEFAULT_MIN_FREE_BYTES = 256 * 1024 * 1024
MAINTENANCE_META_KEY = "persistence_maintenance.last_prune_epoch"


def _env_int(name: str, default: int, *, minimum: int = 1) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError:
        value = default
    return max(minimum, value)


class PersistenceMaintenance:
    """Capacity visibility plus conservative ephemeral-row cleanup.

    Automatic retention is deliberately limited to terminal authentication rows.
    Conversation data, account/guest principals, device records, learning events,
    sync entities, sync change history and all sync conflicts are preserved. Sync
    compaction needs an explicit snapshot/cursor-reset protocol first so a device
    that has been offline for a long time can never silently lose its history.
    """

    def __init__(self, root: Path, *, backup_max_bytes: int | None = None):
        self.root = root.resolve()
        self.database = AuroraDatabase(self.root / "aurorafox.sqlite3")
        configured_database_warning = _env_int(
            "AURORAFOX_DATABASE_WARN_BYTES", DEFAULT_WARN_DATABASE_BYTES
        )
        if backup_max_bytes is None:
            self.backup_max_bytes = _env_int("AURORAFOX_BACKUP_MAX_BYTES", DEFAULT_BACKUP_MAX_BYTES)
        else:
            self.backup_max_bytes = max(1, int(backup_max_bytes))
        # Backups fail closed at their source-size cap. Warn while there is still
        # operating room even when an older deployment configured a looser DB
        # warning. Other durable files can consume the remaining headroom, so 75%
        # of the backup cap is the latest acceptable SQLite-state warning threshold.
        backup_guard_warning = max(1, (self.backup_max_bytes * 3) // 4)
        self.warn_database_bytes = min(configured_database_warning, backup_guard_warning)
        self.warn_sync_changes = _env_int(
            "AURORAFOX_SYNC_CHANGES_WARN", DEFAULT_WARN_SYNC_CHANGES
        )
        self.warn_open_conflicts = _env_int(
            "AURORAFOX_SYNC_CONFLICTS_WARN", DEFAULT_WARN_OPEN_CONFLICTS
        )
        self.min_free_bytes = _env_int(
            "AURORAFOX_STORAGE_MIN_FREE_BYTES", DEFAULT_MIN_FREE_BYTES
        )
        self.maintenance_interval_seconds = _env_int(
            "AURORAFOX_STORAGE_MAINTENANCE_INTERVAL_SECONDS",
            DEFAULT_MAINTENANCE_INTERVAL_SECONDS,
            minimum=60,
        )
        self.retention_seconds = _env_int(
            "AURORAFOX_STORAGE_RETENTION_SECONDS",
            DEFAULT_RETENTION_SECONDS,
            minimum=0,
        )

    @staticmethod
    def _size(path: Path) -> int:
        try:
            return int(path.stat().st_size)
        except OSError:
            return 0

    def status(self) -> dict[str, Any]:
        now = int(time.time())
        db_path = self.database.path
        with self.database.connection() as connection:
            counts = {
                "accounts": int(connection.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]),
                "guests": int(connection.execute("SELECT COUNT(*) FROM guests").fetchone()[0]),
                "devices": int(connection.execute("SELECT COUNT(*) FROM devices").fetchone()[0]),
                "auth_sessions": int(connection.execute("SELECT COUNT(*) FROM auth_sessions").fetchone()[0]),
                "auth_sessions_revoked": int(
                    connection.execute("SELECT COUNT(*) FROM auth_sessions WHERE revoked_at IS NOT NULL").fetchone()[0]
                ),
                "refresh_tokens": int(connection.execute("SELECT COUNT(*) FROM refresh_tokens").fetchone()[0]),
                "refresh_tokens_expired": int(
                    connection.execute("SELECT COUNT(*) FROM refresh_tokens WHERE expires_at < ?", (now,)).fetchone()[0]
                ),
                "account_tokens": int(connection.execute("SELECT COUNT(*) FROM account_tokens").fetchone()[0]),
                "account_tokens_expired": int(
                    connection.execute("SELECT COUNT(*) FROM account_tokens WHERE expires_at < ?", (now,)).fetchone()[0]
                ),
                "sync_entities": int(connection.execute("SELECT COUNT(*) FROM sync_entities").fetchone()[0]),
                "sync_changes": int(connection.execute("SELECT COUNT(*) FROM sync_changes").fetchone()[0]),
                "sync_conflicts_open": int(
                    connection.execute("SELECT COUNT(*) FROM sync_conflicts WHERE resolved_at IS NULL").fetchone()[0]
                ),
                "sync_conflicts_resolved": int(
                    connection.execute("SELECT COUNT(*) FROM sync_conflicts WHERE resolved_at IS NOT NULL").fetchone()[0]
                ),
                "learning_pending": int(
                    connection.execute("SELECT COUNT(*) FROM learning_events WHERE synced=0").fetchone()[0]
                ),
            }
        sizes = {
            "database_bytes": self._size(db_path),
            "wal_bytes": self._size(Path(str(db_path) + "-wal")),
            "shm_bytes": self._size(Path(str(db_path) + "-shm")),
        }
        # Committed pages may still live in WAL until checkpoint. A DB-only size
        # warning can therefore lag behind the materialized SQLite backup size.
        # SHM is coordination metadata and is intentionally not counted as durable
        # SQLite content for the capacity threshold.
        sizes["database_effective_bytes"] = sizes["database_bytes"] + sizes["wal_bytes"]
        try:
            disk_free_bytes = int(shutil.disk_usage(self.root).free)
        except OSError:
            # Capacity inspection is fail-closed when the filesystem cannot be inspected.
            disk_free_bytes = 0
        warnings: list[str] = []
        if sizes["database_effective_bytes"] >= self.warn_database_bytes:
            warnings.append("database_size")
        if counts["sync_changes"] >= self.warn_sync_changes:
            warnings.append("sync_change_history")
        if counts["sync_conflicts_open"] >= self.warn_open_conflicts:
            warnings.append("open_sync_conflicts")
        if counts["learning_pending"]:
            warnings.append("pending_learning_protected")
        hard_pressure = disk_free_bytes < self.min_free_bytes
        if hard_pressure:
            warnings.append("disk_free_critical")
        integrity = self.database.integrity_check()
        return {
            "ok": bool(integrity.get("ok", False)) and not hard_pressure,
            "schema_version": int(integrity.get("schema_version", 0) or 0),
            "counts": counts,
            "sizes": sizes,
            "disk_free_bytes": disk_free_bytes,
            "hard_pressure": hard_pressure,
            "warnings": warnings,
            "attention_required": bool(warnings),
            "capacity_policy": {
                "database_warn_bytes": self.warn_database_bytes,
                "backup_max_source_bytes": self.backup_max_bytes,
                "database_warning_precedes_backup_cap": self.warn_database_bytes < self.backup_max_bytes,
                "database_warning_includes_wal": True,
                "min_free_bytes": self.min_free_bytes,
            },
            "retention_policy": {
                "retention_seconds": self.retention_seconds,
                "maintenance_interval_seconds": self.maintenance_interval_seconds,
                "pending_learning_protected": True,
                "sync_entities_protected": True,
                "sync_changes_auto_pruned": False,
                "sync_conflicts_auto_pruned": False,
                "unresolved_conflicts_protected": True,
                "resolved_conflicts_protected": True,
                "conversation_data_auto_pruned": False,
                "ephemeral_auth_rows_prunable": True,
                "refresh_replay_sentinel_kept_until_expiry": True,
                "session_kept_while_refresh_sentinel_unexpired": True,
            },
        }

    def prune_ephemeral(self, retention_seconds: int = DEFAULT_RETENTION_SECONDS) -> dict[str, Any]:
        retention = max(0, int(retention_seconds))
        now = int(time.time())
        cutoff = now - retention
        with self.database.connection(write=True) as connection:
            account_cursor = connection.execute(
                "DELETE FROM account_tokens WHERE expires_at < ? "
                "OR (used_at IS NOT NULL AND used_at < ?) "
                "OR (revoked_at IS NOT NULL AND revoked_at < ?)",
                (cutoff, cutoff, cutoff),
            )
            # Do not delete merely-consumed refresh rows before expiry: they are
            # still replay sentinels for their original validity window.
            refresh_cursor = connection.execute(
                "DELETE FROM refresh_tokens WHERE expires_at < ? "
                "OR (revoked_at IS NOT NULL AND revoked_at < ? AND expires_at < ?)",
                (cutoff, cutoff, now),
            )
            # auth_sessions is the FK parent of refresh_tokens. Deleting a stale
            # session would cascade-delete an unexpired consumed/revoked refresh
            # row and destroy replay evidence. Keep the parent until *all* refresh
            # rows for it have expired, regardless of consumed/revoked state.
            session_cursor = connection.execute(
                "DELETE FROM auth_sessions WHERE "
                "((revoked_at IS NOT NULL AND revoked_at < ?) OR access_expires_at < ?) "
                "AND NOT EXISTS ("
                "SELECT 1 FROM refresh_tokens r WHERE r.session_id=auth_sessions.id "
                "AND r.expires_at>=?"
                ")",
                (cutoff, cutoff, now),
            )
        return {
            "ok": True,
            "retention_seconds": retention,
            "removed": {
                "account_tokens": max(0, int(account_cursor.rowcount)),
                "refresh_tokens": max(0, int(refresh_cursor.rowcount)),
                "auth_sessions": max(0, int(session_cursor.rowcount)),
            },
            "protected": [
                "accounts",
                "guests",
                "devices",
                "conversations",
                "conversation_messages",
                "learning_events_pending",
                "sync_entities",
                "sync_changes",
                "sync_conflicts_unresolved",
                "sync_conflicts_resolved",
            ],
        }

    def prune_if_due(self, *, force: bool = False) -> dict[str, Any]:
        now = int(time.time())
        if not force:
            raw_last = self.database.get_meta(MAINTENANCE_META_KEY)
            try:
                last_run = int(raw_last) if raw_last is not None else 0
            except ValueError:
                last_run = 0
            elapsed = now - last_run
            if last_run > 0 and elapsed < self.maintenance_interval_seconds:
                return {
                    "ok": True,
                    "ran": False,
                    "next_in_seconds": max(1, self.maintenance_interval_seconds - max(0, elapsed)),
                }
        result = self.prune_ephemeral(self.retention_seconds)
        self.database.set_meta(MAINTENANCE_META_KEY, str(now))
        return {"ok": True, "ran": True, **result}


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect AuroraFox API persistence capacity")
    parser.add_argument("--user-root", required=True, help="AuroraFox API persistence root")
    parser.add_argument("--prune-ephemeral", action="store_true")
    parser.add_argument("--prune-if-due", action="store_true")
    parser.add_argument("--retention-days", type=int, default=7)
    args = parser.parse_args()
    maintenance = PersistenceMaintenance(Path(args.user_root))
    result: dict[str, Any] = {"status": maintenance.status()}
    if args.prune_ephemeral:
        result["prune"] = maintenance.prune_ephemeral(max(0, args.retention_days) * 24 * 60 * 60)
        result["status_after"] = maintenance.status()
    elif args.prune_if_due:
        result["prune"] = maintenance.prune_if_due()
        result["status_after"] = maintenance.status()
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if bool(result["status"].get("ok", False)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
