from __future__ import annotations

import json
import random
from collections import defaultdict, deque
from pathlib import Path


class AuroraPersonality:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.data = json.loads(self.path.read_text(encoding="utf-8"))
        self.mood = "neutral"
        self.last_used: dict[str, deque[str]] = defaultdict(lambda: deque(maxlen=3))

    def choose(self, category: str) -> str:
        items = self.data.get(category, [])
        if not items:
            return ""
        recent = self.last_used[category]
        filtered = [x for x in items if str(x.get("text", "")) not in recent] or items
        weights = [max(0.001, float(x.get("weight", 1.0))) for x in filtered]
        choice = random.choices(filtered, weights=weights, k=1)[0]
        text = str(choice.get("text", "")).strip()
        if text:
            recent.append(text)
        return text

    def greet(self) -> str: return self.choose("greeting")
    def thinking(self) -> str: return self.choose("thinking")
    def success(self) -> str: return self.choose("success")
    def error(self) -> str: return self.choose("error")
    def joke(self) -> str: return self.choose("joke")
    def wake_response(self) -> str: return self.choose("wake_response")
