from __future__ import annotations

import json
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Callable


class LearningQueue:
    """Durable API learning queue.

    Events are appended before bridge delivery. Successful bridge delivery marks
    them as synced. If the Godot runtime is offline, events remain on disk and
    are replayed later.
    """

    def __init__(self, path: Path):
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        if not self.path.exists():
            self._write({"events": []})

    def _read(self) -> dict[str, Any]:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            if isinstance(data, dict) and isinstance(data.get("events"), list):
                return data
        except Exception:
            pass
        return {"events": []}

    def _write(self, data: dict[str, Any]) -> None:
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tmp.replace(self.path)

    def append(self, kind: str, payload: dict[str, Any]) -> dict[str, Any]:
        event = {
            "id": uuid.uuid4().hex,
            "kind": kind,
            "payload": payload,
            "created_at": time.time(),
            "attempts": 0,
            "last_error": "",
            "synced": False,
        }
        with self._lock:
            data = self._read()
            data["events"].append(event)
            if len(data["events"]) > 10000:
                synced = [x for x in data["events"] if x.get("synced")]
                pending = [x for x in data["events"] if not x.get("synced")]
                data["events"] = synced[-1000:] + pending[-9000:]
            self._write(data)
        return event

    def mark_synced(self, event_id: str) -> None:
        with self._lock:
            data = self._read()
            for event in data["events"]:
                if str(event.get("id")) == event_id:
                    event["synced"] = True
                    event["synced_at"] = time.time()
                    event["last_error"] = ""
                    break
            self._write(data)

    def mark_failed(self, event_id: str, error: str) -> None:
        with self._lock:
            data = self._read()
            for event in data["events"]:
                if str(event.get("id")) == event_id:
                    event["attempts"] = int(event.get("attempts", 0)) + 1
                    event["last_error"] = str(error)[:2000]
                    break
            self._write(data)

    def pending(self, limit: int = 100) -> list[dict[str, Any]]:
        with self._lock:
            data = self._read()
            return [dict(x) for x in data["events"] if not x.get("synced")][: max(1, limit)]

    def stats(self) -> dict[str, int]:
        with self._lock:
            data = self._read()
            total = len(data["events"])
            pending = sum(1 for x in data["events"] if not x.get("synced"))
            return {"total": total, "pending": pending, "synced": total - pending}

    def flush(self, deliver: Callable[[dict[str, Any]], dict[str, Any]], limit: int = 100) -> dict[str, Any]:
        sent = 0
        failed = 0
        for event in self.pending(limit):
            try:
                result = deliver(event)
                if result.get("ok", False):
                    self.mark_synced(str(event["id"]))
                    sent += 1
                else:
                    self.mark_failed(str(event["id"]), str(result.get("error", "bridge rejected event")))
                    failed += 1
                    break
            except Exception as exc:
                self.mark_failed(str(event["id"]), str(exc))
                failed += 1
                break
        return {"ok": failed == 0, "sent": sent, "failed": failed, **self.stats()}
