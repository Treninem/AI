from __future__ import annotations

import threading
from pathlib import Path
from typing import Any

from api.learning_store import LearningStore
from api.runtime_bridge import AuroraRuntimeBridge


class LearningSynchronizer:
    def __init__(self, root: Path, bridge: AuroraRuntimeBridge):
        self.store = LearningStore(root)
        self.bridge = bridge
        # Bridge delivery has an at-least-once durability boundary: an event is
        # durable in SQLite before it is sent and marked synced only after the
        # bridge acknowledges it. Serializing that short state transition keeps
        # request-triggered delivery and background flushes from replaying the
        # same pending event concurrently.
        self._delivery_lock = threading.RLock()

    @staticmethod
    def _implicit_interaction_can_learn(kind: str, payload: dict[str, Any]) -> bool:
        if kind != "api_interaction":
            return True
        metadata = payload.get("metadata", {})
        return isinstance(metadata, dict) and bool(metadata.get("share_for_learning", False))

    def record(self, kind: str, payload: dict[str, Any], try_sync: bool = True) -> dict[str, Any]:
        # Ordinary chat is private by default. The API server may call record()
        # for an Ollama fallback interaction, but that raw request/answer must
        # not enter the shared AuroraFox knowledge store unless the client
        # explicitly opted in with metadata.share_for_learning=true.
        if not self._implicit_interaction_can_learn(kind, payload):
            return {
                "event_id": "",
                "synced": False,
                "bridge": {},
                "skipped_private": True,
            }

        if not try_sync:
            event = self.store.append(kind, payload)
            return {
                "event_id": event["id"],
                "synced": False,
                "bridge": {},
            }

        # Append and first delivery share the same lock used by flush(). Without
        # this, flush() could observe the freshly appended row before this call
        # marks it synced and deliver it a second time.
        with self._delivery_lock:
            event = self.store.append(kind, payload)
            synced = False
            bridge_result: dict[str, Any] = {}
            try:
                bridge_result = self.bridge.learn(payload)
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

    def feedback(self, payload: dict[str, Any], try_sync: bool = True) -> dict[str, Any]:
        # Feedback is kept inside the API-local learning log. The Godot bridge
        # independently decides whether it may promote raw data into shared
        # learning; default is private unless metadata.share_for_learning=true.
        if not try_sync:
            event = self.store.append("feedback", payload)
            return {
                "event_id": event["id"],
                "synced": False,
                "bridge": {},
            }

        with self._delivery_lock:
            event = self.store.append("feedback", payload)
            synced = False
            bridge_result: dict[str, Any] = {}
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
        # Only one replayer may select pending rows and perform bridge side
        # effects at a time. SQLite protects storage consistency; this lock
        # additionally protects side-effect uniqueness inside this API process.
        with self._delivery_lock:
            events = self.store.pending(limit)
            if not events:
                return {"ok": True, "pending": 0, "synced": 0, "attempted": 0, "failed": 0}
            synced_ids: set[str] = set()
            failed = 0
            for event in events:
                try:
                    payload = event.get("payload", {}) if isinstance(event.get("payload"), dict) else {}
                    if str(event.get("kind", "")) == "feedback":
                        result = self.bridge.feedback(payload)
                    else:
                        result = self.bridge.learn(payload)
                    if result.get("ok", False):
                        synced_ids.add(str(event.get("id", "")))
                    else:
                        failed += 1
                except Exception:
                    failed += 1
                    break
            changed = self.store.mark_synced(synced_ids)
            remaining = int(self.store.status().get("pending", 0))
            return {
                "ok": failed == 0,
                "attempted": len(events),
                "synced": changed,
                "failed": failed,
                "pending": remaining,
            }

    def status(self) -> dict[str, Any]:
        return self.store.status()
