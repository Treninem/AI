from __future__ import annotations

import argparse
import json
import os
import sqlite3
import threading
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator


SCHEMA_VERSION = 3


class AuroraDatabase:
    """Small, dependency-free transactional store for the AuroraFox API.

    A connection is opened per operation so FastAPI worker threads do not share
    sqlite3 connection objects. WAL + busy_timeout allow concurrent readers and
    short serialized writes while the existing BackupService can take an online
    SQLite snapshot safely.
    """

    def __init__(self, path: Path):
        self.path = path.resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=30.0, isolation_level=None)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys=ON")
        connection.execute("PRAGMA busy_timeout=30000")
        connection.execute("PRAGMA synchronous=FULL")
        return connection

    @contextmanager
    def connection(self, *, write: bool = False) -> Iterator[sqlite3.Connection]:
        connection = self._connect()
        try:
            if write:
                connection.execute("BEGIN IMMEDIATE")
            yield connection
            if write:
                connection.commit()
        except Exception:
            if write:
                connection.rollback()
            raise
        finally:
            connection.close()

    def _ensure_schema(self) -> None:
        with self._connect() as connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute("PRAGMA foreign_keys=ON")
            connection.execute("PRAGMA busy_timeout=30000")
            current = int(connection.execute("PRAGMA user_version").fetchone()[0])
            if current > SCHEMA_VERSION:
                raise RuntimeError(
                    f"AuroraFox database schema {current} is newer than supported {SCHEMA_VERSION}"
                )
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS metadata (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS api_keys (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    token_hash TEXT NOT NULL UNIQUE,
                    scopes_json TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    revoked INTEGER NOT NULL DEFAULT 0 CHECK (revoked IN (0, 1))
                );
                CREATE INDEX IF NOT EXISTS idx_api_keys_token_active
                    ON api_keys(token_hash, revoked);

                CREATE TABLE IF NOT EXISTS conversations (
                    owner TEXT NOT NULL,
                    conversation_id TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY(owner, conversation_id)
                );

                CREATE TABLE IF NOT EXISTS conversation_messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    owner TEXT NOT NULL,
                    conversation_id TEXT NOT NULL,
                    role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
                    content TEXT NOT NULL,
                    metadata_json TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    FOREIGN KEY(owner, conversation_id)
                        REFERENCES conversations(owner, conversation_id)
                        ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS idx_messages_conversation
                    ON conversation_messages(owner, conversation_id, id);

                CREATE TABLE IF NOT EXISTS learning_events (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    synced INTEGER NOT NULL DEFAULT 0 CHECK (synced IN (0, 1)),
                    payload_json TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_learning_pending
                    ON learning_events(synced, created_at, id);

                CREATE TABLE IF NOT EXISTS accounts (
                    id TEXT PRIMARY KEY,
                    email_norm TEXT NOT NULL UNIQUE,
                    display_name TEXT NOT NULL,
                    password_salt TEXT NOT NULL,
                    password_hash TEXT NOT NULL,
                    password_params_json TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    email_verified_at INTEGER,
                    disabled_at INTEGER
                );
                CREATE INDEX IF NOT EXISTS idx_accounts_email_active
                    ON accounts(email_norm, disabled_at);

                CREATE TABLE IF NOT EXISTS guests (
                    id TEXT PRIMARY KEY,
                    token_hash TEXT NOT NULL UNIQUE,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    migrated_to_account TEXT,
                    revoked_at INTEGER,
                    FOREIGN KEY(migrated_to_account) REFERENCES accounts(id)
                );
                CREATE INDEX IF NOT EXISTS idx_guests_token_active
                    ON guests(token_hash, revoked_at);

                CREATE TABLE IF NOT EXISTS devices (
                    id TEXT PRIMARY KEY,
                    account_id TEXT,
                    guest_id TEXT,
                    name TEXT NOT NULL,
                    platform TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    last_seen_at INTEGER NOT NULL,
                    revoked_at INTEGER,
                    CHECK ((account_id IS NOT NULL AND guest_id IS NULL) OR
                           (account_id IS NULL AND guest_id IS NOT NULL)),
                    FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE,
                    FOREIGN KEY(guest_id) REFERENCES guests(id) ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS idx_devices_account_active
                    ON devices(account_id, revoked_at, last_seen_at);
                CREATE INDEX IF NOT EXISTS idx_devices_guest_active
                    ON devices(guest_id, revoked_at, last_seen_at);

                CREATE TABLE IF NOT EXISTS auth_sessions (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    family_id TEXT NOT NULL,
                    access_hash TEXT NOT NULL UNIQUE,
                    access_expires_at INTEGER NOT NULL,
                    created_at INTEGER NOT NULL,
                    last_seen_at INTEGER NOT NULL,
                    revoked_at INTEGER,
                    FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE,
                    FOREIGN KEY(device_id) REFERENCES devices(id) ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS idx_auth_sessions_access_active
                    ON auth_sessions(access_hash, revoked_at, access_expires_at);
                CREATE INDEX IF NOT EXISTS idx_auth_sessions_account
                    ON auth_sessions(account_id, revoked_at, last_seen_at);
                CREATE INDEX IF NOT EXISTS idx_auth_sessions_family
                    ON auth_sessions(family_id, revoked_at);

                CREATE TABLE IF NOT EXISTS refresh_tokens (
                    id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    family_id TEXT NOT NULL,
                    token_hash TEXT NOT NULL UNIQUE,
                    generation INTEGER NOT NULL,
                    created_at INTEGER NOT NULL,
                    expires_at INTEGER NOT NULL,
                    consumed_at INTEGER,
                    revoked_at INTEGER,
                    FOREIGN KEY(session_id) REFERENCES auth_sessions(id) ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS idx_refresh_tokens_lookup
                    ON refresh_tokens(token_hash, expires_at);
                CREATE INDEX IF NOT EXISTS idx_refresh_tokens_family
                    ON refresh_tokens(family_id, generation);

                CREATE TABLE IF NOT EXISTS account_tokens (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    purpose TEXT NOT NULL CHECK (purpose IN ('verify_email', 'reset_password')),
                    token_hash TEXT NOT NULL UNIQUE,
                    created_at INTEGER NOT NULL,
                    expires_at INTEGER NOT NULL,
                    used_at INTEGER,
                    revoked_at INTEGER,
                    FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS idx_account_tokens_lookup
                    ON account_tokens(token_hash, purpose, expires_at);

                CREATE TABLE IF NOT EXISTS sync_entities (
                    principal_kind TEXT NOT NULL CHECK (principal_kind IN ('account', 'guest')),
                    principal_id TEXT NOT NULL,
                    entity_type TEXT NOT NULL,
                    entity_id TEXT NOT NULL,
                    revision INTEGER NOT NULL CHECK (revision >= 1),
                    payload_json TEXT NOT NULL,
                    checksum TEXT NOT NULL,
                    origin_device_id TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0, 1)),
                    PRIMARY KEY(principal_kind, principal_id, entity_type, entity_id)
                );
                CREATE INDEX IF NOT EXISTS idx_sync_entities_principal
                    ON sync_entities(principal_kind, principal_id, entity_type, updated_at);

                CREATE TABLE IF NOT EXISTS sync_changes (
                    seq INTEGER PRIMARY KEY AUTOINCREMENT,
                    principal_kind TEXT NOT NULL CHECK (principal_kind IN ('account', 'guest')),
                    principal_id TEXT NOT NULL,
                    entity_type TEXT NOT NULL,
                    entity_id TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    payload_json TEXT NOT NULL,
                    checksum TEXT NOT NULL,
                    origin_device_id TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0, 1))
                );
                CREATE INDEX IF NOT EXISTS idx_sync_changes_pull
                    ON sync_changes(principal_kind, principal_id, seq);

                CREATE TABLE IF NOT EXISTS sync_conflicts (
                    id TEXT PRIMARY KEY,
                    principal_kind TEXT NOT NULL CHECK (principal_kind IN ('account', 'guest')),
                    principal_id TEXT NOT NULL,
                    entity_type TEXT NOT NULL,
                    entity_id TEXT NOT NULL,
                    current_revision INTEGER NOT NULL,
                    incoming_base_revision INTEGER NOT NULL,
                    incoming_payload_json TEXT NOT NULL,
                    incoming_checksum TEXT NOT NULL,
                    incoming_deleted INTEGER NOT NULL DEFAULT 0 CHECK (incoming_deleted IN (0, 1)),
                    origin_device_id TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    resolved_at INTEGER,
                    resolution_revision INTEGER
                );
                CREATE INDEX IF NOT EXISTS idx_sync_conflicts_open
                    ON sync_conflicts(principal_kind, principal_id, resolved_at, created_at);
                """
            )
            if current < 3:
                columns = {
                    str(row[1])
                    for row in connection.execute("PRAGMA table_info(sync_conflicts)").fetchall()
                }
                if "incoming_deleted" not in columns:
                    connection.execute(
                        "ALTER TABLE sync_conflicts ADD COLUMN incoming_deleted INTEGER NOT NULL DEFAULT 0 "
                        "CHECK (incoming_deleted IN (0, 1))"
                    )
            if current < SCHEMA_VERSION:
                connection.execute(f"PRAGMA user_version={SCHEMA_VERSION}")
            connection.execute(
                "INSERT INTO metadata(key, value, updated_at) VALUES('schema', ?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
                (json.dumps({"version": SCHEMA_VERSION}, separators=(",", ":")), int(time.time())),
            )

    def get_meta(self, key: str) -> str | None:
        with self.connection() as connection:
            row = connection.execute("SELECT value FROM metadata WHERE key=?", (key,)).fetchone()
            return str(row["value"]) if row is not None else None

    def set_meta(self, key: str, value: str) -> None:
        with self.connection(write=True) as connection:
            connection.execute(
                "INSERT INTO metadata(key, value, updated_at) VALUES(?, ?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
                (key, value, int(time.time())),
            )

    def integrity_check(self) -> dict[str, Any]:
        try:
            with self.connection() as connection:
                integrity = str(connection.execute("PRAGMA integrity_check").fetchone()[0])
                foreign_key_rows = connection.execute("PRAGMA foreign_key_check").fetchall()
                counts = {
                    "api_keys": int(connection.execute("SELECT COUNT(*) FROM api_keys").fetchone()[0]),
                    "conversations": int(connection.execute("SELECT COUNT(*) FROM conversations").fetchone()[0]),
                    "messages": int(connection.execute("SELECT COUNT(*) FROM conversation_messages").fetchone()[0]),
                    "learning_events": int(connection.execute("SELECT COUNT(*) FROM learning_events").fetchone()[0]),
                    "learning_pending": int(
                        connection.execute("SELECT COUNT(*) FROM learning_events WHERE synced=0").fetchone()[0]
                    ),
                    "accounts": int(connection.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]),
                    "guests": int(connection.execute("SELECT COUNT(*) FROM guests").fetchone()[0]),
                    "devices": int(connection.execute("SELECT COUNT(*) FROM devices").fetchone()[0]),
                    "auth_sessions": int(connection.execute("SELECT COUNT(*) FROM auth_sessions").fetchone()[0]),
                    "sync_entities": int(connection.execute("SELECT COUNT(*) FROM sync_entities").fetchone()[0]),
                    "sync_conflicts_open": int(
                        connection.execute("SELECT COUNT(*) FROM sync_conflicts WHERE resolved_at IS NULL").fetchone()[0]
                    ),
                }
                return {
                    "ok": integrity == "ok" and not foreign_key_rows,
                    "schema_version": int(connection.execute("PRAGMA user_version").fetchone()[0]),
                    "journal_mode": str(connection.execute("PRAGMA journal_mode").fetchone()[0]).lower(),
                    "integrity": integrity,
                    "foreign_key_errors": len(foreign_key_rows),
                    "counts": counts,
                    "path": str(self.path),
                }
        except Exception as exc:
            return {
                "ok": False,
                "schema_version": 0,
                "integrity": "error",
                "foreign_key_errors": -1,
                "counts": {},
                "path": str(self.path),
                "error": str(exc),
            }

    def create_snapshot(self, destination: Path) -> dict[str, Any]:
        """Create a full, verified SQLite snapshot for local operational rollback.

        Unlike the exportable owner backup, this snapshot intentionally retains
        API credential hashes so an automatic server rollback can restore the
        exact pre-update authentication state. Callers must keep it outside any
        exported backup root with owner-only permissions.
        """

        destination = destination.resolve()
        if destination == self.path:
            raise ValueError("Snapshot destination must differ from live database")
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(
            destination.name + f".{os.getpid()}.{threading.get_ident()}.{time.time_ns()}.tmp"
        )
        temporary.unlink(missing_ok=True)
        try:
            source = self._connect()
            target = sqlite3.connect(temporary, timeout=30.0)
            try:
                source.backup(target)
                target.commit()
                target.execute("PRAGMA foreign_keys=ON")
                integrity = str(target.execute("PRAGMA integrity_check").fetchone()[0])
                foreign_key_errors = len(target.execute("PRAGMA foreign_key_check").fetchall())
                schema_version = int(target.execute("PRAGMA user_version").fetchone()[0])
                if integrity != "ok" or foreign_key_errors:
                    raise RuntimeError(
                        f"Refusing invalid SQLite snapshot: integrity={integrity}, "
                        f"foreign_key_errors={foreign_key_errors}"
                    )
            finally:
                target.close()
                source.close()
            if os.name != "nt":
                os.chmod(temporary, 0o600)
            with temporary.open("rb") as stream:
                os.fsync(stream.fileno())
            temporary.replace(destination)
            if os.name != "nt":
                try:
                    directory_fd = os.open(destination.parent, os.O_RDONLY)
                    try:
                        os.fsync(directory_fd)
                    finally:
                        os.close(directory_fd)
                except OSError:
                    pass
            return {
                "ok": True,
                "path": str(destination),
                "bytes": destination.stat().st_size,
                "schema_version": schema_version,
                "integrity": integrity,
                "foreign_key_errors": foreign_key_errors,
            }
        finally:
            temporary.unlink(missing_ok=True)


def atomic_write_text(path: Path, text: str, *, mode: int | None = None) -> None:
    """Crash-safe same-directory text replacement used by rollback mirrors."""

    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".{os.getpid()}.{threading.get_ident()}.{time.time_ns()}.tmp")
    try:
        with temporary.open("w", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        if mode is not None and os.name != "nt":
            os.chmod(temporary, mode)
        temporary.replace(path)
        if os.name != "nt":
            try:
                directory_fd = os.open(path.parent, os.O_RDONLY)
                try:
                    os.fsync(directory_fd)
                finally:
                    os.close(directory_fd)
            except OSError:
                pass
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate or snapshot AuroraFox API SQLite persistence")
    parser.add_argument("--path", required=True, help="Path to aurorafox.sqlite3")
    parser.add_argument(
        "--snapshot-to",
        default="",
        help="Create a full local operational rollback snapshot at this path after validation",
    )
    args = parser.parse_args()
    database = AuroraDatabase(Path(args.path))
    status = database.integrity_check()
    if not bool(status.get("ok", False)) or status.get("journal_mode") != "wal":
        print(json.dumps(status, ensure_ascii=False, sort_keys=True))
        return 1
    if args.snapshot_to:
        snapshot = database.create_snapshot(Path(args.snapshot_to))
        print(json.dumps({"database": status, "snapshot": snapshot}, ensure_ascii=False, sort_keys=True))
        return 0
    print(json.dumps(status, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
