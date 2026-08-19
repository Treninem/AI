from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path
from typing import Any


class ConversationStore:
    def __init__(self, root: Path, max_messages: int = 120):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.max_messages = max(20, max_messages)

    def _path(self, owner: str, conversation_id: str) -> Path:
        key = hashlib.sha256(f"{owner}:{conversation_id}".encode("utf-8")).hexdigest()
        return self.root / f"{key}.json"

    def get(self, owner: str, conversation_id: str) -> dict[str, Any]:
        path = self._path(owner, conversation_id)
        if not path.is_file():
            return {
                "owner": owner,
                "conversation_id": conversation_id,
                "messages": [],
                "created_at": int(time.time()),
                "updated_at": int(time.time()),
            }
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict) and isinstance(data.get("messages"), list):
                return data
        except Exception:
            pass
        return {
            "owner": owner,
            "conversation_id": conversation_id,
            "messages": [],
            "created_at": int(time.time()),
            "updated_at": int(time.time()),
        }

    def append(self, owner: str, conversation_id: str, role: str, content: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        data = self.get(owner, conversation_id)
        data["messages"].append({
            "role": role,
            "content": content,
            "metadata": metadata or {},
            "time": int(time.time()),
        })
        data["messages"] = data["messages"][-self.max_messages :]
        data["updated_at"] = int(time.time())
        path = self._path(owner, conversation_id)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tmp.replace(path)
        return data

    def clear(self, owner: str, conversation_id: str) -> bool:
        path = self._path(owner, conversation_id)
        if not path.is_file():
            return False
        path.unlink(missing_ok=True)
        return True

    def context(self, owner: str, conversation_id: str, limit: int = 24) -> list[dict[str, Any]]:
        messages = self.get(owner, conversation_id).get("messages", [])
        out: list[dict[str, Any]] = []
        for item in messages[-max(1, limit) :]:
            if not isinstance(item, dict):
                continue
            role = str(item.get("role", ""))
            if role not in {"user", "assistant", "system"}:
                continue
            out.append({"role": role, "content": str(item.get("content", ""))})
        return out
