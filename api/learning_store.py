from __future__ import annotations

import json
import threading
import time
import uuid
from pathlib import Path
from typing import Any


class LearningStore:
    def __init__(self, root: Path, max_events: int = 10000):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.path = self.root / "learning_events.jsonl"
        self.max_events = max(1000, max_events)
        self._lock = threading.Lock()

    def append(self, kind: str, payload: dict[str, Any]) -> dict[str, Any]:
        event = {
            "id": uuid.uuid4().hex,
            "kind": kind,
            "time": int(time.time()),
            "synced": False,
            "payload": payload,
        }
        line = json.dumps(event, ensure_ascii=False, separators=(",", ":"))
        with self._lock:
            with self.path.open("a", encoding="utf-8", newline="\n") as fh:
                fh.write(line + "\n")
        return event

    def pending(self, limit: int = 100) -> list[dict[str, Any]]:
        if not self.path.is_file():
            return []
        out: list[dict[str, Any]] = []
        with self._lock:
            try:
                lines = self.path.read_text(encoding="utf-8").splitlines()
            except Exception:
                return []
        for line in lines:
            try:
                event = json.loads(line)
            except Exception:
                continue
            if not isinstance(event, dict) or event.get("synced", False):
                continue
            out.append(event)
            if len(out) >= max(1, limit):
                break
        return out

    def mark_synced(self, event_ids: set[str]) -> int:
        if not event_ids or not self.path.is_file():
            return 0
        with self._lock:
            try:
                lines = self.path.read_text(encoding="utf-8").splitlines()
            except Exception:
                return 0
            changed = 0
            kept: list[str] = []
            for line in lines:
                try:
                    event = json.loads(line)
                except Exception:
                    kept.append(line)
                    continue
                if isinstance(event, dict) and str(event.get("id", "")) in event_ids:
                    event["synced"] = True
                    changed += 1
                kept.append(json.dumps(event, ensure_ascii=False, separators=(",", ":")))
            # Keep the recent tail so the file remains bounded.
            if len(kept) > self.max_events:
                kept = kept[-self.max_events :]
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text("\n".join(kept) + ("\n" if kept else ""), encoding="utf-8")
            tmp.replace(self.path)
            return changed
