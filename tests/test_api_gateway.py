from __future__ import annotations

from pathlib import Path

from api.auth import DEFAULT_SCOPES, KeyStore, allows
from api.conversation_store import ConversationStore
from api.learning_sync import LearningSynchronizer


class FakeBridge:
    def __init__(self):
        self.online = False
        self.learned = []
        self.feedback_items = []

    def learn(self, payload):
        if not self.online:
            raise ConnectionError("bridge offline")
        self.learned.append(payload)
        return {"ok": True}

    def feedback(self, payload):
        if not self.online:
            raise ConnectionError("bridge offline")
        self.feedback_items.append(payload)
        return {"ok": True}


def test_default_api_key_can_chat_and_train_but_not_run_tools(tmp_path: Path):
    store = KeyStore(tmp_path / "api")
    token, record = store.create("Telegram bot")
    verified = store.verify(token)
    assert verified is not None
    assert allows(verified, "chat")
    assert allows(verified, "feedback")
    assert allows(verified, "memory.read")
    assert allows(verified, "memory.write")
    assert not allows(verified, "tools.run")
    assert set(DEFAULT_SCOPES).issubset(set(record["scopes"]))


def test_revoked_key_is_rejected(tmp_path: Path):
    store = KeyStore(tmp_path / "api")
    token, record = store.create("Site")
    assert store.verify(token) is not None
    assert store.revoke(str(record["id"]))
    assert store.verify(token) is None


def test_conversations_are_isolated_by_api_key_owner(tmp_path: Path):
    store = ConversationStore(tmp_path / "conversations")
    store.append("key-a", "same-chat", "user", "A")
    store.append("key-b", "same-chat", "user", "B")
    assert store.context("key-a", "same-chat")[-1]["content"] == "A"
    assert store.context("key-b", "same-chat")[-1]["content"] == "B"


def test_learning_is_durable_while_godot_is_offline_and_replayed_later(tmp_path: Path):
    bridge = FakeBridge()
    sync = LearningSynchronizer(tmp_path / "api", bridge)
    payload = {
        "source": "telegram",
        "kind": "api_interaction",
        "content": "User prefers concise code examples",
        "importance": 0.8,
        "confidence": 0.9,
    }
    result = sync.record("api_interaction", payload, True)
    assert result["synced"] is False
    assert sync.status()["pending"] == 1

    bridge.online = True
    flushed = sync.flush(100)
    assert flushed["ok"] is True
    assert flushed["synced"] == 1
    assert sync.status()["pending"] == 0
    assert bridge.learned[0]["content"] == payload["content"]


def test_feedback_replays_into_agent_experience_bridge(tmp_path: Path):
    bridge = FakeBridge()
    sync = LearningSynchronizer(tmp_path / "api", bridge)
    payload = {
        "conversation_id": "tg-123",
        "source": "telegram",
        "message": "question",
        "answer": "bad answer",
        "score": -1.0,
        "corrected_answer": "correct answer",
        "note": "user correction",
    }
    first = sync.feedback(payload, True)
    assert first["synced"] is False
    bridge.online = True
    flushed = sync.flush(100)
    assert flushed["synced"] == 1
    assert bridge.feedback_items[0]["corrected_answer"] == "correct answer"
