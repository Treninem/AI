from __future__ import annotations

from pathlib import Path

from api.learning_sync import LearningSynchronizer


class FakeBridge:
    def __init__(self, fail: bool = False) -> None:
        self.fail = fail
        self.learn_calls: list[dict] = []
        self.feedback_calls: list[dict] = []

    def learn(self, payload: dict) -> dict:
        self.learn_calls.append(payload)
        if self.fail:
            return {"ok": False, "error": "offline"}
        return {"ok": True, "learned": True}

    def feedback(self, payload: dict) -> dict:
        self.feedback_calls.append(payload)
        if self.fail:
            return {"ok": False, "error": "offline"}
        return {"ok": True, "feedback_recorded": True}


def test_private_api_interaction_is_not_queued(tmp_path: Path) -> None:
    bridge = FakeBridge()
    sync = LearningSynchronizer(tmp_path, bridge)
    result = sync.record(
        "api_interaction",
        {"metadata": {"share_for_learning": False}, "content": "private"},
    )
    assert result["skipped_private"] is True
    assert result["event_id"] == ""
    assert bridge.learn_calls == []


def test_opted_in_learning_syncs_immediately(tmp_path: Path) -> None:
    bridge = FakeBridge()
    sync = LearningSynchronizer(tmp_path, bridge)
    result = sync.record(
        "api_interaction",
        {"metadata": {"share_for_learning": True}, "content": "shared"},
    )
    assert result["synced"] is True
    assert len(bridge.learn_calls) == 1
    assert sync.status()["pending"] == 0


def test_failed_sync_stays_pending_and_flush_retries(tmp_path: Path) -> None:
    bridge = FakeBridge(fail=True)
    sync = LearningSynchronizer(tmp_path, bridge)
    result = sync.record("external_knowledge", {"content": "knowledge"}, try_sync=True)
    assert result["synced"] is False
    assert sync.status()["pending"] == 1

    bridge.fail = False
    flushed = sync.flush(10)
    assert flushed["ok"] is True
    assert flushed["synced"] == 1
    assert flushed["pending"] == 0
    assert len(bridge.learn_calls) == 2


def test_feedback_is_retried(tmp_path: Path) -> None:
    bridge = FakeBridge(fail=True)
    sync = LearningSynchronizer(tmp_path, bridge)
    result = sync.feedback({"score": 0.5}, try_sync=True)
    assert result["synced"] is False
    assert sync.status()["pending"] == 1

    bridge.fail = False
    flushed = sync.flush(10)
    assert flushed["synced"] == 1
    assert len(bridge.feedback_calls) == 2
