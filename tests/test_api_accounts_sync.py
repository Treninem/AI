from __future__ import annotations

import sqlite3
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest

from api.account_store import AccountStore, AuthenticationError, ConflictError, RefreshReplayError
from api.conversation_store import ConversationStore
from api.database import AuroraDatabase, SCHEMA_VERSION
from api.sync_store import SyncStore


def _verified_account(store: AccountStore, email: str, password: str, device: str):
    registered = store.register(email, password, email.split("@", 1)[0])
    store.verify_email(registered["verification_token"])
    return store.login(email, password, device, "test")


def test_accounts_are_case_insensitive_and_passwords_are_not_stored_plaintext(tmp_path: Path):
    store = AccountStore(tmp_path / "api")
    created = store.register("User@Example.COM", "correct horse battery staple", "User")
    account = created["account"]
    assert account["email"] == "user@example.com"
    assert account["email_verified"] is False
    verified = store.verify_email(created["verification_token"])
    assert verified["email_verified"] is True
    with pytest.raises(ConflictError):
        store.register("USER@example.com", "another secure password", "Duplicate")

    with sqlite3.connect(tmp_path / "api" / "aurorafox.sqlite3") as connection:
        salt, digest, params = connection.execute(
            "SELECT password_salt, password_hash, password_params_json FROM accounts WHERE id=?",
            (account["id"],),
        ).fetchone()
    assert "correct horse battery staple" not in str(salt)
    assert "correct horse battery staple" not in str(digest)
    assert "scrypt" in str(params)


def test_access_refresh_rotation_replay_and_device_revoke(tmp_path: Path):
    store = AccountStore(tmp_path / "api", access_ttl=120, refresh_ttl=3600)
    session = _verified_account(store, "rotate@example.com", "very secure password", "Windows")
    first_access = session["access_token"]
    first_refresh = session["refresh_token"]
    principal = store.verify_access(first_access)
    assert principal is not None
    assert principal["principal_kind"] == "account"

    rotated = store.refresh(first_refresh)
    assert rotated["refresh_token"] != first_refresh
    assert store.verify_access(first_access) is None
    assert store.verify_access(rotated["access_token"]) is not None

    with pytest.raises(RefreshReplayError):
        store.refresh(first_refresh)
    # Reusing an already-consumed refresh token revokes the whole family,
    # including the access token produced by the legitimate rotation.
    assert store.verify_access(rotated["access_token"]) is None

    relogin = store.login(
        "ROTATE@example.com",
        "very secure password",
        "Windows",
        "test",
        device_id=session["device_id"],
    )
    assert store.verify_access(relogin["access_token"]) is not None
    account_id = str(relogin["account"]["id"])
    assert store.revoke_device(account_id, relogin["device_id"]) is True
    assert store.verify_access(relogin["access_token"]) is None
    with pytest.raises(AuthenticationError):
        store.refresh(relogin["refresh_token"])


def test_two_accounts_and_two_guests_are_strictly_isolated(tmp_path: Path):
    root = tmp_path / "api"
    accounts = AccountStore(root)
    sync = SyncStore(root)
    first = _verified_account(accounts, "a@example.com", "first account password", "A")
    second = _verified_account(accounts, "b@example.com", "second account password", "B")
    guest_a = accounts.create_guest("Guest A", "windows")
    guest_b = accounts.create_guest("Guest B", "android")

    principals = [
        accounts.verify_access(first["access_token"]),
        accounts.verify_access(second["access_token"]),
        accounts.verify_guest(guest_a["guest_token"]),
        accounts.verify_guest(guest_b["guest_token"]),
    ]
    assert all(principal is not None for principal in principals)
    assert len({principal["id"] for principal in principals if principal}) == 4

    for index, principal in enumerate(principals):
        result = sync.push(
            principal,
            [{"entity_type": "memory", "entity_id": "same-id", "base_revision": 0, "payload": {"owner": index}}],
        )
        assert result["results"][0]["status"] == "applied"

    for index, principal in enumerate(principals):
        pulled = sync.pull(principal)
        assert len(pulled["changes"]) == 1
        assert pulled["changes"][0]["payload"] == {"owner": index}


def test_sync_is_incremental_idempotent_and_preserves_conflicts(tmp_path: Path):
    root = tmp_path / "api"
    accounts = AccountStore(root)
    sync = SyncStore(root)
    login = _verified_account(accounts, "sync@example.com", "synchronization password", "PC")
    principal = accounts.verify_access(login["access_token"])
    assert principal is not None

    first = sync.push(
        principal,
        [{"entity_type": "settings", "entity_id": "ui", "base_revision": 0, "payload": {"scale": 1.0}}],
    )["results"][0]
    assert first["revision"] == 1
    cursor = first["cursor"]

    unchanged = sync.push(
        principal,
        [{"entity_type": "settings", "entity_id": "ui", "base_revision": 0, "payload": {"scale": 1.0}}],
    )["results"][0]
    assert unchanged["status"] == "unchanged"
    assert sync.pull(principal, cursor=cursor)["changes"] == []

    second = sync.push(
        principal,
        [{"entity_type": "settings", "entity_id": "ui", "base_revision": 1, "payload": {"scale": 1.1}}],
    )["results"][0]
    assert second["revision"] == 2

    stale = sync.push(
        principal,
        [{"entity_type": "settings", "entity_id": "ui", "base_revision": 1, "payload": {"scale": 1.2}}],
    )["results"][0]
    assert stale["status"] == "conflict"
    assert stale["current_revision"] == 2
    open_conflicts = sync.conflicts(principal)
    assert [item["id"] for item in open_conflicts] == [stale["conflict_id"]]
    assert open_conflicts[0]["incoming"]["payload"] == {"scale": 1.2}

    resolved = sync.resolve_conflict(
        principal,
        stale["conflict_id"],
        expected_revision=2,
        payload={"scale": 1.15, "resolution": "merged"},
    )
    assert resolved["revision"] == 3
    assert sync.conflicts(principal) == []
    assert sync.pull(principal, cursor=cursor)["changes"][-1]["payload"]["resolution"] == "merged"


def test_guest_migration_is_transactional_and_preserves_collisions(tmp_path: Path):
    root = tmp_path / "api"
    accounts = AccountStore(root)
    sync = SyncStore(root)
    conversations = ConversationStore(root / "conversations")
    account_login = _verified_account(accounts, "migrate@example.com", "migration account password", "PC")
    account = accounts.verify_access(account_login["access_token"])
    guest_created = accounts.create_guest("Offline guest", "android")
    guest = accounts.verify_guest(guest_created["guest_token"])
    assert account is not None and guest is not None

    conversations.append(account["id"], "chat", "user", "account version")
    conversations.append(guest["id"], "chat", "user", "guest version")
    sync.push(
        account,
        [{"entity_type": "memory", "entity_id": "shared", "base_revision": 0, "payload": {"value": "account"}}],
    )
    sync.push(
        guest,
        [
            {"entity_type": "memory", "entity_id": "shared", "base_revision": 0, "payload": {"value": "guest"}},
            {"entity_type": "project", "entity_id": "guest-project", "base_revision": 0, "payload": {"name": "offline"}},
        ],
    )

    result = sync.migrate_guest_to_account(guest, account)
    assert result["moved_conversations"] == 1
    assert result["renamed_conversations"] == 1
    assert result["moved_entities"] == 1
    assert result["conflict_entities"] == 1
    assert accounts.verify_guest(guest_created["guest_token"]) is None

    original = conversations.get(account["id"], "chat")
    assert [item["content"] for item in original["messages"]] == ["account version"]
    with sqlite3.connect(root / "aurorafox.sqlite3") as connection:
        migrated_ids = [
            row[0]
            for row in connection.execute(
                "SELECT conversation_id FROM conversations WHERE owner=? ORDER BY conversation_id",
                (account["id"],),
            ).fetchall()
        ]
    assert len(migrated_ids) == 2
    guest_chat_id = next(value for value in migrated_ids if value != "chat")
    assert [item["content"] for item in conversations.get(account["id"], guest_chat_id)["messages"]] == ["guest version"]
    assert sync.pull(account)["changes"][-1]["entity_id"] == "guest-project"
    assert sync.conflicts(account)[0]["incoming"]["payload"] == {"value": "guest"}
    assert AuroraDatabase(root / "aurorafox.sqlite3").integrity_check()["ok"] is True


def test_concurrent_sync_writers_produce_one_winner_and_conflicts(tmp_path: Path):
    root = tmp_path / "api"
    accounts = AccountStore(root)
    sync = SyncStore(root)
    login = _verified_account(accounts, "race@example.com", "concurrent sync password", "PC")
    principal = accounts.verify_access(login["access_token"])
    assert principal is not None

    def write(index: int):
        return sync.push(
            principal,
            [{"entity_type": "project", "entity_id": "race", "base_revision": 0, "payload": {"writer": index}}],
        )["results"][0]

    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(write, range(8)))
    assert sum(item["status"] == "applied" for item in results) == 1
    assert sum(item["status"] == "conflict" for item in results) == 7
    assert len(sync.conflicts(principal)) == 7
    status = AuroraDatabase(root / "aurorafox.sqlite3").integrity_check()
    assert status["ok"] is True
    assert status["schema_version"] == SCHEMA_VERSION
