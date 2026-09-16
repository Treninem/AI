from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from api.account_store import AccountStore, RefreshReplayError
from api.conversation_store import ConversationStore
from api.learning_store import LearningStore
from api.persistence_maintenance import PersistenceMaintenance
from api.sync_store import SyncStore


def _verified(accounts: AccountStore):
    created = accounts.register("maintenance@example.com", "maintenance secure password", "Maintenance")
    accounts.verify_email(created["verification_token"])
    return accounts.login("maintenance@example.com", "maintenance secure password", "PC", "pytest")


def test_capacity_status_is_observational_and_flags_thresholds(tmp_path: Path, monkeypatch):
    root = tmp_path / "api"
    monkeypatch.setenv("AURORAFOX_DATABASE_WARN_BYTES", "1")
    monkeypatch.setenv("AURORAFOX_SYNC_CHANGES_WARN", "1")
    monkeypatch.setenv("AURORAFOX_SYNC_CONFLICTS_WARN", "1")
    monkeypatch.setenv("AURORAFOX_STORAGE_MIN_FREE_BYTES", "1")
    accounts = AccountStore(root)
    login = _verified(accounts)
    principal = accounts.verify_access(login["access_token"])
    assert principal is not None

    sync = SyncStore(root)
    sync.push(
        principal,
        [{"entity_type": "memory", "entity_id": "kept", "base_revision": 0, "payload": {"value": 1}}],
    )
    sync.push(
        principal,
        [{"entity_type": "memory", "entity_id": "kept", "base_revision": 0, "payload": {"value": 2}}],
    )
    learning = LearningStore(root)
    learning.append("feedback", {"private": "pending"})

    status = PersistenceMaintenance(root).status()
    assert status["ok"] is True
    assert status["attention_required"] is True
    assert status["hard_pressure"] is False
    assert "database_size" in status["warnings"]
    assert "sync_change_history" in status["warnings"]
    assert "open_sync_conflicts" in status["warnings"]
    assert "pending_learning_protected" in status["warnings"]
    assert status["counts"]["sync_entities"] == 1
    assert status["counts"]["sync_changes"] == 1
    assert status["counts"]["sync_conflicts_open"] == 1
    assert status["counts"]["learning_pending"] == 1
    assert status["capacity_policy"]["database_warning_precedes_backup_cap"] is True
    assert status["capacity_policy"]["database_warning_includes_wal"] is True
    assert status["capacity_policy"]["database_warn_bytes"] < status["capacity_policy"]["backup_max_source_bytes"]
    assert status["sizes"]["database_effective_bytes"] == (
        status["sizes"]["database_bytes"] + status["sizes"]["wal_bytes"]
    )
    assert status["retention_policy"]["sync_changes_auto_pruned"] is False
    assert status["retention_policy"]["sync_conflicts_auto_pruned"] is False
    assert status["retention_policy"]["pending_learning_protected"] is True
    assert status["retention_policy"]["refresh_replay_sentinel_kept_until_expiry"] is True

    # Critical free-space pressure is a fail-closed capacity signal, but status
    # inspection itself remains non-destructive.
    monkeypatch.setenv("AURORAFOX_STORAGE_MIN_FREE_BYTES", str(10**18))
    pressure = PersistenceMaintenance(root).status()
    assert pressure["ok"] is False
    assert pressure["hard_pressure"] is True
    assert "disk_free_critical" in pressure["warnings"]
    assert LearningStore(root).pending(10)[0]["payload"] == {"private": "pending"}
    assert sync.pull(principal)["changes"][0]["payload"] == {"value": 1}


def test_capacity_warning_includes_uncheckpointed_wal_bytes(tmp_path: Path, monkeypatch):
    root = tmp_path / "api"
    AccountStore(root)
    monkeypatch.setenv("AURORAFOX_DATABASE_WARN_BYTES", "100")
    monkeypatch.setenv("AURORAFOX_BACKUP_MAX_BYTES", "1000")
    monkeypatch.setenv("AURORAFOX_STORAGE_MIN_FREE_BYTES", "1")
    maintenance = PersistenceMaintenance(root)
    db_path = maintenance.database.path

    def fake_size(path: Path) -> int:
        text = str(path)
        if path == db_path:
            return 40
        if text.endswith("-wal"):
            return 70
        if text.endswith("-shm"):
            return 32
        return 0

    monkeypatch.setattr(maintenance, "_size", fake_size)
    status = maintenance.status()
    assert status["sizes"]["database_bytes"] == 40
    assert status["sizes"]["wal_bytes"] == 70
    assert status["sizes"]["database_effective_bytes"] == 110
    assert "database_size" in status["warnings"]


def test_guest_population_warning_is_observational_and_never_prunes_principals(tmp_path: Path, monkeypatch):
    root = tmp_path / "api"
    monkeypatch.setenv("AURORAFOX_GUESTS_WARN", "2")
    monkeypatch.setenv("AURORAFOX_STORAGE_MIN_FREE_BYTES", "1")
    accounts = AccountStore(root)
    first = accounts.create_guest("Guest one", "pytest")
    second = accounts.create_guest("Guest two", "pytest")

    maintenance = PersistenceMaintenance(root)
    status = maintenance.status()
    assert status["ok"] is True
    assert status["attention_required"] is True
    assert status["counts"]["guests"] == 2
    assert "guest_population" in status["warnings"]
    assert status["capacity_policy"]["guest_warn_count"] == 2
    assert status["retention_policy"]["guest_principals_auto_pruned"] is False

    pruned = maintenance.prune_ephemeral(retention_seconds=0)
    assert "guests" in pruned["protected"]
    assert "devices" in pruned["protected"]
    assert accounts.verify_guest(first["guest_token"]) is not None
    assert accounts.verify_guest(second["guest_token"]) is not None
    with sqlite3.connect(root / "aurorafox.sqlite3") as connection:
        assert connection.execute("SELECT COUNT(*) FROM guests").fetchone()[0] == 2


def test_prune_removes_only_terminal_auth_rows_and_keeps_sync_audit(tmp_path: Path, monkeypatch):
    root = tmp_path / "api"
    monkeypatch.setenv("AURORAFOX_STORAGE_MIN_FREE_BYTES", "1")
    accounts = AccountStore(root)
    login = _verified(accounts)
    principal = accounts.verify_access(login["access_token"])
    assert principal is not None

    conversations = ConversationStore(root / "conversations")
    conversations.append(principal["id"], "kept-chat", "user", "keep conversation")
    sync = SyncStore(root)
    first = sync.push(
        principal,
        [{"entity_type": "project", "entity_id": "kept-project", "base_revision": 0, "payload": {"name": "keep"}}],
    )["results"][0]
    assert first["revision"] == 1

    resolved = sync.push(
        principal,
        [{"entity_type": "project", "entity_id": "kept-project", "base_revision": 0, "payload": {"name": "resolved-incoming"}}],
    )["results"][0]
    assert resolved["status"] == "conflict"
    sync.resolve_conflict(
        principal,
        resolved["conflict_id"],
        expected_revision=1,
        payload={"name": "resolved"},
    )
    unresolved = sync.push(
        principal,
        [{"entity_type": "project", "entity_id": "kept-project", "base_revision": 1, "payload": {"name": "still-open"}}],
    )["results"][0]
    assert unresolved["status"] == "conflict"
    pending = LearningStore(root).append("feedback", {"keep": True})

    # Rotate once so the consumed refresh token remains a replay sentinel while
    # it is still within its validity/retention horizon.
    rotated = accounts.refresh(login["refresh_token"])
    db_path = root / "aurorafox.sqlite3"
    with sqlite3.connect(db_path) as connection:
        consumed_id, consumed_expires = connection.execute(
            "SELECT id, expires_at FROM refresh_tokens WHERE consumed_at IS NOT NULL LIMIT 1"
        ).fetchone()
        assert consumed_expires > 1
        connection.execute(
            "INSERT INTO account_tokens(id, account_id, purpose, token_hash, created_at, expires_at, used_at) "
            "VALUES('old-account-token', ?, 'reset_password', ?, 1, 1, 1)",
            (principal["principal_id"], "f" * 64),
        )
        # Even an ancient resolved conflict remains an audit record until there is
        # an explicit sync snapshot/cursor-reset compaction protocol.
        connection.execute(
            "UPDATE sync_conflicts SET resolved_at=1 WHERE id=?",
            (resolved["conflict_id"],),
        )
        before_changes = int(connection.execute("SELECT COUNT(*) FROM sync_changes").fetchone()[0])
        before_conflicts = int(connection.execute("SELECT COUNT(*) FROM sync_conflicts").fetchone()[0])
        before_pending = int(connection.execute("SELECT COUNT(*) FROM learning_events WHERE synced=0").fetchone()[0])
        connection.commit()

    maintenance = PersistenceMaintenance(root)
    first_prune = maintenance.prune_ephemeral(retention_seconds=0)
    assert first_prune["removed"]["account_tokens"] >= 1
    assert "resolved_sync_conflicts" not in first_prune["removed"]
    with sqlite3.connect(db_path) as connection:
        # Consumed refresh token is deliberately retained until it expires, so
        # replay detection cannot be weakened by maintenance.
        assert connection.execute("SELECT COUNT(*) FROM refresh_tokens WHERE id=?", (consumed_id,)).fetchone()[0] == 1
        assert int(connection.execute("SELECT COUNT(*) FROM sync_conflicts").fetchone()[0]) == before_conflicts
        assert connection.execute(
            "SELECT COUNT(*) FROM sync_conflicts WHERE id=?", (resolved["conflict_id"],)
        ).fetchone()[0] == 1
        assert connection.execute(
            "SELECT COUNT(*) FROM sync_conflicts WHERE id=?", (unresolved["conflict_id"],)
        ).fetchone()[0] == 1
        assert int(connection.execute("SELECT COUNT(*) FROM sync_changes").fetchone()[0]) == before_changes
        assert int(connection.execute("SELECT COUNT(*) FROM learning_events WHERE synced=0").fetchone()[0]) == before_pending
        connection.execute("UPDATE refresh_tokens SET expires_at=1 WHERE id=?", (consumed_id,))
        connection.commit()

    second_prune = maintenance.prune_ephemeral(retention_seconds=0)
    assert second_prune["removed"]["refresh_tokens"] >= 1
    assert accounts.verify_access(rotated["access_token"]) is not None

    # Private/user state and offline sync history are outside automatic retention.
    assert conversations.get(principal["id"], "kept-chat")["messages"][0]["content"] == "keep conversation"
    pulled = sync.pull(principal)
    assert any(item["entity_id"] == "kept-project" for item in pulled["changes"])
    assert pulled["changes"][-1]["payload"] == {"name": "resolved"}
    assert len(sync.conflicts(principal)) == 1
    assert sync.conflicts(principal)[0]["id"] == unresolved["conflict_id"]
    assert [item["id"] for item in LearningStore(root).pending(10)] == [pending["id"]]
    protected = set(second_prune["protected"])
    assert {
        "conversations",
        "learning_events_pending",
        "sync_entities",
        "sync_changes",
        "sync_conflicts_unresolved",
        "sync_conflicts_resolved",
    } <= protected


def test_prune_preserves_revoked_refresh_family_until_tokens_expire(tmp_path: Path, monkeypatch):
    root = tmp_path / "api"
    monkeypatch.setenv("AURORAFOX_STORAGE_MIN_FREE_BYTES", "1")
    accounts = AccountStore(root)
    login = _verified(accounts)

    # Rotation consumes the first token. Replaying it revokes the whole family,
    # including the current refresh token and its session. Those rows must remain
    # until token expiry so any further replay is still recognized as a replay,
    # rather than silently degrading into an unknown-token path after retention.
    accounts.refresh(login["refresh_token"])
    with pytest.raises(RefreshReplayError):
        accounts.refresh(login["refresh_token"])

    db_path = root / "aurorafox.sqlite3"
    with sqlite3.connect(db_path) as connection:
        session_id, revoked_at = connection.execute(
            "SELECT id, revoked_at FROM auth_sessions WHERE family_id=(SELECT family_id FROM refresh_tokens LIMIT 1) LIMIT 1"
        ).fetchone()
        assert revoked_at is not None
        rows = connection.execute(
            "SELECT id, expires_at, revoked_at FROM refresh_tokens WHERE session_id=? ORDER BY generation",
            (session_id,),
        ).fetchall()
        assert len(rows) >= 2
        assert all(row[1] > 1 for row in rows)
        assert all(row[2] is not None for row in rows)
        token_ids = [row[0] for row in rows]

    pruned = PersistenceMaintenance(root).prune_ephemeral(retention_seconds=0)
    assert pruned["removed"]["refresh_tokens"] == 0
    with sqlite3.connect(db_path) as connection:
        assert connection.execute("SELECT COUNT(*) FROM auth_sessions WHERE id=?", (session_id,)).fetchone()[0] == 1
        remaining = [
            row[0]
            for row in connection.execute(
                "SELECT id FROM refresh_tokens WHERE session_id=? ORDER BY generation",
                (session_id,),
            ).fetchall()
        ]
    assert remaining == token_ids

    # Replay detection remains semantically strong after maintenance because the
    # revoked family sentinel still exists until its original validity window ends.
    with pytest.raises(RefreshReplayError):
        accounts.refresh(login["refresh_token"])


def test_prune_if_due_persists_cadence_across_process_instances(tmp_path: Path, monkeypatch):
    root = tmp_path / "api"
    monkeypatch.setenv("AURORAFOX_STORAGE_MAINTENANCE_INTERVAL_SECONDS", "3600")
    monkeypatch.setenv("AURORAFOX_STORAGE_RETENTION_SECONDS", "3600")
    monkeypatch.setenv("AURORAFOX_STORAGE_MIN_FREE_BYTES", "1")
    AccountStore(root)

    first = PersistenceMaintenance(root).prune_if_due(force=True)
    second = PersistenceMaintenance(root).prune_if_due()
    assert first["ran"] is True
    assert second["ran"] is False
    assert 0 < second["next_in_seconds"] <= 3600


def test_malformed_capacity_environment_falls_back_safely(tmp_path: Path, monkeypatch):
    root = tmp_path / "api"
    AccountStore(root)
    monkeypatch.setenv("AURORAFOX_STORAGE_MIN_FREE_BYTES", "not-a-number")
    monkeypatch.setenv("AURORAFOX_STORAGE_MAINTENANCE_INTERVAL_SECONDS", "bad")
    monkeypatch.setenv("AURORAFOX_DATABASE_WARN_BYTES", "invalid")
    monkeypatch.setenv("AURORAFOX_BACKUP_MAX_BYTES", "invalid")
    monkeypatch.setenv("AURORAFOX_GUESTS_WARN", "invalid")
    maintenance = PersistenceMaintenance(root)
    status = maintenance.status()
    assert isinstance(status["hard_pressure"], bool)
    assert maintenance.maintenance_interval_seconds >= 60
    assert maintenance.warn_database_bytes > 0
    assert maintenance.warn_guests > 0
    assert status["capacity_policy"]["database_warning_precedes_backup_cap"] is True
