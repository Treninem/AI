from __future__ import annotations

import argparse
import json
import os
import time
from pathlib import Path
from typing import Any

from api.database import AuroraDatabase


DEFAULT_RETENTION_SECONDS = 7 * 24 * 60 * 60
DEFAULT_WARN_DATABASE_BYTES = 512 * 1024 * 1024
DEFAULT_WARN_SYNC_CHANGES = 1_000_000
DEFAULT_WARN_OPEN_CONFLICTS = 10_000


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
                "learning_pending": int(
                    connection.execute("SELECT COUNT(*) FROM learning_events WHERE synced=0").fetchone()[0]
                ),
            }
        sizes = {
            "database_bytes": self._size(db_path),
            "wal_bytes": self._size(Path(str(db_path) + "-wal")),
            "shm_bytes": self._size(Path(str(db_path) + "-shm")),
        }
        warnings: list[str] = []
        if sizes["database_bytes"] >= self.warn_database_bytes:
            warnings.append("database_size")
        if counts["sync_changes"] >= self.warn_sync_changes:
            warnings.append("sync_change_history")
        if counts["sync_conflicts_open"] >= self.warn_open_conflicts:
            warnings.append("open_sync_conflicts")
        integrity = self.database.integrity_check()
        return {
            "ok": bool(integrity.get("ok", False)),
            "schema_version": int(integrity.get("schema_version", 0) or 0),
            "counts": counts,
            "sizes": sizes,
            "warnings": warnings,
            "attention_required": bool(warnings),
            "retention_policy": {
                "pending_learning_protected": True,
                "sync_entities_protected": True,
                "sync_changes_auto_pruned": False,
                "unresolved_conflicts_protected": True,
                "conversation_data_auto_pruned": False,
                "ephemeral_auth_rows_prunable": True,
            },
        }

    def prune_ephemeral(self, retention_seconds: int = DEFAULT_RETENTION_SECONDS) -> dict[str, Any]:
        retention = max(0, int(retention_seconds))
        cutoff = int(time.time()) - retention
        with self.database.connection(write=True) as connection:
            account_cursor = connection.execute(
                "DELETE FROM account_tokens WHERE expires_at < ? "
                "OR (used_at IS NOT NULL AND used_at < ?) "
                "OR (revoked_at IS NOT NULL AND revoked_at < ?)",
                (cutoff, cutoff, cutoff),
            )
            refresh_cursor = connection.execute(
                "DELETE FROM refresh_tokens WHERE expires_at < ?",
                (cutoff,),
            )
            session_cursor = connection.execute(
                "DELETE FROM auth_sessions WHERE access_expires_at < ? "
                "AND NOT EXISTS (SELECT 1 FROM refresh_tokens r WHERE r.session_id=auth_sessions.id)",
                (cutoff,),
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
            ],
        }


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect AuroraFox API persistence capacity")
    parser.add_argument("--user-root", required=True, help="AuroraFox API persistence root")
    parser.add_argument("--prune-ephemeral", action="store_true")
    parser.add_argument("--retention-days", type=int, default=7)
    args = parser.parse_args()
    maintenance = PersistenceMaintenance(Path(args.user_root))
    result: dict[str, Any] = {"status": maintenance.status()}
    if args.prune_ephemeral:
        result["prune"] = maintenance.prune_ephemeral(max(0, args.retention_days) * 24 * 60 * 60)
        result["status_after"] = maintenance.status()
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if bool(result["status"].get("ok", False)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
