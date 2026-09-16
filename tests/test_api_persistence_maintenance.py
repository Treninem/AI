from __future__ import annotations

import sqlite3
from pathlib import Path

from api.account_store import AccountStore
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
    assert "database_size" in status["warnings"]
    assert "sync_change_history" in status["warnings"]
    assert "open_sync_conflicts" in status["warnings"]
    assert status["counts"]["sync_entities"] == 1
    assert status["counts"]["sync_changes"] == 1
    assert status["counts"]["sync_conflicts_open"] == 1
    assert status["counts"]["learning_pending"] == 1
    assert status["retention_policy"]["sync_changes_auto_pruned"] is False
    assert status["retention_policy"]["pending_learning_protected"] is True


def test_prune_removes_only_old_ephemeral_auth_rows(tmp_path: Path):
    root = tmp_path / "api"
    accounts = AccountStore(root)
    login = _verified(accounts)
    principal = accounts.verify_access(login["access_token"])
    assert principal is not None

    conversations = ConversationStore(root / "conversations")
    conversations.append(principal["id"], "kept-chat", "user", "keep conversation")
    sync = SyncStore(root)
    sync.push(
        principal,
        [{"entity_type": "project", "entity_id": "kept-project", "base_revision": 0, "payload": {"name": "keep"}}],
    )
    sync.push(
        principal,
        [{"entity_type": "project", "entity_id": "kept-project", "base_revision": 0, "payload": {"name": "conflict"}}],
    )
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
        connection.commit()

    maintenance = PersistenceMaintenance(root)
    first = maintenance.prune_ephemeral(retention_seconds=0)
    assert first["removed"]["account_tokens"] >= 1
    with sqlite3.connect(db_path) as connection:
        # Consumed refresh token is deliberately retained until it expires, so
        # replay detection cannot be weakened by maintenance.
        assert connection.execute("SELECT COUNT(*) FROM refresh_tokens WHERE id=?", (consumed_id,)).fetchone()[0] == 1
        connection.execute("UPDATE refresh_tokens SET expires_at=1 WHERE id=?", (consumed_id,))
        connection.commit()

    second = maintenance.prune_ephemeral(retention_seconds=0)
    assert second["removed"]["refresh_tokens"] >= 1
    assert accounts.verify_access(rotated["access_token"]) is not None

    # Private/user state and offline sync history are outside automatic retention.
    assert conversations.get(principal["id"], "kept-chat")["messages"][0]["content"] == "keep conversation"
    pulled = sync.pull(principal)
    assert any(item["entity_id"] == "kept-project" for item in pulled["changes"])
    assert len(sync.conflicts(principal)) == 1
    assert [item["id"] for item in LearningStore(root).pending(10)] == [pending["id"]]
    protected = set(second["protected"])
    assert {"conversations", "learning_events_pending", "sync_entities", "sync_changes", "sync_conflicts_unresolved"} <= protected
