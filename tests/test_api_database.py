from __future__ import annotations

import hashlib
import json
import sqlite3
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest

from api.auth import KeyStore
from api.conversation_store import ConversationStore
from api.database import AuroraDatabase, SCHEMA_VERSION
from api.learning_store import LearningStore


def test_database_schema_is_wal_and_integrity_checked(tmp_path: Path):
    database = AuroraDatabase(tmp_path / "api" / "aurorafox.sqlite3")
    status = database.integrity_check()
    assert status["ok"] is True
    assert status["schema_version"] == SCHEMA_VERSION
    assert status["journal_mode"] == "wal"
    assert status["integrity"] == "ok"
    assert status["foreign_key_errors"] == 0


def test_legacy_api_state_migrates_once_into_single_database(tmp_path: Path):
    api_root = tmp_path / "api"
    conversations_root = api_root / "conversations"
    conversations_root.mkdir(parents=True)

    token = "af_live_legacy-test"
    legacy_key = {
        "id": "legacy-key",
        "name": "Legacy integration",
        "token_hash": hashlib.sha256(token.encode("utf-8")).hexdigest(),
        "scopes": ["chat", "memory.read"],
        "created_at": 123,
        "revoked": False,
    }
    (api_root / "keys.json").write_text(
        json.dumps({"keys": [legacy_key]}, ensure_ascii=False), encoding="utf-8"
    )
    (conversations_root / "legacy.json").write_text(
        json.dumps(
            {
                "owner": "legacy-key",
                "conversation_id": "conversation-1",
                "created_at": 100,
                "updated_at": 110,
                "messages": [
                    {"role": "user", "content": "hello", "metadata": {"source": "old"}, "time": 101},
                    {"role": "assistant", "content": "hi", "metadata": {}, "time": 102},
                ],
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    legacy_event = {
        "id": "event-1",
        "kind": "feedback",
        "time": 150,
        "synced": False,
        "payload": {"note": "legacy queue"},
    }
    (api_root / "learning_events.jsonl").write_text(
        json.dumps(legacy_event, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    keys = KeyStore(api_root)
    conversations = ConversationStore(conversations_root)
    learning = LearningStore(api_root)

    assert keys.verify(token)["id"] == "legacy-key"
    assert [row["content"] for row in conversations.context("legacy-key", "conversation-1")] == ["hello", "hi"]
    assert learning.pending(10)[0]["id"] == "event-1"

    database = AuroraDatabase(api_root / "aurorafox.sqlite3")
    status = database.integrity_check()
    assert status["ok"] is True
    assert status["counts"] == {
        "api_keys": 1,
        "conversations": 1,
        "messages": 2,
        "learning_events": 1,
        "learning_pending": 1,
        "accounts": 0,
        "guests": 0,
        "devices": 0,
        "auth_sessions": 0,
        "sync_entities": 0,
        "sync_conflicts_open": 0,
    }

    # Re-instantiation is idempotent and does not duplicate legacy state.
    KeyStore(api_root)
    ConversationStore(conversations_root)
    LearningStore(api_root)
    assert AuroraDatabase(api_root / "aurorafox.sqlite3").integrity_check()["counts"] == status["counts"]


def test_bootstrap_key_creation_is_atomic_across_store_instances(tmp_path: Path):
    root = tmp_path / "api"
    stores = [KeyStore(root) for _ in range(8)]

    with ThreadPoolExecutor(max_workers=8) as executor:
        tokens = list(executor.map(lambda store: store.ensure_bootstrap_key(), stores))

    created = [token for token in tokens if token]
    assert len(created) == 1
    assert stores[0].verify(created[0]) is not None
    status = AuroraDatabase(root / "aurorafox.sqlite3").integrity_check()
    assert status["ok"] is True
    assert status["counts"]["api_keys"] == 1

    mirror = json.loads((root / "keys.json").read_text(encoding="utf-8"))
    assert len(mirror["keys"]) == 1
    assert "token" not in mirror["keys"][0]
    assert mirror["keys"][0]["token_hash"] == hashlib.sha256(created[0].encode("utf-8")).hexdigest()


def test_bootstrap_key_recovers_when_insert_fails_after_raw_token_is_durable(tmp_path: Path, monkeypatch):
    root = tmp_path / "api"
    store = KeyStore(root)
    observed: dict[str, str] = {}

    def fail_after_raw_token(connection, record):
        # The recoverable raw material must already be durable before the DB hash
        # can be inserted/committed. Inject a failure at exactly that boundary.
        assert store.bootstrap_path.is_file()
        raw = store.bootstrap_path.read_text(encoding="utf-8").strip()
        assert raw.startswith("af_admin_")
        assert hashlib.sha256(raw.encode("utf-8")).hexdigest() == str(record["token_hash"])
        observed["raw"] = raw
        raise RuntimeError("injected bootstrap insert failure")

    monkeypatch.setattr(store, "_insert_bootstrap_record", fail_after_raw_token)
    with pytest.raises(RuntimeError, match="injected bootstrap insert failure"):
        store.ensure_bootstrap_key()

    # Normal exception rollback removes the provisional raw token and leaves no
    # committed active key. A hard process crash would leave only the provisional
    # file; SQLite rolls back the open transaction and the next start overwrites it.
    assert observed["raw"].startswith("af_admin_")
    assert not store.bootstrap_path.exists()
    with store.database.connection() as connection:
        assert int(connection.execute("SELECT COUNT(*) FROM api_keys WHERE revoked=0").fetchone()[0]) == 0

    recovered_store = KeyStore(root)
    recovered = recovered_store.ensure_bootstrap_key()
    assert recovered is not None
    assert recovered != observed["raw"]
    assert recovered_store.bootstrap_path.read_text(encoding="utf-8").strip() == recovered
    assert recovered_store.verify(recovered) is not None
    with recovered_store.database.connection() as connection:
        assert int(connection.execute("SELECT COUNT(*) FROM api_keys WHERE revoked=0").fetchone()[0]) == 1


def test_concurrent_conversation_writes_do_not_lose_messages(tmp_path: Path):
    store = ConversationStore(tmp_path / "api" / "conversations", max_messages=200)

    def write(index: int) -> None:
        store.append("owner", "shared", "user", f"message-{index}", {"index": index})

    with ThreadPoolExecutor(max_workers=12) as executor:
        list(executor.map(write, range(120)))

    data = store.get("owner", "shared")
    contents = {item["content"] for item in data["messages"]}
    assert len(data["messages"]) == 120
    assert contents == {f"message-{index}" for index in range(120)}

    mirror = json.loads(store._path("owner", "shared").read_text(encoding="utf-8"))
    assert len(mirror["messages"]) == 120
    assert {item["content"] for item in mirror["messages"]} == contents
    assert store.database.integrity_check()["ok"] is True


def test_learning_queue_uses_sqlite_state_and_rollback_mirror(tmp_path: Path):
    root = tmp_path / "api"
    store = LearningStore(root)
    first = store.append("feedback", {"value": 1})
    second = store.append("external_knowledge", {"value": 2})
    assert [event["id"] for event in store.pending(10)] == [first["id"], second["id"]]

    assert store.mark_synced({first["id"]}) == 1
    assert [event["id"] for event in store.pending(10)] == [second["id"]]
    status = store.status()
    assert status["total"] == 2
    assert status["pending"] == 1
    assert status["pending_protected"] is True
    assert status["over_capacity"] == 0

    mirror = [json.loads(line) for line in (root / "learning_events.jsonl").read_text(encoding="utf-8").splitlines()]
    by_id = {event["id"]: event for event in mirror}
    assert by_id[first["id"]]["synced"] is True
    assert by_id[second["id"]]["synced"] is False
    assert AuroraDatabase(root / "aurorafox.sqlite3").integrity_check()["ok"] is True


def test_learning_queue_never_evicts_unsynced_events_when_offline(tmp_path: Path):
    root = tmp_path / "api"
    store = LearningStore(root)
    # Production keeps a much larger floor; reduce it only inside this regression
    # test so the overflow policy is exercised without thousands of writes.
    store.max_events = 3

    first = store.append("feedback", {"value": 1})
    second = store.append("feedback", {"value": 2})
    third = store.append("feedback", {"value": 3})
    assert store.mark_synced({first["id"], second["id"]}) == 2

    fourth = store.append("external_knowledge", {"value": 4})
    fifth = store.append("external_knowledge", {"value": 5})
    # The two old synced rows are safe to evict, leaving only pending work.
    assert [event["id"] for event in store.pending(10)] == [third["id"], fourth["id"], fifth["id"]]
    assert store.status()["total"] == 3

    sixth = store.append("external_knowledge", {"value": 6})
    # With no synced history left, capacity is a soft limit: durability wins and
    # every pending item remains in SQLite and in the rollback-compatible JSONL.
    pending_ids = [event["id"] for event in store.pending(10)]
    assert pending_ids == [third["id"], fourth["id"], fifth["id"], sixth["id"]]
    status = store.status()
    assert status["pending"] == 4
    assert status["total"] == 4
    assert status["over_capacity"] == 1
    assert status["pending_protected"] is True

    store._rewrite_legacy_mirror()
    mirror = [json.loads(line) for line in (root / "learning_events.jsonl").read_text(encoding="utf-8").splitlines()]
    assert [event["id"] for event in mirror if not event["synced"]] == pending_ids

    # Once part of the backlog is synchronized, compaction can safely return the
    # database to its configured history bound without dropping remaining work.
    assert store.mark_synced({third["id"], fourth["id"]}) == 2
    assert [event["id"] for event in store.pending(10)] == [fifth["id"], sixth["id"]]
    assert store.status()["total"] == 3
    assert store.status()["over_capacity"] == 0
    assert store.database.integrity_check()["ok"] is True


def test_operational_snapshot_is_complete_and_integrity_verified(tmp_path: Path):
    api_root = tmp_path / "api"
    keys = KeyStore(api_root)
    token, key = keys.create("Rollback identity", ["chat", "memory.read"])
    conversations = ConversationStore(api_root / "conversations")
    conversations.append(str(key["id"]), "rollback-chat", "user", "preserve me")
    learning = LearningStore(api_root)
    event = learning.append("feedback", {"note": "pending rollback work"})

    live = AuroraDatabase(api_root / "aurorafox.sqlite3")
    destination = tmp_path / "root-only-rollback" / "preupdate.sqlite3"
    snapshot = live.create_snapshot(destination)

    assert snapshot["ok"] is True
    assert snapshot["schema_version"] == SCHEMA_VERSION
    assert snapshot["integrity"] == "ok"
    assert snapshot["foreign_key_errors"] == 0
    assert snapshot["bytes"] > 0
    assert destination.is_file()

    # The operational rollback copy is intentionally complete. It stays outside
    # the exportable owner-backup root, so retaining token hashes here is needed
    # to restore authentication exactly after a failed schema/deployment update.
    with sqlite3.connect(destination) as connection:
        assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert connection.execute("PRAGMA foreign_key_check").fetchall() == []
        assert connection.execute("SELECT COUNT(*) FROM api_keys").fetchone()[0] == 1
        assert connection.execute("SELECT COUNT(*) FROM conversations").fetchone()[0] == 1
        assert connection.execute("SELECT COUNT(*) FROM conversation_messages").fetchone()[0] == 1
        assert connection.execute("SELECT COUNT(*) FROM learning_events WHERE synced=0").fetchone()[0] == 1
        stored_hash = connection.execute("SELECT token_hash FROM api_keys WHERE id=?", (str(key["id"]),)).fetchone()[0]
    assert stored_hash == hashlib.sha256(token.encode("utf-8")).hexdigest()
    assert learning.pending(10)[0]["id"] == event["id"]
