from __future__ import annotations

from pathlib import Path
from typing import Any

from api.learning_store import LearningStore
from api.runtime_bridge import AuroraRuntimeBridge


class LearningSynchronizer:
    def __init__(self, root: Path, bridge: AuroraRuntimeBridge):
        self.store = LearningStore(root)
        self.bridge = bridge

    def record(self, kind: str, payload: dict[str, Any], try_sync: bool = True) -> dict[str, Any]:
        event = self.store.append(kind, payload)
        synced = False
        if try_sync:
            try:
                result = self.bridge.learn(event)
                synced = bool(result.get("ok", False))
            except Exception:
                synced = False
        if synced:
            self.store.mark_synced({str(event["id"])})
        return {"event_id": event["id"], "synced": synced}

    def feedback(self, payload: dict[str, Any], try_sync: bool = True) -> dict[str, Any]:
        event = self.store.append("feedback", payload)
        synced = False
        bridge_result: dict[str, Any] = {}
        if try_sync:
            try:
                bridge_result = self.bridge.feedback(payload)
                synced = bool(bridge_result.get("ok", False))
            except Exception:
                synced = False
        if synced:
            self.store.mark_synced({str(event["id"])})
        return {
            "event_id": event["id"],
            "synced": synced,
            "bridge": bridge_result,
        }

    def flush(self, limit: int = 100) -> dict[str, Any]:
        events = self.store.pending(limit)
        if not events:
            return {"ok": True, "pending": 0, "synced": 0}
        synced_ids: set[str] = set()
        failed = 0
        for event in events:
            try:
                if str(event.get("kind", "")) == "feedback":
                    payload = event.get("payload", {}) if isinstance(event.get("payload"), dict) else {}
                    result = self.bridge.feedback(payload)
                else:
                    result = self.bridge.learn(event)
                if result.get("ok", False):
                    synced_ids.add(str(event.get("id", "")))
                else:
                    failed += 1
            except Exception:
                failed += 1
                break
        changed = self.store.mark_synced(synced_ids)
        return {
            "ok": failed == 0,
            "attempted": len(events),
            "synced": changed,
            "failed": failed,
            "pending": max(0, len(events) - changed),
        }
