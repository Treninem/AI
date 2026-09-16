from __future__ import annotations

import sqlite3
from pathlib import Path

from api.database import AuroraDatabase, SCHEMA_VERSION


def test_v2_sync_conflicts_upgrade_adds_tombstone_state_without_data_loss(tmp_path: Path):
    path = tmp_path / "aurorafox.sqlite3"
    with sqlite3.connect(path) as connection:
        connection.execute(
            "CREATE TABLE sync_conflicts ("
            "id TEXT PRIMARY KEY, principal_kind TEXT NOT NULL, principal_id TEXT NOT NULL, "
            "entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, current_revision INTEGER NOT NULL, "
            "incoming_base_revision INTEGER NOT NULL, incoming_payload_json TEXT NOT NULL, "
            "incoming_checksum TEXT NOT NULL, origin_device_id TEXT NOT NULL, created_at INTEGER NOT NULL, "
            "resolved_at INTEGER, resolution_revision INTEGER)"
        )
        connection.execute(
            "INSERT INTO sync_conflicts(id, principal_kind, principal_id, entity_type, entity_id, current_revision, "
            "incoming_base_revision, incoming_payload_json, incoming_checksum, origin_device_id, created_at) "
            "VALUES('legacy', 'account', 'a', 'memory', 'm', 2, 1, '{}', 'hash', 'device', 1)"
        )
        connection.execute("PRAGMA user_version=2")

    database = AuroraDatabase(path)
    status = database.integrity_check()
    assert status["ok"] is True
    assert status["schema_version"] == SCHEMA_VERSION
    with sqlite3.connect(path) as connection:
        columns = {row[1] for row in connection.execute("PRAGMA table_info(sync_conflicts)").fetchall()}
        assert "incoming_deleted" in columns
        assert connection.execute(
            "SELECT incoming_payload_json, incoming_deleted FROM sync_conflicts WHERE id='legacy'"
        ).fetchone() == ("{}", 0)
