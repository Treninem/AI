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
DEFAULT_WARN_SYNC_CHANGES = 1_000_000
DEFAULT_WARN_OPEN_CONFLICTS = 10_000
DEFAULT_MIN_FREE_BYTES = 256 * 1024 * 1024
MAINTENANCE_META_KEY = "persistence_maintenance.last_prune_epoch"


class PersistenceMaintenance:
    """Capacity visibility plus conservative ephemeral-row cleanup.

    This class never deletes conversations, account/guest principals, current
    sync entities, unresolved conflicts, pending learning events, or other user
    knowledge. Sync change history is intentionally not compacted until a full
    snapshot/cursor-reset protocol exists for long-offline devices.
    """

    def __init__(self, root: Path):
        self.root = root.resolve()
        self.database = AuroraDatabase(self.root / "aurorafox.sqlite3")
        self.warn_database_bytes = max(
            1,
            int(os.getenv("AURORAFOX_DATABASE_WARN_BYTES", str(DEFAULT_WARN_DATABASE_BYTES))),
        )
        self.warn_sync_changes = max(
            1,
            int(os.getenv("AURORAFOX_SYNC_CHANGES_WARN", str(DEFAULT_WARN_SYNC_CHANGES))),
        )
        self.warn_open_conflicts = max(
            1,
            int(os.getenv("AURORAFOX_SYNC_CONFLICTS_WARN", str(DEFAULT_WARN_OPEN_CONFLICTS))),
        )
        self.min_free_bytes = max(
            1,
            int(os.getenv("AURORAFOX_STORAGE_MIN_FREE_BYTES", str(DEFAULT_MIN_FREE_BYTES))),
        )
        self.maintenance_interval_seconds = max(
            60,
            int(
                os.getenv(
                    "AURORAFOX_STORAGE_MAINTENANCE_INTERVAL_SECONDS",
                    str(DEFAULT_MAINTENANCE_INTERVAL_SECONDS),
                )
            ),
        )
        self.retention_seconds = max(
            0,
            int(os.getenv("AURORAFOX_STORAGE_RETENTION_SECONDS", str(DEFAULT_RETENTION_SECONDS))),
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
        try:
            disk_free_bytes = int(shutil.disk_usage(self.root).free)
        except OSError:
            disk_free_bytes = 0
        warnings: list[str] = []
        if sizes["database_bytes"] >= self.warn_database_bytes:
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
            "retention_policy": {
                "retention_seconds": self.retention_seconds,
                "maintenance_interval_seconds": self.maintenance_interval_seconds,
                "pending_learning_protected": True,
                "sync_entities_protected": True,
                "sync_changes_auto_pruned": False,
                "unresolved_conflicts_protected": True,
                "resolved_conflicts_prunable": True,
                "conversation_data_auto_pruned": False,
                "ephemeral_auth_rows_prunable": True,
                "refresh_replay_sentinel_kept_until_expiry": True,
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
            session_cursor = connection.execute(
                "DELETE FROM auth_sessions WHERE "
                "((revoked_at IS NOT NULL AND revoked_at < ?) OR access_expires_at < ?) "
                "AND NOT EXISTS ("
                "SELECT 1 FROM refresh_tokens r WHERE r.session_id=auth_sessions.id "
                "AND r.expires_at>=? AND r.revoked_at IS NULL AND r.consumed_at IS NULL"
                ")",
                (cutoff, cutoff, now),
            )
            conflict_cursor = connection.execute(
                "DELETE FROM sync_conflicts WHERE resolved_at IS NOT NULL AND resolved_at < ?",
                (cutoff,),
            )
        return {
            "ok": True,
            "retention_seconds": retention,
            "removed": {
                "account_tokens": max(0, int(account_cursor.rowcount)),
                "refresh_tokens": max(0, int(refresh_cursor.rowcount)),
                "auth_sessions": max(0, int(session_cursor.rowcount)),
                "resolved_sync_conflicts": max(0, int(conflict_cursor.rowcount)),
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
