from __future__ import annotations

import json
import os
import sqlite3
import threading
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator


SCHEMA_VERSION = 1


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
                """
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
