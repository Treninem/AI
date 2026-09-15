from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import requests

from api.local_core_client import AuroraKnowledgeFallback, AuroraLocalCoreClient


CHAT_PRIORITY = [
    "qwen3", "gemma3", "llama3.3", "llama3.2", "llama3.1", "llama3",
    "mistral", "deepseek", "phi4", "qwen2.5", "qwen2", "gemma2", "gemma", "llama",
]


def is_chat_model(name: str) -> bool:
    lower = name.lower().strip()
    if not lower:
        return False
    return not any(marker in lower for marker in (
        "embed", "embedding", "nomic-embed", "mxbai-embed", "bge-", "snowflake-arctic-embed"
    ))


def choose_chat_model(installed: list[str], preferred: str = "qwen3:8b") -> str:
    if preferred in installed and is_chat_model(preferred):
        return preferred
    best = ""
    best_score = -100000
    for candidate in installed:
        if not is_chat_model(candidate):
            continue
        lower = candidate.lower()
        score = 10
        for index, prefix in enumerate(CHAT_PRIORITY):
            if lower.startswith(prefix):
                score = 1000 - index * 30
                break
        if "coder" in lower or "code" in lower:
            score -= 120
        if "-vl" in lower or ":vl" in lower or "vision" in lower:
            score -= 80
        if "latest" in lower:
            score += 5
        if score > best_score:
            best_score = score
            best = candidate
    return best


class OllamaClient:
    """Optional compatibility adapter.

    Even when a caller explicitly selects Ollama, an unavailable Ollama process
    must not make AuroraFox unavailable. The adapter falls through to AuroraFox
    local Core and finally local knowledge.
    """

    def __init__(self, base_url: str = "http://127.0.0.1:11434", preferred_model: str = "qwen3:8b"):
        self.base_url = base_url.rstrip("/")
        self.preferred_model = preferred_model
        user_root = Path(os.getenv("AURORAFOX_USER_DIR", str(Path.home() / ".aurorafox"))).resolve()
        self.local_core = AuroraLocalCoreClient(user_root)
        self.local_knowledge = AuroraKnowledgeFallback(user_root)

    def models(self) -> list[str]:
        response = requests.get(f"{self.base_url}/api/tags", timeout=4)
        response.raise_for_status()
        payload = response.json()
        out: list[str] = []
        for item in payload.get("models", []):
            if isinstance(item, dict):
                name = str(item.get("name") or item.get("model") or "").strip()
                if name and name not in out:
                    out.append(name)
        return out

    def chat(self, messages: list[dict[str, Any]], model: str | None = None, temperature: float = 0.2) -> dict[str, Any]:
        ollama_error = ""
        try:
            installed = self.models()
            selected = model if model in installed and is_chat_model(model) else choose_chat_model(installed, self.preferred_model)
            if not selected:
                raise RuntimeError("Ollama has no compatible chat model")
            response = requests.post(
                f"{self.base_url}/api/chat",
                json={
                    "model": selected,
                    "messages": messages,
                    "stream": False,
                    "options": {"temperature": temperature},
                },
                timeout=180,
            )
            response.raise_for_status()
            payload = response.json()
            message = payload.get("message", {}) if isinstance(payload, dict) else {}
            content = str(message.get("content", ""))
            if not content.strip():
                raise RuntimeError("Ollama returned an empty answer")
            return {
                "ok": True,
                "content": content,
                "model": selected,
                "runtime": "ollama",
                "raw": payload,
            }
        except Exception as exc:
            ollama_error = str(exc)

        try:
            local = self.local_core.chat(messages, temperature=temperature)
            local["compatibility_fallback"] = {"from": "ollama", "error": ollama_error[:1000]}
            return local
        except Exception as local_exc:
            user_message = ""
            for item in reversed(messages):
                if isinstance(item, dict) and str(item.get("role", "")) == "user":
                    user_message = str(item.get("content", ""))
                    break
            local = self.local_knowledge.reply(user_message)
            local["compatibility_fallback"] = {
                "from": "ollama",
                "error": ollama_error[:1000],
                "local_core_error": str(local_exc)[:1000],
            }
            return local
