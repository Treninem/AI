from __future__ import annotations

import sqlite3
import tempfile
import time
from pathlib import Path

import pytest
from pydantic import ValidationError

from api.community_learning import CommunityEventRequest, CommunityLearningStore


def _dialogue(**overrides):
    data = {
        "kind": "dialogue_pattern",
        "language": "ru",
        "topic": "informal_conversation",
        "pattern": "короткая дружеская шутка после взаимного поддразнивания",
        "features": ["banter", "emoji_context"],
        "labels": {
            "intent": "banter",
            "style": "informal",
            "understand_only": False,
            "spam": False,
            "advertising": False,
            "pii_detected": False,
        },
        "quality": 0.91,
        "confidence": 0.88,
        "diversity_bucket": 4,
        "observations": 17,
    }
    data.update(overrides)
    return CommunityEventRequest.model_validate(data)


def test_dialogue_contract_contains_no_identity_fields() -> None:
    event = _dialogue()
    payload = event.model_dump()
    serialized = str(payload).lower()
    for forbidden in ("chat_id", "user_id", "message_id", "username", "conversation_id", "raw_text"):
        assert forbidden not in serialized


def test_rejects_email_phone_handle_url_and_secret() -> None:
    bad = [
        "напиши user@example.com",
        "позвони +7 999 123-45-67",
        "спроси @private_user",
        "смотри https://example.com/private",
        "token=abcdefghijklmnop123456",
    ]
    for text in bad:
        with pytest.raises(ValidationError):
            _dialogue(pattern=text)


def test_rejects_event_explicitly_marked_as_pii() -> None:
    with pytest.raises(ValidationError):
        _dialogue(labels={"intent": "banter", "pii_detected": True})


def test_spam_cannot_become_dialogue_exemplar() -> None:
    with pytest.raises(ValidationError):
        _dialogue(labels={"intent": "promo", "spam": True, "advertising": True})


def test_topic_trend_is_never_truth_without_external_verification() -> None:
    with pytest.raises(ValidationError):
        CommunityEventRequest.model_validate(
            {
                "kind": "topic_trend",
                "topic": "new software release",
                "quality": 0.8,
                "confidence": 0.7,
                "diversity_bucket": 5,
                "labels": {"requires_external_verification": False},
            }
        )
    valid = CommunityEventRequest.model_validate(
        {
            "kind": "topic_trend",
            "topic": "new software release",
            "quality": 0.8,
            "confidence": 0.7,
            "diversity_bucket": 5,
            "labels": {"requires_external_verification": True},
        }
    )
    assert valid.labels.requires_external_verification is True


def test_mailbox_is_durable_deduplicated_and_acknowledged() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        store = CommunityLearningStore(root)
        first = store.append(_dialogue())
        second = store.append(_dialogue())
        assert first["duplicate"] is False
        assert second["duplicate"] is True
        assert second["id"] == first["id"]

        pulled = store.pull(limit=10, lease_seconds=60)
        assert [row["id"] for row in pulled] == [first["id"]]
        assert pulled[0]["payload"]["schema"] == "aurorafox.impuls.community.v1"
        assert store.pull(limit=10, lease_seconds=60) == []

        changed = store.ack([first["id"]], "accepted", "curated")
        assert changed == 1
        status = store.status()
        assert status["accepted"] == 1
        assert status["pending"] == 0
        assert status["stable_core_promotion"] is False
        assert status["weight_training"] is False


def test_expired_lease_is_redelivered_at_least_once() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        store = CommunityLearningStore(Path(tmp))
        created = store.append(_dialogue())
        pulled = store.pull(limit=1, lease_seconds=30)
        assert pulled[0]["delivery_count"] == 1

        with sqlite3.connect(store.path) as connection:
            connection.execute(
                "UPDATE community_events SET lease_until=? WHERE id=?",
                (int(time.time()) - 1, created["id"]),
            )
            connection.commit()

        retry = store.pull(limit=1, lease_seconds=30)
        assert retry[0]["id"] == created["id"]
        assert retry[0]["delivery_count"] == 2


def test_rejected_and_quarantined_are_terminal_not_promoted() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        store = CommunityLearningStore(Path(tmp))
        rejected = store.append(_dialogue(pattern="абстрактный низкокачественный шаблон"))
        quarantined = store.append(_dialogue(pattern="сомнительный контекст для отдельной проверки"))
        store.ack([rejected["id"]], "rejected", "low_quality")
        store.ack([quarantined["id"]], "quarantined", "privacy_risk")
        status = store.status()
        assert status["rejected"] == 1
        assert status["quarantined"] == 1
        assert store.pull(limit=10) == []
