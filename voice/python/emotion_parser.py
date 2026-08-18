from __future__ import annotations

import re

EMOTIONS = {"neutral","happy","excited","thinking","focused","serious","warning","sad","confused","sleepy","playful","success","error"}

RULES = [
    ("warning", [r"\bвнимание\b", r"предупреж", r"опасн", r"слишком высок", "⚠"]),
    ("error", [r"ошибк", r"не удалось", r"сломал", r"не работает", r"problem", r"failed"]),
    ("success", [r"\bготово\b", r"исправил", r"успеш", r"всё работает", r"запускается"]),
    ("thinking", [r"\bхм\b", r"проверя", r"разбер", r"интересн", "🤔"]),
    ("confused", [r"не хватает контекст", r"уточни", r"не до конца понят"]),
    ("sad", [r"сожале", r"груст", "😔"]),
    ("excited", [r"отлично!", r"супер!", r"вау", "😄"]),
    ("playful", [r"лисий", r"хвост", "🦊"]),
    ("happy", [r"рад", r"приятн", "😊", "❤️"]),
]


def detect_emotion(text: str, default: str = "neutral") -> dict:
    lower = (text or "").lower()
    for emotion, patterns in RULES:
        hits = sum(1 for p in patterns if re.search(p, lower, re.I))
        if hits:
            intensity = min(0.92, 0.54 + 0.12 * hits)
            return {"emotion": emotion, "intensity": intensity}
    if "?" in lower and len(lower) < 180:
        return {"emotion": "focused", "intensity": 0.52}
    return {"emotion": default if default in EMOTIONS else "neutral", "intensity": 0.45}
