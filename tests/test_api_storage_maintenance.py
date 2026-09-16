from __future__ import annotations

import hashlib
import time
from pathlib import Path

from api.account_store import AccountStore
from api.conversation_store import ConversationStore
from api.learning_store import LearningStore
from api.storage_maintenance import StorageMaintenance
from api.sync_store import SyncStore


def _verified_login(accounts: AccountStore, email: str, password: str, device: str):
    created = accounts.register(email, password, device)
    accounts.verify_email(created["verification_token"])
    return accounts.login(email, password, device, "pytest")


def test_retention_prunes_only_terminal_auth_and_resolved_conflicts(tmp_path: Path):
    root = tmp_path / "api"
    accounts = AccountStore(root)
    sync = SyncStore(root)
    conversations = ConversationStore(root / "conversations")
    learning = LearningStore(root)
    now = int(time.time())
    old = now - 3 * 60 * 60

    stale_session = _verified_login(accounts, "stale@example.com", "stale account password", "old-device")
    stale_principal = accounts.verify_access(stale_session["access_token"])
    assert stale_principal is not None
    assert accounts.revoke_access(stale_session["access_token"]) is True

    active_session = _verified_login(accounts, "active@example.com", "active account password", "active-device")
    active_principal = accounts.verify_access(active_session["access_token"])
    assert active_principal is not None
    rotated = accounts.refresh(active_session["refresh_token"])
    consumed_hash = hashlib.sha256(active_session["refresh_token"].encode("utf-8")).hexdigest()

    reset_token = accounts.request_password_reset("active@example.com")
    assert reset_token is not None

    first = sync.push(
        active_principal,
        [{"entity_type": "memory", "entity_id": "keep", "base_revision": 0, "payload": {"v": 1}}],
    )["results"][0]
    assert first["revision"] == 1
    second = sync.push(
        active_principal,
        [{"entity_type": "memory", "entity_id": "keep", "base_revision": 1, "payload": {"v": 2}}],
    )["results"][0]
    assert second["revision"] == 2
    resolved_conflict = sync.push(
        active_principal,
        [{"entity_type": "memory", "entity_id": "keep", "base_revision": 1, "payload": {"v": "resolved"}}],
    )["results"][0]
    assert resolved_conflict["status"] == "conflict"
    sync.resolve_conflict(
        active_principal,
        resolved_conflict["conflict_id"],
        expected_revision=2,
        payload={"v": 3},
    )
    open_conflict = sync.push(
        active_principal,
        [{"entity_type": "memory", "entity_id": "keep", "base_revision": 2, "payload": {"v": "still-open"}}],
    )["results"][0]
    assert open_conflict["status"] == "conflict"

    conversations.append(active_principal["id"], "private-chat", "user", "preserve conversation")
    pending = learning.append("feedback", {"note": "must survive retention"})

    with accounts.database.connection(write=True) as connection:
        connection.execute(
            "UPDATE auth_sessions SET revoked_at=?, access_expires_at=? WHERE id=?",
            (old, old, stale_session["session_id"]),
        )
        connection.execute(
            "UPDATE refresh_tokens SET revoked_at=?, expires_at=? WHERE session_id=?",
            (old, old, stale_session["session_id"]),
        )
        connection.execute(
            "UPDATE account_tokens SET expires_at=?, used_at=COALESCE(used_at, ?) WHERE token_hash=?",
            (old, old, hashlib.sha256(reset_token.encode("utf-8")).hexdigest()),
        )
        connection.execute(
            "UPDATE sync_conflicts SET resolved_at=? WHERE id=?",
            (old, resolved_conflict["conflict_id"]),
        )
        before_changes = int(connection.execute("SELECT COUNT(*) FROM sync_changes").fetchone()[0])
        before_pending = int(connection.execute("SELECT COUNT(*) FROM learning_events WHERE synced=0").fetchone()[0])

    maintenance = StorageMaintenance(
        accounts.database,
        root,
        retention_seconds=60 * 60,
        interval_seconds=60,
        min_free_bytes=1,
    )
    result = maintenance.prune_safe(now=now)
    assert result["ok"] is True
    assert result["removed"]["auth_sessions"] == 1
    assert result["removed"]["refresh_tokens"] >= 1
    assert result["removed"]["account_tokens"] >= 1
    assert result["removed"]["resolved_sync_conflicts"] == 1

    with accounts.database.connection() as connection:
        assert connection.execute(
            "SELECT COUNT(*) FROM auth_sessions WHERE id=?", (stale_session["session_id"],)
        ).fetchone()[0] == 0
        # A consumed refresh token remains replay-detectable until its original expiry.
        assert connection.execute(
            "SELECT COUNT(*) FROM refresh_tokens WHERE token_hash=?", (consumed_hash,)
        ).fetchone()[0] == 1
        assert connection.execute(
            "SELECT COUNT(*) FROM auth_sessions WHERE id=?", (rotated["session_id"],)
        ).fetchone()[0] == 1
        assert connection.execute(
            "SELECT COUNT(*) FROM sync_conflicts WHERE id=?", (resolved_conflict["conflict_id"],)
        ).fetchone()[0] == 0
        assert connection.execute(
            "SELECT COUNT(*) FROM sync_conflicts WHERE id=?", (open_conflict["conflict_id"],)
        ).fetchone()[0] == 1
        assert int(connection.execute("SELECT COUNT(*) FROM sync_changes").fetchone()[0]) == before_changes
        assert int(connection.execute("SELECT COUNT(*) FROM learning_events WHERE synced=0").fetchone()[0]) == before_pending
        assert connection.execute("SELECT COUNT(*) FROM accounts").fetchone()[0] == 2
        assert connection.execute("SELECT COUNT(*) FROM devices").fetchone()[0] == 2

    assert learning.pending(10)[0]["id"] == pending["id"]
    assert conversations.get(active_principal["id"], "private-chat")["messages"][0]["content"] == "preserve conversation"
    assert sync.pull(active_principal)["changes"][-1]["payload"] == {"v": 3}
    assert accounts.verify_access(rotated["access_token"]) is not None


def test_capacity_status_warns_without_pruning_private_or_pending_data(tmp_path: Path):
    root = tmp_path / "api"
    accounts = AccountStore(root)
    sync = SyncStore(root)
    learning = LearningStore(root)
    login = _verified_login(accounts, "capacity@example.com", "capacity account password", "device")
    principal = accounts.verify_access(login["access_token"])
    assert principal is not None
    sync.push(
        principal,
        [{"entity_type": "project", "entity_id": "project", "base_revision": 0, "payload": {"name": "private"}}],
    )
    pending = learning.append("feedback", {"private": True})

    maintenance = StorageMaintenance(
        accounts.database,
        root,
        warn_database_bytes=1,
        min_free_bytes=1,
        warn_sync_changes=1,
        warn_open_conflicts=1,
    )
    status = maintenance.status()
    assert status["ok"] is True
    assert status["pressure"] is True
    assert "database_size" in status["warnings"]
    assert "sync_history" in status["warnings"]
    assert "pending_learning_protected" in status["warnings"]
    assert learning.pending(10)[0]["id"] == pending["id"]
    assert sync.pull(principal)["changes"][0]["payload"] == {"name": "private"}

    impossible_free_space = StorageMaintenance(
        accounts.database,
        root,
        min_free_bytes=10**18,
    ).status()
    assert impossible_free_space["ok"] is False
    assert impossible_free_space["hard_pressure"] is True
    assert "disk_free_critical" in impossible_free_space["warnings"]


def test_maintenance_interval_prevents_write_churn(tmp_path: Path):
    root = tmp_path / "api"
    accounts = AccountStore(root)
    maintenance = StorageMaintenance(accounts.database, root, interval_seconds=3600, min_free_bytes=1)
    first = maintenance.maybe_prune(force=True)
    second = maintenance.maybe_prune()
    assert first["ran"] is True
    assert second["ran"] is False
    assert second["next_in_seconds"] > 0
