from __future__ import annotations

import json
import os
import time
import uuid
from pathlib import Path
from typing import Any

from api.file_lock import file_lock


class LearningStore:
    def __init__(self, root: Path, max_events: int = 10000):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.path = self.root / "learning_events.jsonl"
        self.max_events = max(1000, max_events)
        self.lock_path = self.root / "learning_events.lock"

    def append(self, kind: str, payload: dict[str, Any]) -> dict[str, Any]:
        event = {
            "id": uuid.uuid4().hex,
            "kind": kind,
            "time": int(time.time()),
            "synced": False,
            "payload": payload,
        }
        line = json.dumps(event, ensure_ascii=False, separators=(",", ":"))
        with file_lock(self.lock_path):
            with self.path.open("a", encoding="utf-8", newline="\n") as fh:
                fh.write(line + "\n")
                fh.flush()
                os.fsync(fh.fileno())
        return event

    def pending(self, limit: int | None = 100) -> list[dict[str, Any]]:
        if not self.path.is_file():
            return []
        out: list[dict[str, Any]] = []
        with file_lock(self.lock_path):
            lines = self.path.read_text(encoding="utf-8").splitlines()
        for line in lines:
            try:
                event = json.loads(line)
            except (ValueError, TypeError) as exc:
                raise ValueError("Corrupt learning queue; restore from backup") from exc
            if not isinstance(event, dict) or not event.get("id"):
                raise ValueError("Invalid learning event")
            if event.get("synced", False):
                continue
            out.append(event)
            if limit is not None and len(out) >= max(1, limit):
                break
        return out

    def mark_synced(self, event_ids: set[str], owner: str | None = None) -> int:
        if not event_ids or not self.path.is_file():
            return 0
        with file_lock(self.lock_path):
            lines = self.path.read_text(encoding="utf-8").splitlines()
            changed = 0
            kept: list[str] = []
            for line in lines:
                try:
                    event = json.loads(line)
                except Exception:
                    kept.append(line)
                    continue
                payload = event.get("payload", {}) if isinstance(event, dict) else {}
                owns_event = owner is None or (isinstance(payload, dict) and payload.get("api_key_id") == owner)
                if isinstance(event, dict) and str(event.get("id", "")) in event_ids and owns_event and not event.get("synced", False):
                    event["synced"] = True
                    changed += 1
                kept.append(json.dumps(event, ensure_ascii=False, separators=(",", ":")))
            # Bound acknowledged history only. Never drop unsent or damaged records.
            retained: list[str] = []
            synced_count = 0
            for line in reversed(kept):
                try:
                    item = json.loads(line)
                except ValueError:
                    retained.append(line)
                    continue
                if isinstance(item, dict) and item.get("synced", False):
                    synced_count += 1
                    if synced_count > self.max_events:
                        continue
                retained.append(line)
            kept = list(reversed(retained))
            tmp = self.path.with_suffix(".tmp")
            with tmp.open("w", encoding="utf-8", newline="\n") as fh:
                fh.write("\n".join(kept) + ("\n" if kept else ""))
                fh.flush()
                os.fsync(fh.fileno())
            tmp.replace(self.path)
            if os.name != "nt":
                fd = os.open(self.root, os.O_RDONLY)
                try:
                    os.fsync(fd)
                finally:
                    os.close(fd)
            return changed
